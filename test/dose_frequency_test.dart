import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/core/utils/dose_frequency.dart';

TimeOfDay t(int h, [int m = 0]) => TimeOfDay(hour: h, minute: m);

void main() {
  test('presets give sensible default times', () {
    expect(presetTimes(DoseFrequency.once), [t(8)]);
    expect(presetTimes(DoseFrequency.twice), [t(8), t(20)]);
    expect(presetTimes(DoseFrequency.thrice), [t(8), t(14), t(20)]);
  });

  group('intervalTimes', () {
    test('every 8 hours from 8 AM', () {
      expect(intervalTimes(t(8), 8), [t(8), t(16), t(0)]);
    });
    test('wraps past midnight in dose order', () {
      expect(intervalTimes(t(22), 8), [t(22), t(6), t(14)]);
    });
    test('keeps minutes', () {
      expect(intervalTimes(t(7, 30), 12), [t(7, 30), t(19, 30)]);
    });
    test('every 4 hours is 6 doses (the per-medicine maximum)', () {
      expect(intervalTimes(t(6), 4), hasLength(6));
    });
  });

  group('inferFrequency', () {
    test('1-3 times map to the presets, whatever the times', () {
      expect(inferFrequency([t(9)]).frequency, DoseFrequency.once);
      expect(inferFrequency([t(7), t(19)]).frequency, DoseFrequency.twice);
      expect(
        inferFrequency([t(6), t(14), t(22)]).frequency,
        DoseFrequency.thrice,
      );
    });

    test('evenly spaced 4+ times are every N hours', () {
      final r = inferFrequency(intervalTimes(t(6), 4));
      expect(r.frequency, DoseFrequency.interval);
      expect(r.intervalHours, 4);
      expect(inferFrequency([t(0), t(6), t(12), t(18)]).intervalHours, 6);
    });

    test('uneven 4+ times are custom', () {
      expect(
        inferFrequency([t(6), t(9), t(12), t(22)]).frequency,
        DoseFrequency.custom,
      );
    });

    test('round-trips with intervalTimes regardless of order', () {
      for (final h in [4, 6]) {
        final times = intervalTimes(t(21, 15), h);
        final r = inferFrequency(times.reversed.toList());
        expect(r.frequency, DoseFrequency.interval);
        expect(r.intervalHours, h);
      }
    });
  });
}
