import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/core/providers.dart';
import 'package:pilltrack/data/database/database_helper.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/features/medicines/providers/medicine_providers.dart';
import 'package:pilltrack/services/backup_service.dart';
import 'package:pilltrack/services/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Medicine _med(String id, {bool prn = false, double loose = 0}) => Medicine(
  id: id,
  name: 'Med $id',
  form: 'tablet',
  packageType: 'strip',
  doseUnit: 'pcs',
  unitsPerPackage: 10,
  packagesInHand: 1,
  looseUnits: loose,
  isPrn: prn,
  createdAt: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late ProviderContainer container;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    container = ProviderContainer(
      overrides: [databaseHelperProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('BackupService', () {
    test('export then import round-trips all data', () async {
      await db.insert('medicines', _med('a').toMap());
      await db.insert(
        'schedules',
        const Schedule(id: 's', medicineId: 'a', timeOfDay: '08:00').toMap(),
      );
      final json = await BackupService.exportJson(db);

      await BackupService.deleteAll(db);
      expect(await db.query('medicines'), isEmpty);

      await BackupService.importJson(db, json);
      expect((await db.query('medicines')).single['id'], 'a');
      expect((await db.query('schedules')).single['id'], 's');
    });

    test('invalid backup is rejected and existing data kept', () async {
      await db.insert('medicines', _med('keep').toMap());
      await expectLater(
        BackupService.importJson(db, '{"app":"other"}'),
        throwsFormatException,
      );
      await expectLater(
        BackupService.importJson(db, 'not json'),
        throwsFormatException,
      );
      await expectLater(
        BackupService.importJson(
          db,
          '{"app":"pilltrack","medicines":[{"id":1}],"schedules":[],"dose_logs":[],"settings":[]}',
        ),
        throwsFormatException,
      );
      expect((await db.query('medicines')).single['id'], 'keep');
    });
  });

  group('today doses + actions', () {
    test('lists scheduled doses for today, excluding PRN', () async {
      await db.insert('medicines', _med('a').toMap());
      await db.insert('medicines', _med('p', prn: true).toMap());
      await db.insert(
        'schedules',
        const Schedule(id: 's', medicineId: 'a', timeOfDay: '23:59').toMap(),
      );

      final doses = await container.read(todayDosesProvider.future);
      expect(doses, hasLength(1));
      expect(doses.single.medicine.id, 'a');
      expect(doses.single.isPending, isTrue);
    });

    test('markTaken logs the dose and decrements inventory', () async {
      await db.insert('medicines', _med('a', loose: 3).toMap()); // 13 pcs
      await db.insert(
        'schedules',
        const Schedule(
          id: 's',
          medicineId: 'a',
          timeOfDay: '23:59',
          doseAmount: 2,
        ).toMap(),
      );

      final dose = (await container.read(todayDosesProvider.future)).single;
      final result = await container
          .read(medicineActionsProvider)
          .markTaken(dose);
      expect(result.covered, isTrue);

      final after = (await container.read(todayDosesProvider.future)).single;
      expect(after.isTaken, isTrue);
      final m = await container.read(medicineRepositoryProvider).getById('a');
      expect(m!.totalUnitsRemaining, 11);
    });

    test('a dose is logged once even if Mark Taken runs twice', () async {
      await db.insert('medicines', _med('a', loose: 3).toMap()); // 13 pcs
      await db.insert(
        'schedules',
        const Schedule(id: 's', medicineId: 'a', timeOfDay: '23:59').toMap(),
      );
      final dose = (await container.read(todayDosesProvider.future)).single;
      final actions = container.read(medicineActionsProvider);

      // Both taps start before either finishes, like a quick double tap.
      final results = await Future.wait([
        actions.markTaken(dose),
        actions.markTaken(dose),
      ]);
      expect(results.where((r) => r.alreadyLogged), hasLength(1));
      final logs = await container
          .read(doseLogRepositoryProvider)
          .getByMedicine('a', 0);
      expect(logs, hasLength(1));
      final m = await container.read(medicineRepositoryProvider).getById('a');
      expect(m!.totalUnitsRemaining, 12);
    });

    test('editing a medicine keeps today\'s taken dose taken', () async {
      final med = _med('a', loose: 3);
      await db.insert('medicines', med.toMap());
      const schedule = Schedule(id: 's', medicineId: 'a', timeOfDay: '23:59');
      await db.insert('schedules', schedule.toMap());
      final actions = container.read(medicineActionsProvider);
      await actions.markTaken(
        (await container.read(todayDosesProvider.future)).single,
      );

      // The edit screen re-saves existing times with their ids.
      await actions.saveMedicine(med.copyWith(notes: 'edited'), [schedule]);

      final dose = (await container.read(todayDosesProvider.future)).single;
      expect(dose.isTaken, isTrue);
      // Re-saving must not cascade-delete the medicine's history.
      final logs = await container
          .read(doseLogRepositoryProvider)
          .getByMedicine('a', 0);
      expect(logs, hasLength(1));
    });

    test(
      'saveMedicine survives notification plugin being unavailable',
      () async {
        // No platform plugin in unit tests: the reminder sync must fail softly.
        await container.read(medicineActionsProvider).saveMedicine(
          _med('a'),
          const [Schedule(id: 's', medicineId: 'a', timeOfDay: '09:00')],
        );
        expect(
          await container.read(activeMedicinesProvider.future),
          hasLength(1),
        );
      },
    );
  });

  test('notification ids are stable and 31-bit', () {
    final a = NotificationService.idFor('m|s|2026-1-1');
    expect(NotificationService.idFor('m|s|2026-1-1'), a);
    expect(NotificationService.idFor('m|s|2026-1-2'), isNot(a));
    expect(a, inInclusiveRange(0, 0x7FFFFFFF));
  });
}
