import 'dart:convert';

import '../data/database/database_helper.dart';
import '../data/models/dose_log.dart';
import '../data/models/medicine.dart';
import '../data/models/prescription.dart';
import '../data/models/schedule.dart';

/// JSON export/import of the whole database, plus a full wipe.
///
/// Prescription *photos* are not included: a backup is plain text (shared
/// via the clipboard), so it carries prescriptions and medicines but not
/// their images.
abstract final class BackupService {
  static const _marker = 'pilltrack';

  /// v2 added prescriptions; v1 backups (without them) still import.
  static const _formatVersion = 2;

  static Future<String> exportJson(DatabaseHelper db) async {
    final data = <String, Object?>{
      'app': _marker,
      'version': _formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'prescriptions': await db.query('prescriptions'),
      'medicines': await db.query('medicines'),
      'schedules': await db.query('schedules'),
      'dose_logs': await db.query('dose_logs'),
      'settings': await db.query('settings'),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Replaces ALL current data with the backup in [json]. The backup is fully
  /// parsed and validated before anything is written, and the write happens in
  /// one transaction, so a bad file leaves existing data untouched.
  ///
  /// Throws [FormatException] if [json] isn't a valid PillTrack backup.
  static Future<void> importJson(DatabaseHelper db, String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('That text is not valid JSON.');
    }
    if (decoded is! Map || decoded['app'] != _marker) {
      throw const FormatException('This is not a PillTrack backup.');
    }
    final Map<Object?, Object?> backup = decoded;

    List<Map<String, Object?>> rows(String key, {bool optional = false}) {
      final list = backup[key];
      if (list == null && optional) return const [];
      if (list is! List) throw FormatException('Backup is missing "$key".');
      return [for (final r in list) Map<String, Object?>.from(r as Map)];
    }

    final List<Prescription> prescriptions;
    final List<Medicine> medicines;
    final List<Schedule> schedules;
    final List<DoseLog> logs;
    final List<Map<String, Object?>> settings;
    try {
      prescriptions = rows(
        'prescriptions',
        optional: true,
      ).map(Prescription.fromMap).toList();
      medicines = rows('medicines').map(Medicine.fromMap).toList();
      schedules = rows('schedules').map(Schedule.fromMap).toList();
      logs = rows('dose_logs').map(DoseLog.fromMap).toList();
      settings = rows('settings');
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Backup contains invalid data ($e).');
    }

    final database = await db.getDb();
    await database.transaction((txn) async {
      await _clear(txn.delete);
      for (final rx in prescriptions) {
        await txn.insert('prescriptions', rx.toMap());
      }
      for (final m in medicines) {
        await txn.insert('medicines', m.toMap());
      }
      for (final s in schedules) {
        await txn.insert('schedules', s.toMap());
      }
      for (final l in logs) {
        await txn.insert('dose_logs', l.toMap());
      }
      for (final s in settings) {
        await txn.insert('settings', {'key': s['key'], 'value': s['value']});
      }
    });
  }

  /// Deletes every prescription, medicine, schedule, log and setting.
  static Future<void> deleteAll(DatabaseHelper db) async {
    final database = await db.getDb();
    await database.transaction((txn) => _clear(txn.delete));
  }

  // Children before parents so FK constraints are never violated.
  static Future<void> _clear(Future<int> Function(String table) delete) async {
    await delete('dose_logs');
    await delete('schedules');
    await delete('medicines');
    await delete('prescription_photos');
    await delete('prescriptions');
    await delete('settings');
  }
}
