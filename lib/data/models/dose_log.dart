import 'package:flutter/foundation.dart';

/// A record of one scheduled, PRN, or manually logged dose and its outcome.
@immutable
class DoseLog {
  const DoseLog({
    required this.id,
    required this.medicineId,
    this.scheduleId,
    required this.scheduledTime,
    this.actionTime,
    required this.doseAmount,
    required this.status,
  });

  // Status values.
  static const String statusTaken = 'taken';
  static const String statusSkipped = 'skipped';
  static const String statusMissed = 'missed';
  static const String statusPending = 'pending';

  /// UUID.
  final String id;
  final String medicineId;

  /// Null for PRN or manual logs. Not a DB foreign key: see schema notes.
  final String? scheduleId;

  /// Unix ms the dose was due. For PRN logs this equals [actionTime].
  final int scheduledTime;

  /// Unix ms the user acted; null while still pending.
  final int? actionTime;

  /// Actual amount taken, in the medicine's `dose_unit`.
  final double doseAmount;

  /// One of [statusTaken], [statusSkipped], [statusMissed], [statusPending].
  final String status;

  bool get isTaken => status == statusTaken;
  bool get isPending => status == statusPending;

  factory DoseLog.fromMap(Map<String, Object?> map) => DoseLog(
    id: map['id'] as String,
    medicineId: map['medicine_id'] as String,
    scheduleId: map['schedule_id'] as String?,
    scheduledTime: map['scheduled_time'] as int,
    actionTime: map['action_time'] as int?,
    doseAmount: (map['dose_amount'] as num).toDouble(),
    status: map['status'] as String,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'medicine_id': medicineId,
    'schedule_id': scheduleId,
    'scheduled_time': scheduledTime,
    'action_time': actionTime,
    'dose_amount': doseAmount,
    'status': status,
  };

  DoseLog copyWith({
    String? id,
    String? medicineId,
    String? scheduleId,
    int? scheduledTime,
    int? actionTime,
    double? doseAmount,
    String? status,
  }) => DoseLog(
    id: id ?? this.id,
    medicineId: medicineId ?? this.medicineId,
    scheduleId: scheduleId ?? this.scheduleId,
    scheduledTime: scheduledTime ?? this.scheduledTime,
    actionTime: actionTime ?? this.actionTime,
    doseAmount: doseAmount ?? this.doseAmount,
    status: status ?? this.status,
  );

  @override
  bool operator ==(Object other) =>
      other is DoseLog &&
      other.id == id &&
      other.medicineId == medicineId &&
      other.scheduleId == scheduleId &&
      other.scheduledTime == scheduledTime &&
      other.actionTime == actionTime &&
      other.doseAmount == doseAmount &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
    id,
    medicineId,
    scheduleId,
    scheduledTime,
    actionTime,
    doseAmount,
    status,
  );
}
