import 'package:flutter/foundation.dart';

/// A single daily reminder time for a medicine. A medicine has zero schedules
/// when it is PRN (as-needed); otherwise one row per time-of-day.
@immutable
class Schedule {
  const Schedule({
    required this.id,
    required this.medicineId,
    required this.timeOfDay,
    this.doseAmount = 1,
    this.isVariableDose = false,
    this.daysOfWeek = '1,2,3,4,5,6,7',
  });

  /// UUID.
  final String id;
  final String medicineId;

  /// "HH:mm" 24-hour local time.
  final String timeOfDay;

  /// Amount per dose, in the medicine's `dose_unit` (already ml for liquids).
  final double doseAmount;

  /// When true the actual amount is entered at log time (e.g. insulin).
  final bool isVariableDose;

  /// Comma-separated ISO weekday numbers (1=Mon..7=Sun). "1,2,3,4,5,6,7" = daily.
  final String daysOfWeek;

  /// Parsed weekday numbers.
  List<int> get days => daysOfWeek
      .split(',')
      .where((s) => s.trim().isNotEmpty)
      .map((s) => int.parse(s.trim()))
      .toList();

  /// How many days per week this schedule fires (1..7).
  int get dayCount => days.length;

  /// The hour component of [timeOfDay].
  int get hour => int.parse(timeOfDay.split(':')[0]);

  /// The minute component of [timeOfDay].
  int get minute => int.parse(timeOfDay.split(':')[1]);

  factory Schedule.fromMap(Map<String, Object?> map) => Schedule(
    id: map['id'] as String,
    medicineId: map['medicine_id'] as String,
    timeOfDay: map['time_of_day'] as String,
    doseAmount: (map['dose_amount'] as num).toDouble(),
    isVariableDose: (map['is_variable_dose'] as int? ?? 0) == 1,
    daysOfWeek: map['days_of_week'] as String,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'medicine_id': medicineId,
    'time_of_day': timeOfDay,
    'dose_amount': doseAmount,
    'is_variable_dose': isVariableDose ? 1 : 0,
    'days_of_week': daysOfWeek,
  };

  Schedule copyWith({
    String? id,
    String? medicineId,
    String? timeOfDay,
    double? doseAmount,
    bool? isVariableDose,
    String? daysOfWeek,
  }) => Schedule(
    id: id ?? this.id,
    medicineId: medicineId ?? this.medicineId,
    timeOfDay: timeOfDay ?? this.timeOfDay,
    doseAmount: doseAmount ?? this.doseAmount,
    isVariableDose: isVariableDose ?? this.isVariableDose,
    daysOfWeek: daysOfWeek ?? this.daysOfWeek,
  );

  @override
  bool operator ==(Object other) =>
      other is Schedule &&
      other.id == id &&
      other.medicineId == medicineId &&
      other.timeOfDay == timeOfDay &&
      other.doseAmount == doseAmount &&
      other.isVariableDose == isVariableDose &&
      other.daysOfWeek == daysOfWeek;

  @override
  int get hashCode => Object.hash(
    id,
    medicineId,
    timeOfDay,
    doseAmount,
    isVariableDose,
    daysOfWeek,
  );
}
