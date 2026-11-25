import 'package:flutter/foundation.dart';

/// A photo (one page) of a prescription. [fileName] is relative to the
/// app's private photo folder — see PhotoStore.
@immutable
class PrescriptionPhoto {
  const PrescriptionPhoto({
    required this.id,
    required this.prescriptionId,
    required this.fileName,
    required this.createdAt,
  });

  final String id;
  final String prescriptionId;
  final String fileName;

  /// Unix ms.
  final int createdAt;

  factory PrescriptionPhoto.fromMap(Map<String, Object?> map) =>
      PrescriptionPhoto(
        id: map['id'] as String,
        prescriptionId: map['prescription_id'] as String,
        fileName: map['file_name'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'prescription_id': prescriptionId,
    'file_name': fileName,
    'created_at': createdAt,
  };

  @override
  bool operator ==(Object other) =>
      other is PrescriptionPhoto &&
      other.id == id &&
      other.prescriptionId == prescriptionId &&
      other.fileName == fileName &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, prescriptionId, fileName, createdAt);
}
