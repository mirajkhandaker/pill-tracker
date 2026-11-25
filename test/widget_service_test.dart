import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/models/dose_log.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/data/today_doses.dart';
import 'package:pilltrack/services/widget_service.dart';

final _now = DateTime(2026, 10, 31, 12); // Saturday noon

Medicine _med(String name, {String form = 'tablet', String unit = 'pcs'}) =>
    Medicine(
      id: name,
      name: name,
      form: form,
      packageType: 'strip',
      doseUnit: unit,
      unitsPerPackage: 10,
      createdAt: 0,
    );

TodayDose _dose(
  String name,
  int hour, {
  bool taken = false,
  bool variable = false,
  String unit = 'pcs',
}) => TodayDose(
  medicine: _med(name, unit: unit),
  schedule: Schedule(
    id: 's$name',
    medicineId: name,
    timeOfDay: '$hour:00',
    isVariableDose: variable,
  ),
  time: DateTime(2026, 10, 31, hour),
  log: taken
      ? DoseLog(
          id: 'l$name',
          medicineId: name,
          scheduledTime: 0,
          doseAmount: 1,
          status: DoseLog.statusTaken,
        )
      : null,
);

void main() {
  test('shows only pending doses, capped at 3, with overflow count', () {
    final snap = buildWidgetSnapshot([
      _dose('A', 8, taken: true),
      _dose('B', 9),
      _dose('C', 13),
      _dose('D', 18),
      _dose('E', 21),
    ], _now);

    expect(snap.rows.map((r) => r.name), ['B', 'C', 'D']);
    expect(snap.moreCount, 1);
    expect(snap.rows.first.timeLabel, '9:00 AM');
    expect(snap.rows.first.doseText, '1 Tablet');
  });

  test('variable dose reads "Enter amount"', () {
    final snap = buildWidgetSnapshot([
      _dose('Insulin', 8, variable: true, unit: 'IU'),
    ], _now);
    expect(snap.rows.single.doseText, 'Enter amount');
  });

  test('empty labels distinguish "all done" from "nothing scheduled"', () {
    expect(
      buildWidgetSnapshot([_dose('A', 8, taken: true)], _now).emptyLabel,
      'All done for today',
    );
    expect(
      buildWidgetSnapshot(const [], _now).emptyLabel,
      'No doses scheduled today',
    );
  });

  test('toData flattens to string values with a date key for staleness', () {
    final data = buildWidgetSnapshot([_dose('B', 9)], _now).toData();
    expect(data['date_key'], '2026-10-31');
    expect(data['dose_count'], '1');
    expect(data['more_count'], '0');
    expect(data['dose_0_name'], 'B');
    expect(
      data['dose_0_time_ms'],
      '${DateTime(2026, 10, 31, 9).millisecondsSinceEpoch}',
    );
    expect(data.values, everyElement(isA<String>()));
  });
}
