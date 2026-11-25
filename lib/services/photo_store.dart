import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Keeps prescription photos in the app's private documents folder.
///
/// Picked or captured images are *copied* in, because the picker's own files
/// are temporary and gallery originals can be deleted by the user. Only the
/// file name is stored in the database. Photos never leave the device.
class PhotoStore {
  PhotoStore({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  static final PhotoStore instance = PhotoStore();

  final Future<Directory> Function() _baseDirectory;
  static const _folder = 'prescription_photos';
  static const _uuid = Uuid();

  Directory? _dir;

  /// The photo folder, created on first use.
  Future<Directory> directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = Directory(p.join((await _baseDirectory()).path, _folder));
    await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Copies the image at [sourcePath] into private storage and returns the
  /// stored file name.
  Future<String> importFile(String sourcePath) async {
    final ext = p.extension(sourcePath).toLowerCase();
    final name = '${_uuid.v4()}${ext.isEmpty ? '.jpg' : ext}';
    await File(sourcePath).copy(p.join((await directory()).path, name));
    return name;
  }

  Future<File> fileFor(String fileName) async =>
      File(p.join((await directory()).path, fileName));

  Future<void> delete(String fileName) async {
    final file = await fileFor(fileName);
    if (await file.exists()) await file.delete();
  }

  /// Removes every stored photo (used by "Delete all data" and import).
  Future<void> deleteAll() async {
    final dir = await directory();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
  }
}
