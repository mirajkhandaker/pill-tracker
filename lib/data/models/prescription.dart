import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// A prescription from a doctor. Medicines may belong to one (or to none, for
/// over-the-counter / self-managed medicines).
///
/// Ending a prescription stops its medicines but keeps the record and all dose
/// history, so past prescriptions stay reviewable.
@immutable
class Prescription {
  const Prescription({
    required this.id,
    required this.doctorName,
    this.reason,
    this.notes,
    required this.issuedAt,
    this.status = statusActive,
    this.endedAt,
    required this.createdAt,
  });

  static const String statusActive = 'active';
  static const String statusEnded = 'ended';

  /// UUID.
  final String id;
  final String doctorName;

  /// Optional short label, e.g. "Blood pressure" or "Chest infection".
  final String? reason;
  final String? notes;

  /// Unix ms (local midnight) of the date the prescription was written.
  final int issuedAt;

  /// [statusActive] or [statusEnded].
  final String status;

  /// Unix ms when it was ended; null while active.
  final int? endedAt;

  /// Unix ms.
  final int createdAt;

  bool get isActive => status == statusActive;

  DateTime get issuedDate => DateTime.fromMillisecondsSinceEpoch(issuedAt);

  /// "Dr. Rahman · 12 Oct 2026" — doctor plus issue date.
  String get label =>
      '$doctorName · ${DateFormat('d MMM yyyy').format(issuedDate)}';

  /// Reason when given, otherwise the doctor — for compact UI.
  String get shortTitle =>
      (reason != null && reason!.isNotEmpty) ? reason! : doctorName;

  factory Prescription.fromMap(Map<String, Object?> map) => Prescription(
    id: map['id'] as String,
    doctorName: map['doctor_name'] as String,
    reason: map['reason'] as String?,
    notes: map['notes'] as String?,
    issuedAt: map['issued_at'] as int,
    status: map['status'] as String? ?? statusActive,
    endedAt: map['ended_at'] as int?,
    createdAt: map['created_at'] as int,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'doctor_name': doctorName,
    'reason': reason,
    'notes': notes,
    'issued_at': issuedAt,
    'status': status,
    'ended_at': endedAt,
    'created_at': createdAt,
  };

  Prescription copyWith({
    String? doctorName,
    String? reason,
    String? notes,
    int? issuedAt,
    String? status,
    int? endedAt,
  }) => Prescription(
    id: id,
    doctorName: doctorName ?? this.doctorName,
    reason: reason ?? this.reason,
    notes: notes ?? this.notes,
    issuedAt: issuedAt ?? this.issuedAt,
    status: status ?? this.status,
    endedAt: endedAt ?? this.endedAt,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Prescription &&
      other.id == id &&
      other.doctorName == doctorName &&
      other.reason == reason &&
      other.notes == notes &&
      other.issuedAt == issuedAt &&
      other.status == status &&
      other.endedAt == endedAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    doctorName,
    reason,
    notes,
    issuedAt,
    status,
    endedAt,
    createdAt,
  );
}
