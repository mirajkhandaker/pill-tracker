import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/medicine.dart';
import '../models/prescription.dart';
import '../models/prescription_photo.dart';
import '../models/schedule.dart';

class PrescriptionRepository {
  PrescriptionRepository(this._db);

  final DatabaseHelper _db;
  static const _table = 'prescriptions';
  static const _uuid = Uuid();

  /// Active prescriptions first, then ended ones; newest first within each.
  Future<List<Prescription>> getAll() async {
    final rows = await _db.query(
      _table,
      orderBy: "CASE status WHEN 'active' THEN 0 ELSE 1 END, issued_at DESC",
    );
    return rows.map(Prescription.fromMap).toList();
  }

  Future<List<Prescription>> getActive() async {
    final rows = await _db.query(
      _table,
      where: 'status = ?',
      whereArgs: [Prescription.statusActive],
      orderBy: 'issued_at DESC',
    );
    return rows.map(Prescription.fromMap).toList();
  }

  Future<Prescription?> getById(String id) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Prescription.fromMap(rows.first);
  }

  Future<void> insert(Prescription p) => _db.insert(_table, p.toMap());

  Future<void> update(Prescription p) =>
      _db.update(_table, p.toMap(), where: 'id = ?', whereArgs: [p.id]);

  /// Every medicine ever on [prescriptionId], including stopped ones (so the
  /// prescription keeps showing what it contained).
  Future<List<Medicine>> medicinesFor(String prescriptionId) async {
    final rows = await _db.query(
      'medicines',
      where: 'prescription_id = ?',
      whereArgs: [prescriptionId],
      orderBy: 'is_active DESC, name COLLATE NOCASE',
    );
    return rows.map(Medicine.fromMap).toList();
  }

  /// Ends a prescription: marks it ended and stops all its medicines.
  /// Medicines and dose history are kept.
  Future<void> end(String prescriptionId, {DateTime? at}) async {
    final db = await _db.getDb();
    await db.transaction(
      (txn) => _endIn(txn, prescriptionId, at ?? DateTime.now()),
    );
  }

  /// Saves [newPrescription]. When it [replaces] an existing prescription,
  /// the medicines in [continueMedicineIds] are carried over and the old
  /// prescription is ended (stopping everything not carried over).
  ///
  /// Carried-over medicines are *copied* (new id, same settings, schedules
  /// and remaining stock) rather than moved, so each prescription's dose
  /// history stays attributed to the prescription it happened under.
  Future<void> createReplacing(
    Prescription newPrescription, {
    String? replaces,
    Set<String> continueMedicineIds = const {},
    List<String> photoFileNames = const [],
  }) async {
    final db = await _db.getDb();
    final now = DateTime.now();
    final startOfToday = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert(_table, newPrescription.toMap());
      for (final name in photoFileNames) {
        await txn.insert(
          _photos,
          _photo(newPrescription.id, name, now).toMap(),
        );
      }
      if (replaces == null) return;

      for (final medicineId in continueMedicineIds) {
        final rows = await txn.query(
          'medicines',
          where: 'id = ? AND prescription_id = ?',
          whereArgs: [medicineId, replaces],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final old = Medicine.fromMap(rows.first);
        final copy = old.copyWith(
          id: _uuid.v4(),
          prescriptionId: newPrescription.id,
          isActive: true,
          createdAt: now.millisecondsSinceEpoch,
        );
        await txn.insert('medicines', copy.toMap());

        final schedules = await txn.query(
          'schedules',
          where: 'medicine_id = ?',
          whereArgs: [old.id],
        );
        for (final row in schedules) {
          final s = Schedule.fromMap(row);
          final newId = _uuid.v4();
          await txn.insert(
            'schedules',
            s.copyWith(id: newId, medicineId: copy.id).toMap(),
          );
          // Today's doses already logged move to the copy, so switching
          // prescriptions mid-day doesn't show them as still to take.
          await txn.update(
            'dose_logs',
            {'medicine_id': copy.id, 'schedule_id': newId},
            where:
                'medicine_id = ? AND schedule_id = ? AND scheduled_time >= ?',
            whereArgs: [old.id, s.id, startOfToday],
          );
        }
      }

      await _endIn(txn, replaces, now);
    });
  }

  // --- Photos ---------------------------------------------------------------

  static const _photos = 'prescription_photos';

  static PrescriptionPhoto _photo(String rxId, String fileName, DateTime at) =>
      PrescriptionPhoto(
        id: _uuid.v4(),
        prescriptionId: rxId,
        fileName: fileName,
        createdAt: at.millisecondsSinceEpoch,
      );

  /// Photos of a prescription, in the order they were added (page order).
  Future<List<PrescriptionPhoto>> photosFor(String prescriptionId) async {
    final rows = await _db.query(
      _photos,
      where: 'prescription_id = ?',
      whereArgs: [prescriptionId],
      orderBy: 'created_at, rowid',
    );
    return rows.map(PrescriptionPhoto.fromMap).toList();
  }

  Future<void> addPhotos(String prescriptionId, List<String> fileNames) async {
    final db = await _db.getDb();
    final now = DateTime.now();
    await db.transaction((txn) async {
      for (final name in fileNames) {
        await txn.insert(_photos, _photo(prescriptionId, name, now).toMap());
      }
    });
  }

  Future<void> deletePhoto(String photoId) =>
      _db.delete(_photos, where: 'id = ?', whereArgs: [photoId]);

  static Future<void> _endIn(
    Transaction txn,
    String prescriptionId,
    DateTime at,
  ) async {
    await txn.update(
      _table,
      {
        'status': Prescription.statusEnded,
        'ended_at': at.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [prescriptionId],
    );
    await txn.update(
      'medicines',
      {'is_active': 0},
      where: 'prescription_id = ?',
      whereArgs: [prescriptionId],
    );
  }
}
