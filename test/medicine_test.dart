import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/schedule.dart';

Medicine baseMedicine({
  String form = 'tablet',
  String packageType = 'strip',
  String doseUnit = 'pcs',
  double unitsPerPackage = 10,
  int packagesInHand = 2,
  double looseUnits = 0,
  bool trackInventory = true,
  bool isPrn = false,
  int refillThresholdDays = 3,
}) => Medicine(
  id: 'm1',
  name: 'Test',
  form: form,
  packageType: packageType,
  doseUnit: doseUnit,
  unitsPerPackage: unitsPerPackage,
  packagesInHand: packagesInHand,
  looseUnits: looseUnits,
  trackInventory: trackInventory,
  isPrn: isPrn,
  refillThresholdDays: refillThresholdDays,
  createdAt: 0,
);

Schedule sched({
  double dose = 1,
  String days = '1,2,3,4,5,6,7',
  bool variable = false,
}) => Schedule(
  id: 's',
  medicineId: 'm1',
  timeOfDay: '08:00',
  doseAmount: dose,
  daysOfWeek: days,
  isVariableDose: variable,
);

void main() {
  group('inventory totals', () {
    test('totalUnitsRemaining sums packages and loose', () {
      final m = baseMedicine(
        unitsPerPackage: 10,
        packagesInHand: 2,
        looseUnits: 3,
      );
      expect(m.totalUnitsRemaining, 23);
    });

    test('remainingLabel', () {
      final m = baseMedicine(
        unitsPerPackage: 10,
        packagesInHand: 2,
        looseUnits: 0,
      );
      expect(m.remainingLabel, '20 Tablets left');
    });

    test('inventoryBreakdown with loose pieces', () {
      final m = baseMedicine(packagesInHand: 2, looseUnits: 3);
      expect(m.inventoryBreakdown, '2 Strips + 3 loose Tablets');
    });

    test('inventoryBreakdown ml measure', () {
      final m = baseMedicine(
        form: 'liquid',
        packageType: 'bottle',
        doseUnit: 'ml',
        unitsPerPackage: 100,
        packagesInHand: 1,
        looseUnits: 45,
      );
      expect(m.inventoryBreakdown, '1 Bottle + 45 ml');
    });

    test('inventoryBreakdown without packs drops "loose"', () {
      final m = baseMedicine(packagesInHand: 0, looseUnits: 12);
      expect(m.inventoryBreakdown, '12 Tablets');
    });

    test('hasPackSize is false when no pack size was given', () {
      expect(baseMedicine(unitsPerPackage: 0).hasPackSize, isFalse);
      expect(baseMedicine(unitsPerPackage: 10).hasPackSize, isTrue);
    });

    test('inventoryBreakdown empty', () {
      final m = baseMedicine(packagesInHand: 0, looseUnits: 0);
      expect(m.inventoryBreakdown, 'Empty');
    });
  });

  group('daysUntilEmpty', () {
    test('daily tablet consumption', () {
      final m = baseMedicine(unitsPerPackage: 10, packagesInHand: 2); // 20 pcs
      expect(m.daysUntilEmpty([sched(dose: 1)]), 20);
    });

    test('alternate-day insulin', () {
      final m = baseMedicine(
        form: 'injection',
        doseUnit: 'IU',
        unitsPerPackage: 300,
        packagesInHand: 1,
        looseUnits: 0,
      ); // 300 IU
      // 10 IU on 4 of 7 days => 40/7 per day => floor(300 / (40/7)) = 52
      expect(m.daysUntilEmpty([sched(dose: 10, days: '1,3,5,7')]), 52);
    });

    test('PRN returns 999', () {
      final m = baseMedicine(isPrn: true);
      expect(m.daysUntilEmpty([sched(dose: 1)]), 999);
    });

    test('cream (untracked) returns 999', () {
      final m = baseMedicine(form: 'cream', trackInventory: false);
      expect(m.daysUntilEmpty([sched(dose: 1)]), 999);
    });

    test('zero schedules returns 999', () {
      final m = baseMedicine();
      expect(m.daysUntilEmpty(const []), 999);
    });
  });

  group('needsRefill', () {
    test('true when at/under threshold', () {
      final m = baseMedicine(
        unitsPerPackage: 1,
        packagesInHand: 3,
        refillThresholdDays: 3,
      ); // 3 pcs
      expect(m.needsRefill([sched(dose: 1)]), isTrue); // 3 days <= 3
    });

    test('false when well stocked', () {
      final m = baseMedicine(
        unitsPerPackage: 10,
        packagesInHand: 3,
        refillThresholdDays: 3,
      ); // 30
      expect(m.needsRefill([sched(dose: 1)]), isFalse);
    });

    test('untracked never needs refill', () {
      final m = baseMedicine(trackInventory: false);
      expect(m.needsRefill([sched(dose: 1)]), isFalse);
    });
  });

  group('doseAmountInBaseUnit', () {
    test('teaspoon to ml', () {
      final m = baseMedicine(form: 'liquid', doseUnit: 'ml');
      expect(m.doseAmountInBaseUnit(2, 'tsp'), 10);
    });
    test('tablespoon to ml', () {
      final m = baseMedicine(form: 'liquid', doseUnit: 'ml');
      expect(m.doseAmountInBaseUnit(1, 'tbsp'), 15);
    });
    test('ml identity', () {
      final m = baseMedicine(form: 'liquid', doseUnit: 'ml');
      expect(m.doseAmountInBaseUnit(5, 'ml'), 5);
    });
  });

  group('serialization', () {
    test('round-trips through map', () {
      final m = baseMedicine(looseUnits: 3);
      expect(Medicine.fromMap(m.toMap()), m);
    });

    test('copyWith changes one field', () {
      final m = baseMedicine();
      expect(m.copyWith(name: 'New').name, 'New');
      expect(m.copyWith(name: 'New') == m, isFalse);
    });

    test('schedule round-trips and parses days', () {
      final s = sched(days: '1,3,5');
      final back = Schedule.fromMap(s.toMap());
      expect(back, s);
      expect(back.days, [1, 3, 5]);
      expect(back.dayCount, 3);
      expect(back.hour, 8);
      expect(back.minute, 0);
    });
  });
}
