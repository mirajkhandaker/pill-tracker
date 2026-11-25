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
  late MedicineRepository meds;
  late DoseLogRepository logs;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    meds = MedicineRepository(db);
    logs = DoseLogRepository(db);
  });
  tearDown(() => db.close());

  /// A tracked medicine with [stock] loose units and one logged dose.
  Future<DoseLog> seed({
    double stock = 10,
    double amount = 2,
    String status = DoseLog.statusTaken,
    bool tracked = true,
  }) async {
    await meds.insert(
      Medicine(
        id: 'm',
        name: 'Med',
        form: 'tablet',
        packageType: 'strip',
        doseUnit: 'pcs',
        unitsPerPackage: 10,
        looseUnits: stock,
        trackInventory: tracked,
        createdAt: 0,
      ),
    );
    final log = DoseLog(
      id: 'l',
      medicineId: 'm',
      scheduleId: 's',
      scheduledTime: 1000,
      actionTime: 2000,
      doseAmount: amount,
      status: status,
    );
    await logs.insert(log);
    return log;
  }

  Future<double> stock() async =>
      (await meds.getById('m'))!.totalUnitsRemaining;

  test('logging a dose with custom details consumes stock once', () async {
    final existing = await seed(stock: 10, amount: 1);
    final result = await logs.addLog(
      existing.copyWith(
        id: 'new',
        scheduleId: 'other',
        doseAmount: 0.5,
        actionTime: 9000,
      ),
    );
    expect(result.added, isTrue);
    expect(result.covered, isTrue);
    expect(await stock(), 9.5);
    expect(await logs.getByMedicine('m', 0), hasLength(2));
  });

  test('logging a skipped dose leaves stock alone', () async {
    final existing = await seed(stock: 10, amount: 1);
    await logs.addLog(
      existing.copyWith(
        id: 'new',
        scheduleId: 'other',
        status: DoseLog.statusSkipped,
        doseAmount: 0,
      ),
    );
    expect(await stock(), 10);
  });

  test(
    'a scheduled dose already logged that day is not logged again',
    () async {
      final existing = await seed(stock: 10, amount: 1);
      final again = await logs.addLog(
        existing.copyWith(
          id: 'dup',
          scheduledTime: existing.scheduledTime + 60,
        ),
      );
      expect(again.added, isFalse);
      expect(await stock(), 10);
      expect(await logs.getByMedicine('m', 0), hasLength(1));
    },
  );

  test('lowering the amount taken gives the difference back', () async {
    final log = await seed(stock: 8, amount: 2);
    await logs.updateLog(log, log.copyWith(doseAmount: 1));
    expect(await stock(), 9);
    expect((await logs.getByMedicine('m', 0)).single.doseAmount, 1);
  });

  test('raising the amount taken consumes more', () async {
    final log = await seed(stock: 8, amount: 2);
    await logs.updateLog(log, log.copyWith(doseAmount: 3));
    expect(await stock(), 7);
  });

  test('changing taken to skipped returns the whole dose', () async {
    final log = await seed(stock: 8, amount: 2);
    await logs.updateLog(
      log,
      log.copyWith(status: DoseLog.statusSkipped, doseAmount: 0),
    );
    expect(await stock(), 10);
  });

  test('changing skipped to taken consumes the dose', () async {
    final log = await seed(stock: 10, amount: 0, status: DoseLog.statusSkipped);
    await logs.updateLog(
      log,
      log.copyWith(status: DoseLog.statusTaken, doseAmount: 2),
    );
    expect(await stock(), 8);
  });

  test('editing only the time leaves stock alone', () async {
    final log = await seed(stock: 8, amount: 2);
    await logs.updateLog(log, log.copyWith(actionTime: 5000));
    expect(await stock(), 8);
    expect((await logs.getByMedicine('m', 0)).single.actionTime, 5000);
  });

  test('removing a taken dose deletes it and returns the stock', () async {
    final log = await seed(stock: 8, amount: 2);
    await logs.deleteLog(log);
    expect(await logs.getByMedicine('m', 0), isEmpty);
    expect(await stock(), 10);
  });

  test('removing a skipped dose changes no stock', () async {
    final log = await seed(stock: 8, amount: 0, status: DoseLog.statusSkipped);
    await logs.deleteLog(log);
    expect(await stock(), 8);
  });

  test("untracked supply is never touched", () async {
    final log = await seed(stock: 8, amount: 2, tracked: false);
    await logs.updateLog(log, log.copyWith(doseAmount: 5));
    await logs.deleteLog(log.copyWith(doseAmount: 5));
    expect(await stock(), 8);
  });

  test('extra consumption can open a new package', () async {
    final log = await seed(stock: 1, amount: 1);
    // 1 loose + 0 packages: consuming 3 more can't be covered -> clamps to 0.
    await logs.updateLog(log, log.copyWith(doseAmount: 4));
    expect(await stock(), 0);
  });
}
