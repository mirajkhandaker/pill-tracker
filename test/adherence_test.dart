import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/adherence.dart';
import 'package:pilltrack/data/models/dose_log.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/data/repositories/schedule_repository.dart';

// Wed 2026-10-28 is the "today" used throughout.
final _today = DateTime(2026, 10, 28);

Medicine _med(String id, {DateTime? createdAt}) => Medicine(
  id: id,
  name: id,
  form: 'tablet',
  packageType: 'strip',
  doseUnit: 'pcs',
  unitsPerPackage: 10,
  createdAt: (createdAt ?? DateTime(2026, 1, 1)).millisecondsSinceEpoch,
);

ScheduleWithMedicine _pair(
  Medicine m,
  String time, {
  String id = 's',
  String days = '1,2,3,4,5,6,7',
}) => (
  schedule: Schedule(
    id: '${m.id}-$id',
    medicineId: m.id,
    timeOfDay: time,
    daysOfWeek: days,
  ),
  medicine: m,
);

DoseLog _log(
  String medicineId,
  DateTime at, {
  String status = DoseLog.statusTaken,
  String? scheduleId = 'any',
}) => DoseLog(
  id: '$medicineId-${at.toIso8601String()}-$status',
  medicineId: medicineId,
  scheduleId: scheduleId,
  scheduledTime: at.millisecondsSinceEpoch,
  doseAmount: 1,
  status: status,
);

DayAdherence _day(int expected, int taken) =>
    DayAdherence(day: _today, expected: expected, taken: taken);

void main() {
  group('dailyAdherence', () {
    final a = _med('a');

    test('counts only doses due by the cutoff', () {
      final days = dailyAdherence(
        pairs: [
          _pair(a, '08:00', id: 'am'),
          _pair(a, '20:00', id: 'pm'),
        ],
        logs: [_log('a', DateTime(2026, 10, 28, 8))],
        from: _today,
        to: _today,
        cutoff: DateTime(2026, 10, 28, 12), // noon: the 20:00 dose isn't due
      );
      expect(days.single.expected, 1);
      expect(days.single.taken, 1);
      expect(days.single.complete, isTrue);
    });

    test('matches by medicine, so edited schedules keep their history', () {
      // The log references an old (deleted) schedule id.
      final days = dailyAdherence(
        pairs: [_pair(a, '08:00')],
        logs: [_log('a', DateTime(2026, 10, 27, 8), scheduleId: 'old-id')],
        from: DateTime(2026, 10, 27),
        to: DateTime(2026, 10, 27),
        cutoff: _today,
      );
      expect(days.single.taken, 1);
    });

    test('ignores skipped and PRN logs; caps taken at expected', () {
      final days = dailyAdherence(
        pairs: [_pair(a, '08:00')],
        logs: [
          _log('a', DateTime(2026, 10, 27, 8), status: DoseLog.statusSkipped),
          _log('a', DateTime(2026, 10, 27, 9), scheduleId: null), // PRN
        ],
        from: DateTime(2026, 10, 27),
        to: DateTime(2026, 10, 27),
        cutoff: _today,
      );
      expect(days.single.expected, 1);
      expect(days.single.taken, 0);

      final doubled = dailyAdherence(
        pairs: [_pair(a, '08:00')],
        logs: [
          _log('a', DateTime(2026, 10, 27, 8)),
          _log('a', DateTime(2026, 10, 27, 8, 1)),
        ],
        from: DateTime(2026, 10, 27),
        to: DateTime(2026, 10, 27),
        cutoff: _today,
      );
      expect(doubled.single.taken, 1);
    });

    test('respects weekdays and when the medicine was added', () {
      final added = _med('b', createdAt: DateTime(2026, 10, 27, 12));
      final days = dailyAdherence(
        pairs: [
          _pair(added, '08:00'), // first due Wed 28th
          _pair(a, '08:00', days: '1'), // Mondays only
        ],
        logs: const [],
        from: DateTime(2026, 10, 26), // Mon
        to: _today, // Wed
        cutoff: DateTime(2026, 10, 28, 23),
      );
      expect(days.map((d) => d.expected), [1, 0, 1]);
    });

    test('a dose due before the medicine was added counts only if taken', () {
      // Added tonight at 23:00 with an 08:00 schedule.
      final late = _med('c', createdAt: DateTime(2026, 10, 28, 23));
      List<DayAdherence> run(List<DoseLog> logs) => dailyAdherence(
        pairs: [_pair(late, '08:00')],
        logs: logs,
        from: _today,
        to: _today,
        cutoff: DateTime(2026, 10, 28, 23, 30),
      );

      final untaken = run(const []).single;
      expect(untaken.expected, 0, reason: "isn't held against the user");

      final taken = run([_log('c', DateTime(2026, 10, 28, 8))]).single;
      expect(taken.expected, 1);
      expect(taken.complete, isTrue, reason: 'but counts once logged');
    });
  });

  group('currentStreak', () {
    test('counts consecutive complete days ending today', () {
      expect(currentStreak([_day(1, 0), _day(2, 2), _day(1, 1)]), 2);
    });

    test("an incomplete today doesn't break the streak", () {
      expect(currentStreak([_day(1, 1), _day(1, 1), _day(2, 1)]), 2);
    });

    test('a missed past day breaks it', () {
      expect(currentStreak([_day(1, 1), _day(1, 0), _day(1, 1)]), 1);
    });

    test('days with nothing scheduled are skipped, not breaks', () {
      expect(currentStreak([_day(1, 1), _day(0, 0), _day(1, 1)]), 2);
    });

    test('zero with no data', () => expect(currentStreak(const []), 0));
  });

  group('nextWeeklySummaryTime', () {
    test('later this week', () {
      expect(
        nextWeeklySummaryTime(DateTime(2026, 10, 28, 9)),
        DateTime(2026, 11, 1, 20),
      );
    });
    test('Sunday before 8 PM is the same day', () {
      expect(
        nextWeeklySummaryTime(DateTime(2026, 11, 1, 19, 59)),
        DateTime(2026, 11, 1, 20),
      );
    });
    test('Sunday at/after 8 PM rolls to next week', () {
      expect(
        nextWeeklySummaryTime(DateTime(2026, 11, 1, 20)),
        DateTime(2026, 11, 8, 20),
      );
    });
  });

  group('qualifiesForReviewPrompt', () {
    final now = DateTime(2026, 10, 28);
    List<DayAdherence> week(int taken, int expected) => [
      DayAdherence(day: now, expected: expected, taken: taken),
    ];

    test('needs a full week of use', () {
      expect(
        qualifiesForReviewPrompt(
          firstUse: now.subtract(const Duration(days: 6)),
          now: now,
          recentDays: week(10, 10),
        ),
        isFalse,
      );
    });

    test('needs at least 80% adherence', () {
      final firstUse = now.subtract(const Duration(days: 8));
      expect(
        qualifiesForReviewPrompt(
          firstUse: firstUse,
          now: now,
          recentDays: week(8, 10),
        ),
        isTrue,
      );
      expect(
        qualifiesForReviewPrompt(
          firstUse: firstUse,
          now: now,
          recentDays: week(7, 10),
        ),
        isFalse,
      );
    });

    test('never with nothing scheduled', () {
      expect(
        qualifiesForReviewPrompt(
          firstUse: now.subtract(const Duration(days: 30)),
          now: now,
          recentDays: week(0, 0),
        ),
        isFalse,
      );
    });
  });
}
