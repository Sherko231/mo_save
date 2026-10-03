import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saving_challenge.dart';

class ChallengeStorage {
  ChallengeStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _storageKey = 'saving_challenges_v1';

  final SharedPreferencesAsync _preferences;

  Future<List<SavingChallenge>> loadChallenges() async {
    final String? raw = await _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return <SavingChallenge>[];
    }

    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => SavingChallenge.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } on FormatException {
      return <SavingChallenge>[];
    } on TypeError {
      return <SavingChallenge>[];
    }
  }

  Future<void> saveChallenges(List<SavingChallenge> challenges) async {
    final String encoded = jsonEncode(
      challenges.map((challenge) => challenge.toJson()).toList(growable: false),
    );
    await _preferences.setString(_storageKey, encoded);
  }
}
