import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/financial_event.dart';
import 'financial_ledger_storage.dart';
import 'local_database.dart';

class TransactionHistoryRecord {
  const TransactionHistoryRecord({
    required this.event,
    required this.isDeleted,
    required this.revisionCount,
  });

  final FinancialEvent event;
  final bool isDeleted;
  final int revisionCount;
}

class FinancialEventRevision {
  const FinancialEventRevision({
    required this.action,
    required this.snapshot,
    required this.changedAt,
  });

  final String action;
  final FinancialEvent snapshot;
  final DateTime changedAt;

  bool get isDelete => action == 'delete';
}

class TransactionMutationException implements Exception {
  const TransactionMutationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TransactionHistoryService {
  TransactionHistoryService({
    LocalDatabase? database,
    FinancialLedgerStorage? ledger,
  })  : _database = database ?? LocalDatabase.instance,
        _ledger = ledger ?? FinancialLedgerStorage();

  final LocalDatabase _database;
  final FinancialLedgerStorage _ledger;

  Future<List<TransactionHistoryRecord>> loadMonth(
    DateTime month, {
    FinancialEventType? type,
    FinancialUnit? unit,
    FinancialFund? fund,
  }) async {
    final DateTime start = DateTime(month.year, month.month, 1);
    final DateTime end = DateTime(month.year, month.month + 1, 1);
    final List<FinancialEvent> active = await _ledger.loadEvents(
      from: start,
      to: end,
      type: type,
    );
    final Database database = await _database.database;

    final Map<String, int> revisionCounts = await _loadRevisionCounts(database);
    final List<TransactionHistoryRecord> result = active
        .where((event) => unit == null || _containsUnit(event, unit))
        .where((event) => fund == null ||
            event.entries.any((entry) => entry.fund == fund &&
                (entry.affectsBalance ||
                    event.type == FinancialEventType.fundTransfer)))
        .map(
          (event) => TransactionHistoryRecord(
            event: event,
            isDeleted: false,
            revisionCount: revisionCounts[event.id] ?? 0,
          ),
        )
        .toList();

    final List<Map<String, Object?>> deletedRows = await database.query(
      'financial_event_revisions',
      columns: <String>['event_id', 'snapshot_json'],
      where: 'action = ?',
      whereArgs: const <Object?>['delete'],
    );

    for (final Map<String, Object?> row in deletedRows) {
      final FinancialEvent event = _eventFromJson(
        jsonDecode(row['snapshot_json']! as String) as Map<String, dynamic>,
      );
      final DateTime localDate = event.occurredAt.toLocal();
      if (localDate.isBefore(start) || !localDate.isBefore(end)) {
        continue;
      }
      if (type != null && event.type != type) {
        continue;
      }
      if (unit != null && !_containsUnit(event, unit)) {
        continue;
      }
      if (fund != null && !event.entries.any((entry) =>
          entry.fund == fund && (entry.affectsBalance ||
              event.type == FinancialEventType.fundTransfer))) {
        continue;
      }
      result.add(
        TransactionHistoryRecord(
          event: event,
          isDeleted: true,
          revisionCount: revisionCounts[event.id] ?? 1,
        ),
      );
    }

    result.sort((a, b) {
      final int date = b.event.occurredAt.compareTo(a.event.occurredAt);
      if (date != 0) return date;
      return b.event.updatedAt.compareTo(a.event.updatedAt);
    });
    return result;
  }

  Future<List<FinancialEventRevision>> loadRevisions(String eventId) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'financial_event_revisions',
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
      orderBy: 'changed_at_ms DESC, id DESC',
    );

    return rows
        .map(
          (row) => FinancialEventRevision(
            action: row['action']! as String,
            snapshot: _eventFromJson(
              jsonDecode(row['snapshot_json']! as String)
                  as Map<String, dynamic>,
            ),
            changedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['changed_at_ms']! as num).toInt(),
              isUtc: true,
            ),
          ),
        )
        .toList(growable: false);
  }

  bool isWorkflowManaged(FinancialEvent event) {
    return event.type == FinancialEventType.savingContribution;
  }

  bool canCorrectAmounts(FinancialEvent event) => !isWorkflowManaged(event);

  bool canDelete(FinancialEvent event) => !isWorkflowManaged(event);

  Future<void> updateMetadata({
    required String eventId,
    required DateTime occurredAt,
    required String? category,
    required String? note,
  }) async {
    final Database database = await _database.database;

    await database.transaction((transaction) async {
      final FinancialEvent current = await _requireEvent(transaction, eventId);
      if (isWorkflowManaged(current)) {
        throw const TransactionMutationException(
          'مساهمة هدف الادخار مرتبطة بشبكة التحدي. عدّلها من التحدي نفسه.',
        );
      }

      final DateTime normalizedDate = DateTime(
        occurredAt.year,
        occurredAt.month,
        occurredAt.day,
        current.occurredAt.toLocal().hour,
        current.occurredAt.toLocal().minute,
      ).toUtc();
      if (current.recurrenceKey != null &&
          !current.recurrenceKey!.startsWith('manual-cash:') &&
          !_sameLocalDay(normalizedDate, current.occurredAt)) {
        throw const TransactionMutationException(
          'تاريخ الحركة الدورية مرتبط بموعدها الأصلي ولا يمكن نقله ليوم آخر.',
        );
      }

      await _writeRevision(transaction, current, action: 'update');
      await transaction.update(
        'financial_events',
        <String, Object?>{
          'occurred_at_ms': normalizedDate.millisecondsSinceEpoch,
          'category': _normalizeOptionalText(category),
          'note': _normalizeOptionalText(note),
          'updated_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[eventId],
      );
    });

    FinancialLedgerStorage.notifyChanged();
  }

  Future<void> correctAmounts({
    required String eventId,
    required List<int> absoluteAmountsMicros,
  }) async {
    final Database database = await _database.database;

    await database.transaction((transaction) async {
      final FinancialEvent current = await _requireEvent(transaction, eventId);
      if (!canCorrectAmounts(current)) {
        throw const TransactionMutationException(
          'مساهمة هدف الادخار تتبع شبكة التحدي ولا تُصحح من سجل الحركات.',
        );
      }
      if (absoluteAmountsMicros.length != current.entries.length ||
          absoluteAmountsMicros.any((amount) => amount <= 0)) {
        throw const TransactionMutationException(
          'يجب إدخال مبلغ موجب لكل جزء من الحركة.',
        );
      }

      final List<LedgerEntry> correctedEntries = <LedgerEntry>[];
      for (int index = 0; index < current.entries.length; index++) {
        final LedgerEntry old = current.entries[index];
        final int sign = old.amountMicros < 0 ? -1 : 1;
        correctedEntries.add(
          LedgerEntry(
            unit: old.unit,
            amountMicros: sign * absoluteAmountsMicros[index],
            affectsBalance: old.affectsBalance,
            role: old.role,
            fund: old.fund,
          ),
        );
      }

      if (_sameEntries(current.entries, correctedEntries)) {
        return;
      }

      if (await _hasDependents(transaction, current.id)) {
        throw const TransactionMutationException(
          'هذه الحركة مرتبطة بحركة لاحقة. عدّل أو ألغِ الحركة التابعة أولاً.',
        );
      }

      double? executedRate = current.executedSypPerUsd;
      if (current.type == FinancialEventType.currencyConversion) {
        executedRate = _deriveConversionRate(correctedEntries);
      }

      final FinancialEvent corrected = current.copyWith(
        entries: correctedEntries,
        executedSypPerUsd: executedRate,
        updatedAt: DateTime.now().toUtc(),
      );

      await _validateSemanticShape(transaction, corrected);
      await _ensureReplacementBalancesSafe(
        transaction,
        oldEvent: current,
        newEvent: corrected,
      );
      final fundBefore = await FinancialLedgerStorage.loadFundBalancesForMutation(transaction);
      await _writeRevision(transaction, current, action: 'update');

      await transaction.update(
        'financial_events',
        <String, Object?>{
          'executed_syp_per_usd': corrected.executedSypPerUsd,
          'updated_at_ms': corrected.updatedAt.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[current.id],
      );
      await transaction.delete(
        'financial_event_entries',
        where: 'event_id = ?',
        whereArgs: <Object?>[current.id],
      );
      await _insertEntries(transaction, corrected);
      await FinancialLedgerStorage.ensureFundMutationSafe(transaction, fundBefore);
    });

    FinancialLedgerStorage.notifyChanged();
  }

  Future<void> deleteEvent(String eventId) async {
    final Database database = await _database.database;

    await database.transaction((transaction) async {
      final FinancialEvent current = await _requireEvent(transaction, eventId);
      if (!canDelete(current)) {
        throw const TransactionMutationException(
          'مساهمة هدف الادخار مرتبطة بالتحدي. غيّر تقدم التحدي بدل حذفها من السجل.',
        );
      }
      if (await _hasDependents(transaction, current.id)) {
        throw const TransactionMutationException(
          'لا يمكن حذف هذه الحركة قبل حذف أو تعديل الحركة التابعة لها.',
        );
      }

      await _ensureDeletionBalancesSafe(transaction, current);
      final fundBefore = await FinancialLedgerStorage.loadFundBalancesForMutation(transaction);
      await _writeRevision(transaction, current, action: 'delete');
      await transaction.delete(
        'financial_events',
        where: 'id = ?',
        whereArgs: <Object?>[current.id],
      );
      await FinancialLedgerStorage.ensureFundMutationSafe(transaction, fundBefore);
    });

    FinancialLedgerStorage.notifyChanged();
  }

  Future<Map<String, int>> _loadRevisionCounts(Database database) async {
    final List<Map<String, Object?>> rows = await database.rawQuery('''
      SELECT event_id, COUNT(*) AS revision_count
      FROM financial_event_revisions
      GROUP BY event_id
    ''');
    return <String, int>{
      for (final Map<String, Object?> row in rows)
        row['event_id']! as String: (row['revision_count']! as num).toInt(),
    };
  }

  static Future<FinancialEvent> _requireEvent(
    DatabaseExecutor database,
    String eventId,
  ) async {
    final List<Map<String, Object?>> rows = await database.query(
      'financial_events',
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const TransactionMutationException('الحركة لم تعد موجودة.');
    }

    final Map<String, Object?> row = rows.single;
    final List<Map<String, Object?>> entryRows = await database.query(
      'financial_event_entries',
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
      orderBy: 'position ASC',
    );

    return FinancialEvent(
      id: eventId,
      type: _parseEventType(row['event_type']! as String),
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        (row['occurred_at_ms']! as num).toInt(),
        isUtc: true,
      ),
      entries: entryRows
          .map(
            (entry) => LedgerEntry(
              unit: _parseUnit(entry['unit']! as String),
              amountMicros: (entry['amount_micros']! as num).toInt(),
              affectsBalance:
                  (entry['affects_balance']! as num).toInt() == 1,
              role: _parseEntryRole(entry['entry_role'] as String?),
              fund: FinancialFund.values.byName(entry['fund']! as String),
            ),
          )
          .toList(growable: false),
      note: row['note'] as String?,
      category: row['category'] as String?,
      relatedChallengeId: row['related_challenge_id'] as String?,
      relatedGoalId: row['related_goal_id'] as String?,
      recurrenceKey: row['recurrence_key'] as String?,
      sourceEventId: row['source_event_id'] as String?,
      executedSypPerUsd:
          (row['executed_syp_per_usd'] as num?)?.toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at_ms']! as num).toInt(),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at_ms']! as num).toInt(),
        isUtc: true,
      ),
    );
  }

  static Future<void> _validateSemanticShape(
    DatabaseExecutor database,
    FinancialEvent event,
  ) async {
    switch (event.type) {
      case FinancialEventType.income:
        if (event.entries.any(
          (entry) => !entry.affectsBalance || entry.amountMicros <= 0,
        )) {
          throw const TransactionMutationException(
            'الدخل يجب أن يبقى إضافة موجبة إلى الرصيد.',
          );
        }
        break;
      case FinancialEventType.openingBalance:
        if (event.entries.length != 1 ||
            event.entries.any((entry) => !entry.affectsBalance ||
                entry.amountMicros <= 0 ||
                entry.unit == FinancialUnit.goldGram)) {
          throw const TransactionMutationException(
            'الرصيد الافتتاحي يجب أن يكون مبلغاً نقدياً موجباً.',
          );
        }
        break;
      case FinancialEventType.expense:
        if (event.entries.any(
          (entry) => !entry.affectsBalance || entry.amountMicros >= 0,
        )) {
          throw const TransactionMutationException(
            'المصروف يجب أن يبقى خصماً من الرصيد.',
          );
        }
        break;
      case FinancialEventType.currencyConversion:
        _deriveConversionRate(event.entries);
        break;
      case FinancialEventType.goldPurchase:
        _validateAssetExchange(
          event.entries,
          sourceAllowed: const <FinancialUnit>{
            FinancialUnit.syp,
            FinancialUnit.usd,
          },
          destinationAllowed: const <FinancialUnit>{FinancialUnit.goldGram},
        );
        break;
      case FinancialEventType.goldSale:
        _validateAssetExchange(
          event.entries,
          sourceAllowed: const <FinancialUnit>{FinancialUnit.goldGram},
          destinationAllowed: const <FinancialUnit>{
            FinancialUnit.syp,
            FinancialUnit.usd,
          },
        );
        break;
      case FinancialEventType.weeklyAllocation:
        await _validateWeeklyAllocation(database, event);
        break;
      case FinancialEventType.savingContribution:
        throw const TransactionMutationException(
          'مساهمة هدف الادخار تتبع التحدي ولا تُصحح يدوياً.',
        );
      case FinancialEventType.manualAdjustment:
        break;
      case FinancialEventType.fundTransfer:
        if (event.entries.length != 2 ||
            event.entries[0].affectsBalance ||
            event.entries[1].affectsBalance ||
            event.entries[0].unit != event.entries[1].unit ||
            event.entries[0].fund == event.entries[1].fund ||
            event.entries[0].amountMicros >= 0 ||
            event.entries[1].amountMicros <= 0 ||
            event.entries[0].amountMicros != -event.entries[1].amountMicros ||
            event.entries.any((entry) => entry.unit == FinancialUnit.goldGram && entry.fund == FinancialFund.spending)) {
          throw const TransactionMutationException('تحويل الصناديق غير متوازن.');
        }
        break;
    }
  }

  static Future<void> _validateWeeklyAllocation(
    DatabaseExecutor database,
    FinancialEvent event,
  ) async {
    if (event.sourceEventId == null ||
        event.entries.isEmpty ||
        event.entries.any(
          (entry) =>
              entry.affectsBalance ||
              entry.unit != FinancialUnit.syp ||
              entry.amountMicros <= 0,
        )) {
      throw const TransactionMutationException('تقسيم راتب الخميس غير صالح.');
    }

    final FinancialEvent source =
        await _requireEvent(database, event.sourceEventId!);
    final int received = source.entries
        .where(
          (entry) =>
              entry.affectsBalance &&
              entry.unit == FinancialUnit.syp &&
              entry.amountMicros > 0,
        )
        .fold<int>(0, (sum, entry) => sum + entry.amountMicros);
    final int allocated = event.entries.fold<int>(
      0,
      (sum, entry) => sum + entry.amountMicros,
    );
    if (received <= 0 || allocated > received) {
      throw const TransactionMutationException(
        'مجموع التقسيم لا يمكن أن يتجاوز راتب الخميس المستلم.',
      );
    }
  }

  static double _deriveConversionRate(List<LedgerEntry> entries) {
    if (entries.length != 2 ||
        entries.any((entry) => !entry.affectsBalance)) {
      throw const TransactionMutationException(
        'تحويل العملة يجب أن يحتوي خصماً وإضافة فقط.',
      );
    }
    final List<LedgerEntry> negative =
        entries.where((entry) => entry.amountMicros < 0).toList();
    final List<LedgerEntry> positive =
        entries.where((entry) => entry.amountMicros > 0).toList();
    if (negative.length != 1 || positive.length != 1) {
      throw const TransactionMutationException(
        'تحويل العملة يجب أن يحتوي مصدراً ووجهة.',
      );
    }
    final Set<FinancialUnit> pair = <FinancialUnit>{
      negative.single.unit,
      positive.single.unit,
    };
    if (pair.length != 2 ||
        !pair.contains(FinancialUnit.syp) ||
        !pair.contains(FinancialUnit.usd)) {
      throw const TransactionMutationException(
        'التحويل المدعوم هنا هو بين الليرة السورية والدولار فقط.',
      );
    }
    final int sypMicros = entries
        .firstWhere((entry) => entry.unit == FinancialUnit.syp)
        .amountMicros
        .abs();
    final int usdMicros = entries
        .firstWhere((entry) => entry.unit == FinancialUnit.usd)
        .amountMicros
        .abs();
    return sypMicros / usdMicros;
  }

  static void _validateAssetExchange(
    List<LedgerEntry> entries, {
    required Set<FinancialUnit> sourceAllowed,
    required Set<FinancialUnit> destinationAllowed,
  }) {
    if (entries.length != 2 ||
        entries.any((entry) => !entry.affectsBalance)) {
      throw const TransactionMutationException('حركة الأصل يجب أن تحوي طرفين.');
    }
    final List<LedgerEntry> negative =
        entries.where((entry) => entry.amountMicros < 0).toList();
    final List<LedgerEntry> positive =
        entries.where((entry) => entry.amountMicros > 0).toList();
    if (negative.length != 1 ||
        positive.length != 1 ||
        !sourceAllowed.contains(negative.single.unit) ||
        !destinationAllowed.contains(positive.single.unit)) {
      throw const TransactionMutationException('تركيب حركة الأصل غير صالح.');
    }
  }

  static Future<void> _ensureReplacementBalancesSafe(
    DatabaseExecutor database, {
    required FinancialEvent oldEvent,
    required FinancialEvent newEvent,
  }) async {
    final Map<FinancialUnit, int> balances = await _loadBalances(database);
    for (final FinancialUnit unit in FinancialUnit.values) {
      final int current = balances[unit] ?? 0;
      final int after = current -
          oldEvent.balanceDeltaMicros(unit) +
          newEvent.balanceDeltaMicros(unit);
      if (after < 0 && after < current) {
        throw TransactionMutationException(
          'التصحيح سيجعل رصيد ${_unitLabel(unit)} سالباً. صحح الحركات اللاحقة أولاً.',
        );
      }
    }
  }

  static Future<void> _ensureDeletionBalancesSafe(
    DatabaseExecutor database,
    FinancialEvent event,
  ) async {
    final Map<FinancialUnit, int> balances = await _loadBalances(database);
    for (final FinancialUnit unit in FinancialUnit.values) {
      final int current = balances[unit] ?? 0;
      final int after = current - event.balanceDeltaMicros(unit);
      if (after < 0 && after < current) {
        throw TransactionMutationException(
          'حذف الحركة سيجعل رصيد ${_unitLabel(unit)} سالباً. لا يمكن حذفها قبل تصحيح الحركات اللاحقة.',
        );
      }
    }
  }

  static Future<Map<FinancialUnit, int>> _loadBalances(
    DatabaseExecutor database,
  ) async {
    final List<Map<String, Object?>> rows = await database.rawQuery('''
      SELECT unit, COALESCE(SUM(amount_micros), 0) AS balance_micros
      FROM financial_event_entries
      WHERE affects_balance = 1
      GROUP BY unit
    ''');
    final Map<FinancialUnit, int> result = <FinancialUnit, int>{
      for (final FinancialUnit unit in FinancialUnit.values) unit: 0,
    };
    for (final Map<String, Object?> row in rows) {
      result[_parseUnit(row['unit']! as String)] =
          (row['balance_micros']! as num).toInt();
    }
    return result;
  }

  static Future<bool> _hasDependents(
    DatabaseExecutor database,
    String eventId,
  ) async {
    final List<Map<String, Object?>> rows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS dependency_count
      FROM financial_events
      WHERE source_event_id = ?
      ''',
      <Object?>[eventId],
    );
    return (rows.single['dependency_count']! as num).toInt() > 0;
  }

  static Future<void> _writeRevision(
    DatabaseExecutor database,
    FinancialEvent event, {
    required String action,
  }) async {
    await database.insert(
      'financial_event_revisions',
      <String, Object?>{
        'event_id': event.id,
        'action': action,
        'snapshot_json': jsonEncode(_eventToJson(event)),
        'changed_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
    );
  }

  static Future<void> _insertEntries(
    DatabaseExecutor database,
    FinancialEvent event,
  ) async {
    for (int index = 0; index < event.entries.length; index++) {
      final LedgerEntry entry = event.entries[index];
      await database.insert(
        'financial_event_entries',
        <String, Object?>{
          'event_id': event.id,
          'position': index,
          'unit': entry.unit.name,
          'amount_micros': entry.amountMicros,
          'affects_balance': entry.affectsBalance ? 1 : 0,
          'entry_role': entry.role?.name,
          'fund': entry.fund.name,
        },
      );
    }
  }

  static Map<String, dynamic> _eventToJson(FinancialEvent event) {
    return <String, dynamic>{
      'id': event.id,
      'type': event.type.name,
      'occurredAtMs': event.occurredAt.millisecondsSinceEpoch,
      'note': event.note,
      'category': event.category,
      'relatedChallengeId': event.relatedChallengeId,
      'relatedGoalId': event.relatedGoalId,
      'recurrenceKey': event.recurrenceKey,
      'sourceEventId': event.sourceEventId,
      'executedSypPerUsd': event.executedSypPerUsd,
      'createdAtMs': event.createdAt.millisecondsSinceEpoch,
      'updatedAtMs': event.updatedAt.millisecondsSinceEpoch,
      'entries': event.entries
          .map(
            (entry) => <String, dynamic>{
              'unit': entry.unit.name,
              'amountMicros': entry.amountMicros,
              'affectsBalance': entry.affectsBalance,
              'role': entry.role?.name,
              'fund': entry.fund.name,
            },
          )
          .toList(growable: false),
    };
  }

  static FinancialEvent _eventFromJson(Map<String, dynamic> json) {
    return FinancialEvent(
      id: json['id']! as String,
      type: _parseEventType(json['type']! as String),
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        (json['occurredAtMs']! as num).toInt(),
        isUtc: true,
      ),
      entries: (json['entries']! as List<dynamic>)
          .map(
            (raw) {
              final Map<String, dynamic> entry = raw as Map<String, dynamic>;
              return LedgerEntry(
                unit: _parseUnit(entry['unit']! as String),
                amountMicros: (entry['amountMicros']! as num).toInt(),
                affectsBalance: entry['affectsBalance'] as bool? ?? true,
                role: _parseEntryRole(entry['role'] as String?),
                fund: FinancialFund.values.byName(entry['fund'] as String? ?? 'unallocated'),
              );
            },
          )
          .toList(growable: false),
      note: json['note'] as String?,
      category: json['category'] as String?,
      relatedChallengeId: json['relatedChallengeId'] as String?,
      relatedGoalId: json['relatedGoalId'] as String?,
      recurrenceKey: json['recurrenceKey'] as String?,
      sourceEventId: json['sourceEventId'] as String?,
      executedSypPerUsd: (json['executedSypPerUsd'] as num?)?.toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAtMs']! as num).toInt(),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAtMs']! as num).toInt(),
        isUtc: true,
      ),
    );
  }

  static bool _containsUnit(FinancialEvent event, FinancialUnit unit) {
    return event.entries.any((entry) => entry.unit == unit);
  }

  static bool _sameEntries(List<LedgerEntry> a, List<LedgerEntry> b) {
    if (a.length != b.length) return false;
    for (int index = 0; index < a.length; index++) {
      if (a[index].unit != b[index].unit ||
          a[index].amountMicros != b[index].amountMicros ||
          a[index].affectsBalance != b[index].affectsBalance ||
          a[index].role != b[index].role ||
          a[index].fund != b[index].fund) {
        return false;
      }
    }
    return true;
  }

  static bool _sameLocalDay(DateTime a, DateTime b) {
    final DateTime localA = a.toLocal();
    final DateTime localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  static String? _normalizeOptionalText(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static FinancialEventType _parseEventType(String value) {
    return FinancialEventType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => throw StateError('Unknown financial event type: $value'),
    );
  }

  static FinancialUnit _parseUnit(String value) {
    return FinancialUnit.values.firstWhere(
      (unit) => unit.name == value,
      orElse: () => throw StateError('Unknown financial unit: $value'),
    );
  }

  static LedgerEntryRole? _parseEntryRole(String? value) {
    if (value == null) return null;
    return LedgerEntryRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => throw StateError('Unknown ledger entry role: $value'),
    );
  }

  static String _unitLabel(FinancialUnit unit) {
    switch (unit) {
      case FinancialUnit.usd:
        return 'الدولار';
      case FinancialUnit.syp:
        return 'الليرة السورية';
      case FinancialUnit.sypNew:
        return 'الليرة السورية الجديدة';
      case FinancialUnit.goldGram:
        return 'الذهب';
    }
  }
}
