import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/models/dose_log.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/services/notification_service.dart';

const _med = Medicine(
  id: 'm',
  name: 'Med',
  form: 'tablet',
  packageType: 'strip',
  doseUnit: 'pcs',
  unitsPerPackage: 0,
  createdAt: 0,
);
const _schedule = Schedule(id: 's', medicineId: 'm', timeOfDay: '20:00');

DoseLog _log(DateTime due, String status) => DoseLog(
  id: 'l',
  medicineId: 'm',
  scheduleId: 's',
  scheduledTime: due.millisecondsSinceEpoch,
  doseAmount: 1,
  status: status,
);

void main() {
  final now = DateTime(2026, 11, 16, 12);
  final tonight = DateTime(2026, 11, 16, 20);

  group('logged doses get no reminder', () {
    test('a dose taken early is left out; later days are not', () {
      final occ = reminderOccurrences(
        [_schedule],
        [_med],
        now,
        logged: loggedDoseKeys([_log(tonight, DoseLog.statusTaken)]),
      );
      expect(occ.first.time, DateTime(2026, 11, 17, 20));
      expect(occ, hasLength(NotificationService.horizonDays));
    });

    test('skipped counts as logged; pending and PRN logs do not', () {
      final keys = loggedDoseKeys([
        _log(tonight, DoseLog.statusSkipped),
        _log(DateTime(2026, 11, 17, 20), DoseLog.statusPending),
        DoseLog(
          id: 'prn',
          medicineId: 'm',
          scheduledTime: tonight.millisecondsSinceEpoch,
          doseAmount: 1,
          status: DoseLog.statusTaken,
        ),
      ]);
      expect(keys, {doseDayKey('s', tonight)});
    });
  });

  group('snoozes survive a re-sync', () {
    final ms = tonight.millisecondsSinceEpoch;
    final payload = NotificationService.snoozePayload('m', 's', ms);

    test('kept while the dose is still to take', () {
      expect(keepSnooze(payload, {'m'}, const {}), isTrue);
    });

    test('dropped once the dose is logged', () {
      expect(keepSnooze(payload, {'m'}, {doseDayKey('s', tonight)}), isFalse);
    });

    test('dropped when the medicine is stopped', () {
      expect(keepSnooze(payload, const {}, const {}), isFalse);
    });

    test('regular reminders and the weekly summary are not snoozes', () {
      expect(keepSnooze('m|s|$ms', {'m'}, const {}), isFalse);
      expect(keepSnooze(null, {'m'}, const {}), isFalse);
    });

    test('snoozing the same dose again reuses one notification id', () {
      expect(
        NotificationService.idFor(NotificationService.snoozeKey('m', 's', ms)),
        NotificationService.idFor(NotificationService.snoozeKey('m', 's', ms)),
      );
    });
  });
}
