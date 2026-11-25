import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Run SQLite on the host VM for tests.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper helper;

  setUp(() {
    helper = DatabaseHelper.forTesting(inMemoryDatabasePath);
  });

  tearDown(() async {
    await helper.close();
  });

  test('creates all tables', () async {
    final rows = await helper.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = rows.map((r) => r['name'] as String).toSet();
    expect(
      names.containsAll({'medicines', 'schedules', 'dose_logs', 'settings'}),
      isTrue,
    );
  });

  test('inserts and reads back a tablet medicine', () async {
    final tablet = {
      'id': 'med-tablet',
      'name': 'Paracetamol',
      'dosage_text': '500mg',
      'notes': null,
      'form': 'tablet',
      'package_type': 'strip',
      'dose_unit': 'pcs',
      'units_per_package': 10.0,
      'packages_in_hand': 2,
      'loose_units': 3.0,
      'track_inventory': 1,
      'is_prn': 0,
      'refill_threshold_days': 3,
      'is_active': 1,
      'created_at': 1700000000000,
    };
    await helper.insert('medicines', tablet);

    final rows = await helper.query(
      'medicines',
      where: 'id = ?',
      whereArgs: ['med-tablet'],
    );
    expect(rows, hasLength(1));
    final row = rows.first;
    expect(row['name'], 'Paracetamol');
    expect(row['form'], 'tablet');
    expect(row['dose_unit'], 'pcs');
    expect(row['units_per_package'], 10.0);
    expect(row['packages_in_hand'], 2);
    expect(row['loose_units'], 3.0);
    expect(row['track_inventory'], 1);
  });

  test('inserts an insulin medicine with a variable-dose schedule', () async {
    final insulin = {
      'id': 'med-insulin',
      'name': 'Lantus',
      'dosage_text': '10 IU',
      'notes': 'sliding scale',
      'form': 'injection',
      'package_type': 'pen',
      'dose_unit': 'IU',
      'units_per_package': 300.0,
      'packages_in_hand': 1,
      'loose_units': 0.0,
      'track_inventory': 1,
      'is_prn': 0,
      'refill_threshold_days': 5,
      'is_active': 1,
      'created_at': 1700000000000,
    };
    await helper.insert('medicines', insulin);
    await helper.insert('schedules', {
      'id': 'sch-1',
      'medicine_id': 'med-insulin',
      'time_of_day': '08:00',
      'dose_amount': 10.0,
      'is_variable_dose': 1,
      'days_of_week': '1,2,3,4,5,6,7',
    });

    final meds = await helper.query(
      'medicines',
      where: 'form = ?',
      whereArgs: ['injection'],
    );
    expect(meds.single['dose_unit'], 'IU');
    expect(meds.single['units_per_package'], 300.0);

    final schedules = await helper.query(
      'schedules',
      where: 'medicine_id = ?',
      whereArgs: ['med-insulin'],
    );
    expect(schedules.single['is_variable_dose'], 1);
    expect(schedules.single['time_of_day'], '08:00');
  });

  test('deleting a medicine cascades to its schedules', () async {
    await helper.insert('medicines', {
      'id': 'm1',
      'name': 'X',
      'form': 'tablet',
      'package_type': 'strip',
      'dose_unit': 'pcs',
      'units_per_package': 10.0,
      'created_at': 1,
    });
    await helper.insert('schedules', {
      'id': 's1',
      'medicine_id': 'm1',
      'time_of_day': '09:00',
      'dose_amount': 1.0,
      'days_of_week': '1,2,3,4,5,6,7',
    });

    await helper.delete('medicines', where: 'id = ?', whereArgs: ['m1']);
    final schedules = await helper.query('schedules');
    expect(schedules, isEmpty);
  });
}
