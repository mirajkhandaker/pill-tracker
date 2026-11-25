import '../database/database_helper.dart';
import '../models/medicine.dart';
import '../models/schedule.dart';
import 'medicine_repository.dart';

/// A schedule paired with the medicine it belongs to.
typedef ScheduleWithMedicine = ({Schedule schedule, Medicine medicine});

class ScheduleRepository {
  ScheduleRepository(this._db);

  final DatabaseHelper _db;
  static const _table = 'schedules';

  Future<List<Schedule>> getByMedicineId(String medicineId) async {
    final rows = await _db.query(
      _table,
      where: 'medicine_id = ?',
      whereArgs: [medicineId],
      orderBy: 'time_of_day',
    );
    return rows.map(Schedule.fromMap).toList();
  }

  Future<void> insert(Schedule schedule) =>
      _db.insert(_table, schedule.toMap());

  Future<void> update(Schedule schedule) => _db.update(
    _table,
    schedule.toMap(),
    where: 'id = ?',
    whereArgs: [schedule.id],
  );

  Future<void> delete(String id) =>
      _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteByMedicineId(String medicineId) =>
      _db.delete(_table, where: 'medicine_id = ?', whereArgs: [medicineId]);

  /// Schedules of medicines currently being taken (active, non-PRN, course
  /// not finished as of [now]), each joined to its medicine.
  Future<List<ScheduleWithMedicine>> getAllActiveWithMedicine({
    DateTime? now,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT s.*, ${_medicineColumns('m')}
      FROM $_table s
      JOIN medicines m ON m.id = s.medicine_id
      WHERE m.is_active = 1 AND m.is_prn = 0
        AND (m.end_date IS NULL OR m.end_date >= ?)
      ORDER BY s.time_of_day
    ''',
      [MedicineRepository.startOfDayMs(now)],
    );

    return rows.map((row) {
      final schedule = Schedule.fromMap({
        'id': row['id'],
        'medicine_id': row['medicine_id'],
        'time_of_day': row['time_of_day'],
        'dose_amount': row['dose_amount'],
        'is_variable_dose': row['is_variable_dose'],
        'days_of_week': row['days_of_week'],
      });
      final medicine = Medicine.fromMap(_stripPrefix(row, 'm_'));
      return (schedule: schedule, medicine: medicine);
    }).toList();
  }

  /// Aliased medicine columns (`m.name AS m_name, ...`) so the JOIN result can
  /// be split back into a Medicine without colliding with `schedules.id` etc.
  static String _medicineColumns(String alias) {
    const cols = [
      'id',
      'name',
      'dosage_text',
      'notes',
      'form',
      'package_type',
      'dose_unit',
      'units_per_package',
      'packages_in_hand',
      'loose_units',
      'track_inventory',
      'is_prn',
      'refill_threshold_days',
      'is_active',
      'created_at',
      'prescription_id',
      'end_date',
    ];
    return cols.map((c) => '$alias.$c AS ${alias}_$c').join(', ');
  }

  static Map<String, Object?> _stripPrefix(
    Map<String, Object?> row,
    String prefix,
  ) {
    final out = <String, Object?>{};
    for (final entry in row.entries) {
      if (entry.key.startsWith(prefix)) {
        out[entry.key.substring(prefix.length)] = entry.value;
      }
    }
    return out;
  }
}
