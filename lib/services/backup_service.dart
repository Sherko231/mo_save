import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';

import 'financial_ledger_storage.dart';
import 'local_database.dart';
import 'notification_preferences_storage.dart';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupSummary {
  const BackupSummary({
    required this.createdAt,
    required this.databaseSchemaVersion,
    required this.transactionCount,
    required this.challengeCount,
    required this.expensePlanCount,
  });

  final DateTime createdAt;
  final int databaseSchemaVersion;
  final int transactionCount;
  final int challengeCount;
  final int expensePlanCount;
}

class BackupPickResult {
  const BackupPickResult({
    required this.fileName,
    required this.bytes,
    required this.summary,
  });

  final String fileName;
  final Uint8List bytes;
  final BackupSummary summary;
}

class BackupService {
  BackupService({
    LocalDatabase? database,
    NotificationPreferencesStorage? notificationPreferencesStorage,
  })  : _database = database ?? LocalDatabase.instance,
        _notificationPreferencesStorage = notificationPreferencesStorage ??
            NotificationPreferencesStorage();

  static const String backupExtension = 'mosave';
  static const String _format = 'mo_save_backup';
  static const int _formatVersion = 1;
  static const int _maxBackupBytes = 25 * 1024 * 1024;

  static const List<String> _tableNames = <String>[
    'app_metadata',
    'financial_settings',
    'challenges',
    'challenge_cells',
    'recurring_expense_items',
    'financial_events',
    'financial_event_entries',
    'financial_event_revisions',
  ];

  static const List<String> _deleteOrder = <String>[
    'financial_event_revisions',
    'financial_event_entries',
    'financial_events',
    'challenge_cells',
    'recurring_expense_items',
    'financial_settings',
    'challenges',
    'app_metadata',
  ];

  Future<bool> exportToFile() async {
    final Uint8List bytes = await createBackupBytes();
    final DateTime now = DateTime.now();
    final String fileName =
        'mo_save_${now.year}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}.$backupExtension';

    final Uri? saved = await FilePicker.saveFile(
      dialogTitle: 'حفظ نسخة Mo Save الاحتياطية',
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: const <String>[backupExtension],
    );
    return saved != null;
  }

  Future<BackupPickResult?> pickBackupFile() async {
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'اختر نسخة Mo Save الاحتياطية',
      type: FileType.custom,
      allowedExtensions: const <String>[backupExtension, 'json'],
    );
    if (file == null) return null;

    final int? reportedLength = file.lengthSync() ?? await file.length();
    if (reportedLength != null && reportedLength > _maxBackupBytes) {
      throw const BackupException('ملف النسخة الاحتياطية أكبر من الحد المسموح.');
    }

    final Uint8List bytes = await file.readAsBytes();
    final BackupSummary summary = inspectBackupBytes(bytes);
    return BackupPickResult(
      fileName: file.name,
      bytes: bytes,
      summary: summary,
    );
  }

  Future<Uint8List> createBackupBytes() async {
    final Database database = await _database.database;
    final Map<String, List<Map<String, Object?>>> tables =
        await database.transaction((transaction) async {
      final Map<String, List<Map<String, Object?>>> snapshot =
          <String, List<Map<String, Object?>>>{};
      for (final String table in _tableNames) {
        final List<Map<String, Object?>> rows = await transaction.query(table);
        snapshot[table] = rows
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false);
      }
      return snapshot;
    });

    final NotificationPreferences notifications =
        await _notificationPreferencesStorage.load();
    final DateTime createdAt = DateTime.now().toUtc();

    final String payloadJson = jsonEncode(<String, Object?>{
      'tables': tables,
      'notificationPreferences': <String, bool>{
        'weeklyIncomeEnabled': notifications.weeklyIncomeEnabled,
        'monthlyIncomeEnabled': notifications.monthlyIncomeEnabled,
        'goalDeadlinesEnabled': notifications.goalDeadlinesEnabled,
      },
    });
    final String checksum = sha256.convert(utf8.encode(payloadJson)).toString();

    final String outerJson = jsonEncode(<String, Object?>{
      'format': _format,
      'formatVersion': _formatVersion,
      'databaseSchemaVersion': LocalDatabase.schemaVersion,
      'createdAtUtc': createdAt.toIso8601String(),
      'checksumSha256': checksum,
      'payloadJson': payloadJson,
    });
    return Uint8List.fromList(utf8.encode(outerJson));
  }

  BackupSummary inspectBackupBytes(Uint8List bytes) {
    final _DecodedBackup decoded = _decodeAndValidate(bytes);
    final Map<String, List<Map<String, Object?>>> tables = decoded.tables;
    return BackupSummary(
      createdAt: decoded.createdAt,
      databaseSchemaVersion: decoded.databaseSchemaVersion,
      transactionCount: tables['financial_events']!.length,
      challengeCount: tables['challenges']!.length,
      expensePlanCount: tables['recurring_expense_items']!.length,
    );
  }

  Future<BackupSummary> restoreBackupBytes(Uint8List bytes) async {
    final _DecodedBackup decoded = _decodeAndValidate(bytes);
    final NotificationPreferences previousNotifications =
        await _notificationPreferencesStorage.load();

    await _notificationPreferencesStorage.save(decoded.notifications);

    try {
      final Database database = await _database.database;
      await database.transaction((transaction) async {
        for (final String table in _deleteOrder) {
          await transaction.delete(table);
        }

        await _insertRows(transaction, 'app_metadata', decoded.tables);
        await _insertRows(transaction, 'financial_settings', decoded.tables);
        await _insertRows(transaction, 'challenges', decoded.tables);
        await _insertRows(transaction, 'challenge_cells', decoded.tables);
        await _insertRows(
          transaction,
          'recurring_expense_items',
          decoded.tables,
        );
        await _insertFinancialEvents(transaction, decoded.tables);
        await _insertRows(
          transaction,
          'financial_event_entries',
          decoded.tables,
        );
        await _insertRows(
          transaction,
          'financial_event_revisions',
          decoded.tables,
        );
      });
    } catch (_) {
      try {
        await _notificationPreferencesStorage.save(previousNotifications);
      } catch (_) {
        // The SQLite restore is still fully rolled back. Notification toggles
        // are auxiliary preferences and must not mask the original failure.
      }
      rethrow;
    }

    FinancialLedgerStorage.notifyChanged();
    return BackupSummary(
      createdAt: decoded.createdAt,
      databaseSchemaVersion: decoded.databaseSchemaVersion,
      transactionCount: decoded.tables['financial_events']!.length,
      challengeCount: decoded.tables['challenges']!.length,
      expensePlanCount: decoded.tables['recurring_expense_items']!.length,
    );
  }

  _DecodedBackup _decodeAndValidate(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const BackupException('ملف النسخة الاحتياطية فارغ.');
    }
    if (bytes.length > _maxBackupBytes) {
      throw const BackupException('ملف النسخة الاحتياطية أكبر من الحد المسموح.');
    }

    final Object? decodedOuter;
    try {
      decodedOuter = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const BackupException('الملف ليس نسخة Mo Save احتياطية صالحة.');
    }
    if (decodedOuter is! Map<String, dynamic>) {
      throw const BackupException('بنية ملف النسخة الاحتياطية غير صالحة.');
    }

    if (decodedOuter['format'] != _format ||
        decodedOuter['formatVersion'] != _formatVersion) {
      throw const BackupException('إصدار ملف النسخة الاحتياطية غير مدعوم.');
    }

    final Object? schemaRaw = decodedOuter['databaseSchemaVersion'];
    if (schemaRaw is! num) {
      throw const BackupException('إصدار قاعدة البيانات مفقود من النسخة.');
    }
    final int databaseSchemaVersion = schemaRaw.toInt();
    if (databaseSchemaVersion != LocalDatabase.schemaVersion) {
      throw BackupException(
        'هذه النسخة تستخدم قاعدة بيانات v$databaseSchemaVersion، '
        'بينما هذا الإصدار من التطبيق يستخدم v${LocalDatabase.schemaVersion}.',
      );
    }

    final String? payloadJson = decodedOuter['payloadJson'] as String?;
    final String? expectedChecksum = decodedOuter['checksumSha256'] as String?;
    final String? createdAtRaw = decodedOuter['createdAtUtc'] as String?;
    if (payloadJson == null || expectedChecksum == null || createdAtRaw == null) {
      throw const BackupException('ملف النسخة الاحتياطية ناقص.');
    }

    final String actualChecksum =
        sha256.convert(utf8.encode(payloadJson)).toString();
    if (actualChecksum != expectedChecksum) {
      throw const BackupException(
        'فشل التحقق من سلامة النسخة الاحتياطية. قد يكون الملف تالفاً أو معدلاً.',
      );
    }

    final DateTime? createdAt = DateTime.tryParse(createdAtRaw)?.toLocal();
    if (createdAt == null) {
      throw const BackupException('تاريخ إنشاء النسخة الاحتياطية غير صالح.');
    }

    final Object? payloadRaw;
    try {
      payloadRaw = jsonDecode(payloadJson);
    } catch (_) {
      throw const BackupException('محتوى النسخة الاحتياطية غير قابل للقراءة.');
    }
    if (payloadRaw is! Map<String, dynamic>) {
      throw const BackupException('محتوى النسخة الاحتياطية غير صالح.');
    }

    final Object? tablesRaw = payloadRaw['tables'];
    if (tablesRaw is! Map<String, dynamic>) {
      throw const BackupException('جداول النسخة الاحتياطية مفقودة.');
    }

    final Map<String, List<Map<String, Object?>>> tables =
        <String, List<Map<String, Object?>>>{};
    for (final String table in _tableNames) {
      final Object? rowsRaw = tablesRaw[table];
      if (rowsRaw is! List<dynamic>) {
        throw BackupException('الجدول $table مفقود أو غير صالح في النسخة.');
      }
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      for (final Object? rowRaw in rowsRaw) {
        if (rowRaw is! Map<String, dynamic>) {
          throw BackupException('يوجد سجل غير صالح ضمن الجدول $table.');
        }
        rows.add(Map<String, Object?>.from(rowRaw));
      }
      tables[table] = rows;
    }

    if (tables['financial_settings']!.length > 1) {
      throw const BackupException('النسخة تحتوي أكثر من سجل إعدادات مالية واحد.');
    }

    final Object? notificationsRaw = payloadRaw['notificationPreferences'];
    if (notificationsRaw is! Map<String, dynamic>) {
      throw const BackupException('تفضيلات التنبيهات مفقودة من النسخة.');
    }
    final NotificationPreferences notifications = NotificationPreferences(
      weeklyIncomeEnabled:
          _requireBool(notificationsRaw, 'weeklyIncomeEnabled'),
      monthlyIncomeEnabled:
          _requireBool(notificationsRaw, 'monthlyIncomeEnabled'),
      goalDeadlinesEnabled:
          _requireBool(notificationsRaw, 'goalDeadlinesEnabled'),
    );

    return _DecodedBackup(
      createdAt: createdAt,
      databaseSchemaVersion: databaseSchemaVersion,
      tables: tables,
      notifications: notifications,
    );
  }

  static Future<void> _insertRows(
    DatabaseExecutor transaction,
    String table,
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    for (final Map<String, Object?> row in tables[table]!) {
      await transaction.insert(
        table,
        Map<String, Object?>.from(row),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  static Future<void> _insertFinancialEvents(
    DatabaseExecutor transaction,
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    final List<Map<String, Object?>> rows = tables['financial_events']!;

    // source_event_id is a self-reference. Insert all event identities first,
    // then restore those links after every referenced row exists.
    for (final Map<String, Object?> original in rows) {
      final Map<String, Object?> row = Map<String, Object?>.from(original);
      row['source_event_id'] = null;
      await transaction.insert(
        'financial_events',
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    for (final Map<String, Object?> row in rows) {
      final Object? sourceEventId = row['source_event_id'];
      if (sourceEventId == null) continue;
      final Object? eventId = row['id'];
      if (eventId is! String || sourceEventId is! String) {
        throw const BackupException('رابط حركة مالية غير صالح في النسخة.');
      }
      final int updated = await transaction.update(
        'financial_events',
        <String, Object?>{'source_event_id': sourceEventId},
        where: 'id = ?',
        whereArgs: <Object?>[eventId],
      );
      if (updated != 1) {
        throw const BackupException('تعذر استعادة رابط حركة مالية.');
      }
    }
  }

  static bool _requireBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is! bool) {
      throw BackupException('القيمة $key غير صالحة في النسخة الاحتياطية.');
    }
    return value;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _DecodedBackup {
  const _DecodedBackup({
    required this.createdAt,
    required this.databaseSchemaVersion,
    required this.tables,
    required this.notifications,
  });

  final DateTime createdAt;
  final int databaseSchemaVersion;
  final Map<String, List<Map<String, Object?>>> tables;
  final NotificationPreferences notifications;
}
