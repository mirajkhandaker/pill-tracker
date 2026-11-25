import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/app_logger.dart';

/// Photos are downscaled on capture: plenty to read a prescription, without
/// filling the phone (a full-resolution camera photo can be 5-10 MB).
const _maxPhotoWidth = 2000.0;
const _photoQuality = 85;

/// Takes a photo with the camera, or picks one or more from the gallery.
/// Returns the picked files' paths (empty if cancelled or unavailable).
Future<List<String>> pickPrescriptionPhotos(
  BuildContext context, {
  required bool fromCamera,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final picker = ImagePicker();
  try {
    if (fromCamera) {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxPhotoWidth,
        imageQuality: _photoQuality,
      );
      return shot == null ? const [] : [shot.path];
    }
    final picked = await picker.pickMultiImage(
      maxWidth: _maxPhotoWidth,
      imageQuality: _photoQuality,
      limit: 10,
    );
    return [for (final f in picked) f.path];
  } on PlatformException catch (e) {
    AppLogger.warn('Photo picker failed', e);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          fromCamera
              ? "Couldn't open the camera. Check PillTrack's camera access."
              : "Couldn't open your photos.",
        ),
      ),
    );
    return const [];
  }
}

/// "Take photo" / "Choose photos" buttons.
class PhotoSourceButtons extends StatelessWidget {
  const PhotoSourceButtons({super.key, required this.onPicked});

  final ValueChanged<List<String>> onPicked;

  Future<void> _pick(BuildContext context, {required bool camera}) async {
    final paths = await pickPrescriptionPhotos(context, fromCamera: camera);
    if (paths.isNotEmpty) onPicked(paths);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
            onPressed: () => _pick(context, camera: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose photos'),
            onPressed: () => _pick(context, camera: false),
          ),
        ),
      ],
    );
  }
}

/// A tappable prescription photo thumbnail, with an optional remove button.
class PhotoThumbnail extends StatelessWidget {
  const PhotoThumbnail({
    super.key,
    required this.file,
    required this.label,
    this.onTap,
    this.onRemove,
  });

  final File file;

  /// Spoken description, e.g. "Prescription photo 1 of 2".
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  static const double width = 96;
  static const double height = 128;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: onTap != null,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Material(
              color: scheme.surfaceContainerHighest,
              child: InkWell(
                onTap: onTap,
                child: Image.file(
                  file,
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  // Decode small: thumbnails don't need full-size images.
                  cacheWidth: (width * 3).round(),
                  errorBuilder: (_, _, _) => SizedBox(
                    width: width,
                    height: height,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: scheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove photo',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
            ),
        ],
      ),
    );
  }
}
