import '../database/database_helper.dart';

/// Key-value app settings persisted in the `settings` table. Lives in SQLite
/// (not shared_preferences) so the background notification isolate can read
/// the same values through its own DB connection.
class SettingsRepository {
  SettingsRepository(this._db);

  final DatabaseHelper _db;
  static const _table = 'settings';

  static const notificationsEnabledKey = 'notifications_enabled';
  static const snoozeMinutesKey = 'snooze_minutes';
  static const longestStreakKey = 'longest_streak';

  /// Unix ms of the first launch after onboarding (for the review prompt).
  static const firstUseAtKey = 'first_use_at';

  /// Set once the one-time store-review prompt has been triggered.
  static const reviewPromptedKey = 'review_prompted';

  Future<String?> get(String key) async {
    final rows = await _db.query(
      _table,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) =>
      _db.insert(_table, {'key': key, 'value': value});

  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final v = await get(key);
    return v == null ? defaultValue : v == 'true';
  }

  Future<void> setBool(String key, bool value) => set(key, value.toString());

  Future<int> getInt(String key, {int defaultValue = 0}) async {
    final v = await get(key);
    return v == null ? defaultValue : int.tryParse(v) ?? defaultValue;
  }

  Future<void> setInt(String key, int value) => set(key, value.toString());
}
