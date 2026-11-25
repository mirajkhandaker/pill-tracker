import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/database/database_helper.dart';
import 'package:pilltrack/data/models/dose_log.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/repositories/dose_log_repository.dart';
import 'package:pilltrack/data/repositories/medicine_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late MedicineRepository repo;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    repo = MedicineRepository(db);
  });

  tearDown(() => db.close());

  Future<Medicine> seed({
    double unitsPerPackage = 10,
    int packagesInHand = 1,
    double looseUnits = 0,
    bool trackInventory = true,
  }) async {
    final m = Medicine(
      id: 'm1',
      name: 'Med',
      form: 'tablet',
      packageType: 'strip',
      doseUnit: 'pcs',
      unitsPerPackage: unitsPerPackage,
      packagesInHand: packagesInHand,
      looseUnits: looseUnits,
      trackInventory: trackInventory,
      createdAt: 0,
    );
    await repo.insert(m);
    return m;
  }

  group('decrementUnits', () {
    test('1. enough loose units', () async {
      await seed(packagesInHand: 1, looseUnits: 5);
      final ok = await repo.decrementUnits('m1', 3);
      final m = (await repo.getById('m1'))!;
      expect(ok, isTrue);
      expect(m.looseUnits, 2);
      expect(m.packagesInHand, 1);
    });

    test('2. loose units go to exactly zero', () async {
      await seed(packagesInHand: 1, looseUnits: 5);
      final ok = await repo.decrementUnits('m1', 5);
      final m = (await repo.getById('m1'))!;
      expect(ok, isTrue);
      expect(m.looseUnits, 0);
      expect(m.packagesInHand, 1);
    });

    test('3. loose goes negative -> open a new package', () async {
      await seed(unitsPerPackage: 10, packagesInHand: 2, looseUnits: 2);
      final ok = await repo.decrementUnits('m1', 5);
      final m = (await repo.getById('m1'))!;
      expect(ok, isTrue);
      expect(m.packagesInHand, 1);
      expect(m.looseUnits, 7);
      expect(m.totalUnitsRemaining, 17);
    });

    test('4. multiple packages consumed in one call', () async {
      await seed(unitsPerPackage: 100, packagesInHand: 3, looseUnits: 0);
      final ok = await repo.decrementUnits('m1', 200);
      final m = (await repo.getById('m1'))!;
      expect(ok, isTrue);
      expect(m.packagesInHand, 1);
      expect(m.looseUnits, 0);
      expect(m.totalUnitsRemaining, 100);
    });

    test('5. insufficient inventory returns false and clamps', () async {
      await seed(unitsPerPackage: 10, packagesInHand: 1, looseUnits: 0);
      final ok = await repo.decrementUnits('m1', 15);
      final m = (await repo.getById('m1'))!;
      expect(ok, isFalse);
      expect(m.totalUnitsRemaining, 0);
    });

    test('6. untracked returns true with no change', () async {
      await seed(packagesInHand: 1, looseUnits: 5, trackInventory: false);
      final ok = await repo.decrementUnits('m1', 3);
      final m = (await repo.getById('m1'))!;
      expect(ok, isTrue);
      expect(m.looseUnits, 5);
      expect(m.packagesInHand, 1);
    });
  });

  group('other medicine ops', () {
    test('addUnits refills by a number of units', () async {
      await seed(packagesInHand: 0, looseUnits: 2);
      await repo.addUnits('m1', 30);
      expect((await repo.getById('m1'))!.totalUnitsRemaining, 32);
    });

    test('addPackages increments', () async {
      await seed(packagesInHand: 1);
      await repo.addPackages('m1', 2);
      expect((await repo.getById('m1'))!.packagesInHand, 3);
    });

    test('softDelete hides from getActive but keeps the row', () async {
      await seed();
      await repo.softDelete('m1');
      expect(await repo.getActive(), isEmpty);
      expect(await repo.getAll(), hasLength(1));
      expect((await repo.getById('m1'))!.isActive, isFalse);
    });
  });

  group('logPrnDose', () {
    test('records a taken log and decrements', () async {
      await seed(unitsPerPackage: 10, packagesInHand: 1, looseUnits: 5);
      final logRepo = DoseLogRepository(db);
      final result = await logRepo.logPrnDose('m1', 2);
      expect(result.covered, isTrue);
      expect(result.log.status, DoseLog.statusTaken);
      expect(result.log.scheduleId, isNull);
      expect(result.log.scheduledTime, result.log.actionTime);
      expect((await repo.getById('m1'))!.looseUnits, 3);
      expect(await logRepo.getByMedicine('m1', 0), hasLength(1));
    });
  });
}
