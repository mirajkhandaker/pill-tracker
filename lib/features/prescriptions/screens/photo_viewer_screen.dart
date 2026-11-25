import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/guarded.dart';
import '../../../data/models/prescription_photo.dart';
import '../providers/prescription_providers.dart';

/// Full-screen prescription photos: swipe between pages, pinch to zoom (handy
/// for reading small handwriting), delete a photo.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.prescriptionId,
    this.initialIndex = 0,
  });

  final String prescriptionId;
  final int initialIndex;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(PrescriptionPhoto photo, int remaining) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('It will be removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    final deleted = await guarded(
      ScaffoldMessenger.of(context),
      "Couldn't delete the photo. Please try again.",
      () => ref.read(prescriptionActionsProvider).removePhoto(photo),
    );
    if (deleted && remaining <= 1) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref
        .watch(prescriptionPhotosProvider(widget.prescriptionId))
        .asData
        ?.value;
    final dir = ref.watch(photoDirectoryProvider).asData?.value;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          photos == null || photos.isEmpty
              ? 'Photo'
              : 'Photo ${_index + 1} of ${photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (photos != null && photos.isNotEmpty)
            IconButton(
              tooltip: 'Delete photo',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(
                photos[_index.clamp(0, photos.length - 1)],
                photos.length,
              ),
            ),
        ],
      ),
      body: photos == null || dir == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.file(
                    File(p.join(dir.path, photos[i].fileName)),
                    fit: BoxFit.contain,
                    semanticLabel:
                        'Prescription photo ${i + 1} of ${photos.length}',
                    errorBuilder: (_, _, _) => const Text(
                      'This photo is no longer available',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
