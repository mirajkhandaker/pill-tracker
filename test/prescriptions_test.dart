import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilltrack/data/database/database_helper.dart';
import 'package:pilltrack/data/models/dose_log.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/prescription.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/data/repositories/dose_log_repository.dart';
import 'package:pilltrack/data/repositories/medicine_repository.dart';
import 'package:pilltrack/data/repositories/prescription_repository.dart';
import 'package:pilltrack/data/repositories/schedule_repository.dart';
import 'package:pilltrack/services/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The exact v1 schema shipped before prescriptions existed.
const _v1Schema = [
  '''CREATE TABLE medicines (id TEXT PRIMARY KEY, name TEXT NOT NULL,
     dosage_text TEXT, notes TEXT, form TEXT NOT NULL, package_type TEXT NOT NULL,
     dose_unit TEXT NOT NULL, units_per_package REAL NOT NULL,
     packages_in_hand INTEGER NOT NULL DEFAULT 0, loose_units REAL NOT NULL DEFAULT 0,
     track_inventory INTEGER NOT NULL DEFAULT 1, is_prn INTEGER NOT NULL DEFAULT 0,
     refill_threshold_days INTEGER NOT NULL DEFAULT 3,
     is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL)''',
  '''CREATE TABLE schedules (id TEXT PRIMARY KEY, medicine_id TEXT NOT NULL,
     time_of_day TEXT NOT NULL, dose_amount REAL NOT NULL DEFAULT 1,
     is_variable_dose INTEGER NOT NULL DEFAULT 0, days_of_week TEXT NOT NULL,
     FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE)''',
  '''CREATE TABLE dose_logs (id TEXT PRIMARY KEY, medicine_id TEXT NOT NULL,
     schedule_id TEXT, scheduled_time INTEGER NOT NULL, action_time INTEGER,
     dose_amount REAL NOT NULL, status TEXT NOT NULL,
     FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE)''',
  'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
];

Medicine _med(
  String id, {
  String? rx,
  int? endDate,
  double loose = 0,
  bool tracked = true,
}) => Medicine(
  id: id,
  name: 'Med $id',
  form: 'tablet',
  packageType: 'strip',
  doseUnit: 'pcs',
  unitsPerPackage: 10,
  looseUnits: loose,
  trackInventory: tracked,
  createdAt: 0,
  prescriptionId: rx,
  endDate: endDate,
);

Prescription _rx(String id, {String doctor = 'Dr. Rahman'}) => Prescription(
  id: id,
  doctorName: doctor,
  reason: 'Blood pressure',
  issuedAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
  createdAt: 0,
);

Future<Map<String, List<String>>> _columns(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return {
    for (final t in tables)
      t['name'] as String: [
        for (final c in await db.rawQuery("PRAGMA table_info(${t['name']})"))
          '${c['name']}:${c['type']}:${c['notnull']}:${c['dflt_value']}',
      ],
  };
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('migration v1 -> v2', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('pilltrack_mig'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps existing data and adds prescription support', () async {
      final path = p.join(dir.path, 'v1.db');
      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            for (final sql in _v1Schema) {
              await db.execute(sql);
            }
          },
        ),
      );
      await v1.insert('medicines', {
        'id': 'old',
        'name': 'Paracetamol',
        'form': 'tablet',
        'package_type': 'strip',
        'dose_unit': 'pcs',
        'units_per_package': 10.0,
        'loose_units': 4.0,
        'created_at': 1,
      });
      await v1.insert('schedules', {
        'id': 's',
        'medicine_id': 'old',
        'time_of_day': '08:00',
        'days_of_week': '1,2,3,4,5,6,7',
      });
      await v1.close();

      final helper = DatabaseHelper.forTesting(path);
      final med = (await MedicineRepository(helper).getById('old'))!;
      expect(med.name, 'Paracetamol');
      expect(med.looseUnits, 4);
      expect(med.prescriptionId, isNull);
      expect(med.endDate, isNull);
      expect(
        await ScheduleRepository(helper).getByMedicineId('old'),
        hasLength(1),
      );
      expect(await PrescriptionRepository(helper).getAll(), isEmpty);
      final upgraded = await _columns(await helper.getDb());
      await helper.close();

      // An upgraded database must match a fresh install exactly.
      final fresh = DatabaseHelper.forTesting(p.join(dir.path, 'fresh.db'));
      expect(upgraded, await _columns(await fresh.getDb()));
      await fresh.close();
    });
  });

  group('prescriptions', () {
    late DatabaseHelper db;
    late PrescriptionRepository rxRepo;
    late MedicineRepository medRepo;

    setUp(() {
      db = DatabaseHelper.forTesting(inMemoryDatabasePath);
      rxRepo = PrescriptionRepository(db);
      medRepo = MedicineRepository(db);
    });
    tearDown(() => db.close());

    test('ending a prescription stops its medicines but keeps them', () async {
      await rxRepo.insert(_rx('r1'));
      await medRepo.insert(_med('a', rx: 'r1'));
      await medRepo.insert(_med('otc')); // not on the prescription

      await rxRepo.end('r1');

      expect((await rxRepo.getById('r1'))!.isActive, isFalse);
      expect((await medRepo.getActive()).map((m) => m.id), ['otc']);
      expect(await rxRepo.medicinesFor('r1'), hasLength(1));
    });

    test(
      'a new prescription carries over chosen medicines and ends the old',
      () async {
        await rxRepo.insert(_rx('old'));
        await medRepo.insert(_med('keep', rx: 'old', loose: 7));
        await medRepo.insert(_med('stop', rx: 'old'));
        await ScheduleRepository(db).insert(
          const Schedule(
            id: 's1',
            medicineId: 'keep',
            timeOfDay: '09:00',
            doseAmount: 2,
          ),
        );
        await DoseLogRepository(db).insert(
          const DoseLog(
            id: 'l1',
            medicineId: 'keep',
            scheduleId: 's1',
            scheduledTime: 1,
            doseAmount: 2,
            status: DoseLog.statusTaken,
          ),
        );

        await rxRepo.createReplacing(
          _rx('new', doctor: 'Dr. Akter'),
          replaces: 'old',
          continueMedicineIds: {'keep'},
        );

        expect((await rxRepo.getById('old'))!.isActive, isFalse);
        final active = await medRepo.getActive();
        expect(active, hasLength(1));
        final copy = active.single;
        expect(copy.id, isNot('keep'), reason: 'copied, not moved');
        expect(copy.prescriptionId, 'new');
        expect(copy.name, 'Med keep');
        expect(copy.looseUnits, 7, reason: 'remaining stock carries over');

        final schedules = await ScheduleRepository(db).getByMedicineId(copy.id);
        expect(schedules.single.timeOfDay, '09:00');
        expect(schedules.single.doseAmount, 2);

        // History stays with the old prescription's medicine.
        expect(
          await DoseLogRepository(db).getByMedicine('keep', 0),
          hasLength(1),
        );
        expect(await DoseLogRepository(db).getByMedicine(copy.id, 0), isEmpty);
        expect(await rxRepo.medicinesFor('old'), hasLength(2));
      },
    );
  });

  group('replacing mid-day', () {
    late DatabaseHelper db;
    setUp(() => db = DatabaseHelper.forTesting(inMemoryDatabasePath));
    tearDown(() => db.close());

    test("today's logged doses move to the carried-over copy", () async {
      final rxRepo = PrescriptionRepository(db);
      final logs = DoseLogRepository(db);
      await rxRepo.insert(_rx('old'));
      await MedicineRepository(db).insert(_med('keep', rx: 'old'));
      await ScheduleRepository(db).insert(
        const Schedule(id: 's1', medicineId: 'keep', timeOfDay: '00:00'),
      );
      final now = DateTime.now();
      final todayMs = DateTime(
        now.year,
        now.month,
        now.day,
      ).millisecondsSinceEpoch;
      for (final (id, at) in [('today', todayMs), ('yesterday', todayMs - 1)]) {
        await logs.insert(
          DoseLog(
            id: id,
            medicineId: 'keep',
            scheduleId: 's1',
            scheduledTime: at,
            doseAmount: 1,
            status: DoseLog.statusTaken,
          ),
        );
      }

      await rxRepo.createReplacing(
        _rx('new'),
        replaces: 'old',
        continueMedicineIds: {'keep'},
      );

      final copy = (await MedicineRepository(db).getActive()).single;
      final newSchedule = (await ScheduleRepository(
        db,
      ).getByMedicineId(copy.id)).single;
      final moved = (await logs.getByMedicine(copy.id, 0)).single;
      expect(moved.id, 'today');
      expect(moved.scheduleId, newSchedule.id);
      // Earlier history stays with the old prescription's medicine.
      expect((await logs.getByMedicine('keep', 0)).single.id, 'yesterday');
    });
  });

  group('fixed courses', () {
    late DatabaseHelper db;
    setUp(() => db = DatabaseHelper.forTesting(inMemoryDatabasePath));
    tearDown(() => db.close());

    final now = DateTime(2026, 10, 28, 12);
    final yesterday = DateTime(2026, 10, 27).millisecondsSinceEpoch;
    final today = DateTime(2026, 10, 28).millisecondsSinceEpoch;

    test('a finished course is no longer active or scheduled', () async {
      await MedicineRepository(db).insert(_med('done', endDate: yesterday));
      await MedicineRepository(db).insert(_med('last-day', endDate: today));
      for (final id in ['done', 'last-day']) {
        await ScheduleRepository(db)
            .insert(Schedule(id: 's-$id', medicineId: id, timeOfDay: '20:00'));
      }

      final active = await MedicineRepository(db).getActive(now: now);
      expect(active.map((m) => m.id), ['last-day']);
      final pairs = await ScheduleRepository(db)
          .getAllActiveWithMedicine(now: now);
      expect(pairs.map((p) => p.medicine.id), ['last-day']);
    });

    test('reminders stop after the last day of the course', () {
      final threeDays = _med(
        'c',
        endDate: DateTime(2026, 10, 30).millisecondsSinceEpoch,
      );
      final occ = reminderOccurrences(
        [const Schedule(id: 's', medicineId: 'c', timeOfDay: '09:00')],
        [threeDays],
        now,
      );
      // Today's 09:00 has passed; the 29th and 30th remain.
      expect(occ.map((o) => o.time), [
        DateTime(2026, 10, 29, 9),
        DateTime(2026, 10, 30, 9),
      ]);
    });

    test('ongoing medicines get the full horizon', () {
      final occ = reminderOccurrences(
        [const Schedule(id: 's', medicineId: 'o', timeOfDay: '13:00')],
        [_med('o')],
        now,
      );
      expect(occ, hasLength(NotificationService.horizonDays + 1));
      expect(occ.first.time, DateTime(2026, 10, 28, 13));
    });
  });
}
