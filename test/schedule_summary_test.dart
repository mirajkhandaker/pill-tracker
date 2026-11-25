import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/features/prescriptions/screens/prescription_detail_screen.dart';

Medicine _med({bool prn = false, String form = 'tablet'}) => Medicine(
  id: 'm',
  name: 'Med',
  form: form,
  packageType: 'strip',
  doseUnit: 'pcs',
  unitsPerPackage: 10,
  isPrn: prn,
  createdAt: 0,
);

Schedule _at(
  String time, {
  double amount = 1,
  bool variable = false,
  String days = '1,2,3,4,5,6,7',
}) => Schedule(
  id: time,
  medicineId: 'm',
  timeOfDay: time,
  doseAmount: amount,
  isVariableDose: variable,
  daysOfWeek: days,
);

void main() {
  test('dose and how often', () {
    expect(scheduleSummary(_med(), [_at('08:00')]), '1 Tablet · Once a day');
    expect(
      scheduleSummary(_med(), [
        _at('08:00', amount: 2),
        _at('20:00', amount: 2),
      ]),
      '2 Tablets · Twice a day',
    );
  });

  test('every N hours', () {
    expect(
      scheduleSummary(_med(), [
        for (final t in ['02:00', '08:00', '14:00', '20:00']) _at(t),
      ]),
      '1 Tablet · Every 6 hours',
    );
  });

  test('as needed, variable, varying, some days', () {
    expect(scheduleSummary(_med(prn: true), const []), 'As needed');
    expect(
      scheduleSummary(_med(), [_at('08:00', variable: true)]),
      'Variable dose · Once a day',
    );
    expect(
      scheduleSummary(_med(), [
        _at('08:00', amount: 10),
        _at('20:00', amount: 6),
      ]),
      'Varying amounts · Twice a day',
    );
    expect(
      scheduleSummary(_med(), [_at('08:00', days: '1,3,5')]),
      '1 Tablet · Once a day, some days',
    );
  });

  test('creams read naturally', () {
    expect(
      scheduleSummary(_med(form: 'cream'), [_at('08:00'), _at('20:00')]),
      'Apply as directed · Twice a day',
    );
  });
}
