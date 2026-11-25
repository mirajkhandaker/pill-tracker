import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilltrack/data/database/database_helper.dart';
import 'package:pilltrack/data/models/prescription.dart';
import 'package:pilltrack/data/repositories/prescription_repository.dart';
import 'package:pilltrack/services/backup_service.dart';
import 'package:pilltrack/services/photo_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Prescription _rx(String id) => Prescription(
  id: id,
  doctorName: 'Dr. Rahman',
  issuedAt: DateTime(2026, 11, 1).millisecondsSinceEpoch,
  createdAt: 0,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PhotoStore', () {
    late Directory base;
    late PhotoStore store;
    setUp(() {
      base = Directory.systemTemp.createTempSync('pilltrack_photos');
      store = PhotoStore(baseDirectory: () async => base);
    });
    tearDown(() => base.deleteSync(recursive: true));

    test('copies a picked image into private storage', () async {
      final picked = File(p.join(base.path, 'picked.JPG'))
        ..writeAsBytesSync([1, 2, 3]);
      final name = await store.importFile(picked.path);

      expect(name, endsWith('.jpg'));
      expect(name, isNot('picked.JPG'), reason: 'gets its own unique name');
      final stored = await store.fileFor(name);
      expect(stored.readAsBytesSync(), [1, 2, 3]);

      // The original can disappear (picker temp files do); the copy remains.
      picked.deleteSync();
      expect(stored.existsSync(), isTrue);
    });

    test('delete and deleteAll remove files', () async {
      final src = File(p.join(base.path, 'a.png'))..writeAsBytesSync([0]);
      final a = await store.importFile(src.path);
      final b = await store.importFile(src.path);
      await store.delete(a);
      expect((await store.fileFor(a)).existsSync(), isFalse);
      expect((await store.fileFor(b)).existsSync(), isTrue);
      await store.deleteAll();
      expect((await store.fileFor(b)).existsSync(), isFalse);
    });
  });

  group('photo records', () {
    late DatabaseHelper db;
    late PrescriptionRepository repo;
    setUp(() {
      db = DatabaseHelper.forTesting(inMemoryDatabasePath);
      repo = PrescriptionRepository(db);
    });
    tearDown(() => db.close());

    test('saved with a new prescription, in page order', () async {
      await repo.createReplacing(
        _rx('r'),
        photoFileNames: ['page1.jpg', 'page2.jpg'],
      );
      final photos = await repo.photosFor('r');
      expect(photos.map((x) => x.fileName), ['page1.jpg', 'page2.jpg']);
    });

    test('added later and deleted individually', () async {
      await repo.insert(_rx('r'));
      await repo.addPhotos('r', ['a.jpg']);
      await repo.addPhotos('r', ['b.jpg']);
      final photos = await repo.photosFor('r');
      expect(photos, hasLength(2));
      await repo.deletePhoto(photos.first.id);
      expect((await repo.photosFor('r')).single.fileName, 'b.jpg');
    });

    test('ending a prescription keeps its photos', () async {
      await repo.createReplacing(_rx('r'), photoFileNames: ['a.jpg']);
      await repo.end('r');
      expect(await repo.photosFor('r'), hasLength(1));
    });

    test('delete-all clears photo records; backups leave them out', () async {
      await repo.createReplacing(_rx('r'), photoFileNames: ['a.jpg']);
      final json = await BackupService.exportJson(db);
      expect(json.contains('a.jpg'), isFalse);

      await BackupService.deleteAll(db);
      expect(await db.query('prescription_photos'), isEmpty);
    });
  });
}
