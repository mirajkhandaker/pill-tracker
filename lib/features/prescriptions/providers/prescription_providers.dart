import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/prescription.dart';
import '../../../data/models/prescription_photo.dart';
import '../../../services/photo_store.dart';
import '../../medicines/providers/medicine_providers.dart';

/// Active prescriptions first, then past ones.
final allPrescriptionsProvider = FutureProvider<List<Prescription>>(
  (ref) => ref.watch(prescriptionRepositoryProvider).getAll(),
);

final activePrescriptionsProvider = FutureProvider<List<Prescription>>(
  (ref) => ref.watch(prescriptionRepositoryProvider).getActive(),
);

final prescriptionByIdProvider = FutureProvider.family<Prescription?, String>(
  (ref, id) => ref.watch(prescriptionRepositoryProvider).getById(id),
);

/// Every medicine ever on a prescription (including stopped / finished).
final prescriptionMedicinesProvider =
    FutureProvider.family<List<Medicine>, String>(
      (ref, id) => ref.watch(prescriptionRepositoryProvider).medicinesFor(id),
    );

/// All dose logs for a prescription's medicines, newest first.
final prescriptionLogsProvider = FutureProvider.family<List<DoseLog>, String>((
  ref,
  id,
) async {
  final medicines = await ref.watch(prescriptionMedicinesProvider(id).future);
  return ref
      .watch(doseLogRepositoryProvider)
      .getByMedicines(medicines.map((m) => m.id));
});

/// Photos (pages) of a prescription.
final prescriptionPhotosProvider =
    FutureProvider.family<List<PrescriptionPhoto>, String>(
      (ref, id) => ref.watch(prescriptionRepositoryProvider).photosFor(id),
    );

/// Where photo files live (resolved once).
final photoDirectoryProvider = FutureProvider<Directory>(
  (ref) => PhotoStore.instance.directory(),
);

void invalidatePrescriptionData(Ref ref) {
  ref.invalidate(allPrescriptionsProvider);
  ref.invalidate(activePrescriptionsProvider);
  ref.invalidate(prescriptionByIdProvider);
  ref.invalidate(prescriptionMedicinesProvider);
  ref.invalidate(prescriptionLogsProvider);
  ref.invalidate(prescriptionPhotosProvider);
}

final prescriptionActionsProvider = Provider<PrescriptionActions>(
  (ref) => PrescriptionActions(ref),
);

class PrescriptionActions {
  PrescriptionActions(this._ref);
  final Ref _ref;

  /// Re-reads everything and re-syncs reminders + widget, since prescription
  /// changes can start or stop medicines.
  Future<void> _afterChange() async {
    invalidatePrescriptionData(_ref);
    final medicines = _ref.read(medicineActionsProvider);
    medicines.refreshAll();
    await medicines.resync();
  }

  /// Saves a new prescription, optionally replacing an existing one: the
  /// medicines in [continueMedicineIds] carry over, the rest stop.
  Future<void> create(
    Prescription prescription, {
    String? replaces,
    Set<String> continueMedicineIds = const {},
    List<String> photoPaths = const [],
  }) async {
    final names = await _importPhotos(photoPaths);
    try {
      await _ref
          .read(prescriptionRepositoryProvider)
          .createReplacing(
            prescription,
            replaces: replaces,
            continueMedicineIds: continueMedicineIds,
            photoFileNames: names,
          );
    } catch (_) {
      await _discard(names); // don't leave orphaned copies behind
      rethrow;
    }
    await _afterChange();
  }

  /// Adds photos (picked or captured image paths) to a prescription.
  Future<void> addPhotos(String prescriptionId, List<String> photoPaths) async {
    final names = await _importPhotos(photoPaths);
    try {
      await _ref
          .read(prescriptionRepositoryProvider)
          .addPhotos(prescriptionId, names);
    } catch (_) {
      await _discard(names);
      rethrow;
    }
    _ref.invalidate(prescriptionPhotosProvider(prescriptionId));
  }

  Future<void> removePhoto(PrescriptionPhoto photo) async {
    await _ref.read(prescriptionRepositoryProvider).deletePhoto(photo.id);
    await PhotoStore.instance.delete(photo.fileName);
    _ref.invalidate(prescriptionPhotosProvider(photo.prescriptionId));
  }

  Future<List<String>> _importPhotos(List<String> paths) async {
    final names = <String>[];
    try {
      for (final path in paths) {
        names.add(await PhotoStore.instance.importFile(path));
      }
    } catch (_) {
      await _discard(names);
      rethrow;
    }
    return names;
  }

  Future<void> _discard(List<String> names) async {
    for (final n in names) {
      try {
        await PhotoStore.instance.delete(n);
      } catch (e) {
        // Best effort: an orphaned copy only wastes a little space.
        AppLogger.warn('Could not delete unused photo $n', e);
      }
    }
  }

  Future<void> update(Prescription prescription) async {
    await _ref.read(prescriptionRepositoryProvider).update(prescription);
    await _afterChange();
  }

  /// Ends a prescription and stops all its medicines (history is kept).
  Future<void> end(String id) async {
    await _ref.read(prescriptionRepositoryProvider).end(id);
    await _afterChange();
  }
}
