import 'package:flutter/material.dart';

/// How often a scheduled medicine is taken each day. Every option is stored
/// the same way — as a list of daily reminder times — so this only drives
/// how the Add/Edit screen helps the user fill those times in.
enum DoseFrequency {
  once('Once a day'),
  twice('Twice a day'),
  thrice('3 times a day'),
  interval('Every few hours'),
  custom('Custom');

  const DoseFrequency(this.label);
  final String label;
}

/// Hour gaps offered for [DoseFrequency.interval]. Each divides the day
/// evenly and yields at most 6 doses (the app's per-medicine maximum).
const intervalChoices = [4, 6, 8, 12];

/// Default times for the "N times a day" presets.
List<TimeOfDay> presetTimes(DoseFrequency f) => switch (f) {
  DoseFrequency.once => const [TimeOfDay(hour: 8, minute: 0)],
  DoseFrequency.twice => const [
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 20, minute: 0),
  ],
  DoseFrequency.thrice => const [
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 14, minute: 0),
    TimeOfDay(hour: 20, minute: 0),
  ],
  _ => const [],
};

/// Daily times for a dose every [hours] hours starting at [first], in dose
/// order — e.g. every 8 hours from 10 PM gives 10 PM, 6 AM, 2 PM.
List<TimeOfDay> intervalTimes(TimeOfDay first, int hours) {
  final start = first.hour * 60 + first.minute;
  return [
    for (var i = 0; i < 24 ~/ hours; i++)
      _fromMinutes((start + i * hours * 60) % (24 * 60)),
  ];
}

/// Recognises which option a medicine's saved daily [times] correspond to,
/// so editing it shows the same choice the user made. Evenly spaced times
/// that fit an [intervalChoices] gap are "every N hours" (when there are more
/// than three); otherwise 1–3 times are the matching preset, and anything
/// else is custom.
({DoseFrequency frequency, int intervalHours}) inferFrequency(
  List<TimeOfDay> times,
) {
  const fallbackInterval = 8;
  final n = times.length;
  if (n > 3 && 24 % n == 0 && intervalChoices.contains(24 ~/ n)) {
    final minutes = times.map((t) => t.hour * 60 + t.minute).toList()..sort();
    final gap = 24 * 60 ~/ n;
    var even = true;
    for (var i = 0; i < n; i++) {
      final next = i == n - 1 ? minutes.first + 24 * 60 : minutes[i + 1];
      if (next - minutes[i] != gap) even = false;
    }
    if (even) {
      return (frequency: DoseFrequency.interval, intervalHours: 24 ~/ n);
    }
  }
  final frequency = switch (n) {
    1 => DoseFrequency.once,
    2 => DoseFrequency.twice,
    3 => DoseFrequency.thrice,
    _ => DoseFrequency.custom,
  };
  return (frequency: frequency, intervalHours: fallbackInterval);
}

TimeOfDay _fromMinutes(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);
