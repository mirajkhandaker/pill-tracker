import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/core/utils/prescription_parser.dart';

ScannedMedicine one(String row) {
  final found = parsePrescriptionText([row]);
  expect(found, hasLength(1), reason: 'expected one medicine in "$row"');
  return found.single;
}

List<int> hours(ScannedMedicine m) => [for (final s in m.dailySlots()) s.hour];
List<double?> amounts(ScannedMedicine m) => [
  for (final s in m.dailySlots()) s.amount,
];

void main() {
  group('medicine rows', () {
    test('tablet with strength, dose pattern and course', () {
      final m = one('1. Tab. Napa 500mg 1+0+1 x 7 days');
      expect(m.name, 'Napa');
      expect(m.form, 'tablet');
      expect(m.strength, '500mg');
      expect(m.doseParts, [1, 0, 1]);
      expect(m.courseDays, 7);
      expect(hours(m), [8, 20]);
      expect(amounts(m), [1, 1]);
    });

    test('capsule, all-caps name, meal instruction, continue', () {
      final m = one('Cap SECLO 20 mg  0+0+1  before meal  continue');
      expect(m.name, 'Seclo');
      expect(m.form, 'capsule');
      expect(m.strength, '20mg');
      expect(hours(m), [20]);
      expect(m.instructions, 'Before meals');
      expect(m.ongoing, isTrue);
      expect(m.courseDays, isNull);
    });

    test('multi-word name and half tablets', () {
      final m = one('Tab. Napa Extend 665mg ½+0+½ 1 month');
      expect(m.name, 'Napa Extend');
      expect(m.doseParts, [0.5, 0, 0.5]);
      expect(m.courseDays, 30);
    });

    test('strength written without a unit', () {
      final m = one('Tab Losectil 20 1-0-1');
      expect(m.name, 'Losectil');
      expect(m.strength, '20');
      expect(hours(m), [8, 20]);
    });

    test('"O" misread for zero in the pattern', () {
      expect(one('Tab Ace 500mg 1+O+1').doseParts, [1, 0, 1]);
    });

    test('abbreviations: BD, TDS, QID, OD and bedtime', () {
      expect(one('Tab. Metformin 500mg BD').timesPerDay, 2);
      expect(hours(one('Cap. Amoxicillin 500mg TDS 5 days')), [8, 14, 20]);
      expect(one('Tab Something 10mg QID').timesPerDay, 4);
      final night = one('Tab. Rosuva 10mg HS');
      expect(night.instructions, 'At bedtime');
      expect(hours(night), [21]);
      expect(hours(one('Tab. Amlodipine 5mg once daily')), [8]);
    });

    test('every N hours', () {
      final m = one('Tab. Paracetamol 500 mg q8h');
      expect(m.everyHours, 8);
      expect(hours(m), [8, 16, 0]);
      expect(one('Tab Ibuprofen 400mg 6 hourly').everyHours, 6);
    });

    test('as needed has no daily times', () {
      final m = one('Tab. Napa 500mg 1 tab SOS');
      expect(m.asNeeded, isTrue);
      expect(m.amount, 1);
      expect(m.dailySlots(), isEmpty);
    });

    test('syrup: strength per ml, amount in teaspoons', () {
      final m = one('Syp. Napa 120mg/5ml 2 tsp tds');
      expect(m.form, 'liquid');
      expect(m.strength, '120mg/5ml');
      expect(m.amount, 2);
      expect(m.amountUnit, 'tsp');
      expect(amounts(m), [2, 2, 2]);
    });

    test('syrup bottle size is not the dose', () {
      final m = one('4. Syp. Tusca 100ml  2 tsp TDS  5 days');
      expect(m.name, 'Tusca');
      expect(m.amount, 2);
      expect(m.amountUnit, 'tsp');
      expect(amounts(m), [2, 2, 2]);
      expect(m.courseDays, 5);
    });

    test('syrup pattern without a unit leaves the amount for the user', () {
      final m = one('Syrup Tusca 1+1+1 5 days');
      expect(m.form, 'liquid');
      expect(hours(m), [8, 14, 20]);
      expect(amounts(m), [null, null, null]);
      expect(m.effectiveUnit, isNull);
    });

    test('eye drops and inhaler', () {
      final drops = one('E/D Moxiflox 2 drops 4 times a day');
      expect(drops.form, 'drops');
      expect(drops.amountUnit, 'drop');
      expect(drops.timesPerDay, 4);
      expect(one('Eye drop Tears Naturale 1+1+1').form, 'drops');
      final inhaler = one('Inh. Salbutamol 2 puffs SOS');
      expect(inhaler.form, 'inhaler');
      expect(inhaler.amount, 2);
      expect(inhaler.amountUnit, 'puff');
    });

    test('row without a form needs a strength', () {
      final m = one('Montelukast 10mg 0+0+1');
      expect(m.form, isNull);
      expect(m.name, 'Montelukast');
      expect(parsePrescriptionText(['Montelukast once daily']), isEmpty);
    });
  });

  group('rows that are not medicines', () {
    test('patient, doctor and vitals rows are ignored', () {
      final found = parsePrescriptionText([
        'Dr. Rahman MBBS, FCPS',
        'Patient: Karim  Age: 45  Date: 12-10-2026',
        'BP 130/80 mmHg  Wt 70 kg',
        'Hb 12 g/dl',
        'Advice: drink plenty of water',
        'Follow up after 7 days',
      ]);
      expect(found, isEmpty);
    });

    test('dates are not dose patterns', () {
      final m = one('Tab. Napa 500mg 12-10-26');
      expect(m.doseParts, isNull);
    });
  });

  group('dosing written on the next line', () {
    test('fills in the medicine above', () {
      final found = parsePrescriptionText([
        'Tab. Napa 500mg',
        '1+1+1 x 5 days after meal',
        'Cap. Seclo 20mg',
        '1+0+1',
        'Follow up after 7 days',
      ]);
      expect(found, hasLength(2));
      expect(found[0].doseParts, [1, 1, 1]);
      expect(found[0].courseDays, 5);
      expect(found[0].instructions, 'After meals');
      expect(found[1].doseParts, [1, 0, 1]);
      // "Follow up after 7 days" is about the visit, not Seclo.
      expect(found[1].courseDays, isNull);
    });
  });

  group('groupIntoRows', () {
    test('joins side-by-side lines, top to bottom', () {
      final rows = groupIntoRows(const [
        OcrLine('1+0+1', left: 300, top: 102, right: 360, bottom: 122),
        OcrLine('Tab. Napa 500mg', left: 20, top: 100, right: 200, bottom: 120),
        OcrLine('Cap. Seclo 20mg', left: 20, top: 160, right: 200, bottom: 180),
        OcrLine('7 days', left: 400, top: 99, right: 460, bottom: 119),
      ]);
      expect(rows, ['Tab. Napa 500mg  1+0+1  7 days', 'Cap. Seclo 20mg']);
      expect(parsePrescriptionText(rows).first.courseDays, 7);
    });
  });
}
