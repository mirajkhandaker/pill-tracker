import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/medicine.dart';

class MedicineRepository {
  MedicineRepository(this._db);

  final DatabaseHelper _db;
  static const _table = 'medicines';

  Future<List<Medicine>> getAll() async {
    final rows = await _db.query(_table, orderBy: 'name COLLATE NOCASE');
    return rows.map(Medicine.fromMap).toList();
  }

  /// Medicines currently being taken: not stopped, and not past the last day
  /// of a fixed course (relative to [now], default today).
  Future<List<Medicine>> getActive({DateTime? now}) async {
    final rows = await _db.query(
      _table,
      where: 'is_active = 1 AND $ongoingClause',
      whereArgs: [startOfDayMs(now)],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Medicine.fromMap).toList();
  }

  /// SQL condition (one `?` = start of today, ms) for "course not finished".
  static const ongoingClause = '(end_date IS NULL OR end_date >= ?)';

  static int startOfDayMs([DateTime? now]) {
    final t = now ?? DateTime.now();
    return DateTime(t.year, t.month, t.day).millisecondsSinceEpoch;
  }

  Future<Medicine?> getById(String id) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Medicine.fromMap(rows.first);
  }

  Future<void> insert(Medicine medicine) =>
      _db.insert(_table, medicine.toMap());

  Future<void> update(Medicine medicine) => _db.update(
    _table,
    medicine.toMap(),
    where: 'id = ?',
    whereArgs: [medicine.id],
  );

  /// Soft delete: keeps rows (and history) but hides the medicine.
  Future<void> softDelete(String id) =>
      _db.update(_table, {'is_active': 0}, where: 'id = ?', whereArgs: [id]);

  /// Refill flow: add [count] unopened packages to inventory.
  Future<void> addPackages(String medicineId, int count) async {
    final db = await _db.getDb();
    await db.rawUpdate(
      'UPDATE $_table SET packages_in_hand = packages_in_hand + ? WHERE id = ?',
      [count, medicineId],
    );
  }

  /// Refill by a number of units (e.g. "I picked up 30 tablets").
  Future<void> addUnits(String medicineId, double amount) async {
    final db = await _db.getDb();
    await adjustUnitsIn(db, medicineId, -amount);
  }

  /// Core inventory decrement when a dose is taken.
  ///
  /// Reduces loose units by [amount], opening unopened packages as needed
  /// (supporting a single dose larger than one package). Runs in a transaction.
  ///
  /// Returns:
  /// - `true` when the dose was fully covered (or inventory isn't tracked).
  /// - `false` when stock was insufficient: the log should still be recorded by
  ///   the caller, but inventory is clamped to empty and a warning shown.
  Future<bool> decrementUnits(String medicineId, double amount) async {
    final db = await _db.getDb();
    return db.transaction<bool>(
      (txn) => adjustUnitsIn(txn, medicineId, amount),
    );
  }

  /// Changes a medicine's stock by [delta] units within an existing
  /// transaction (or database): positive [delta] consumes stock exactly like
  /// [decrementUnits]; negative [delta] gives units back (e.g. when a logged
  /// dose is corrected or removed), added to the loose units.
  ///
  /// No-op (returns true) for medicines whose supply isn't tracked. Returns
  /// false only when consumption couldn't be fully covered.
  static Future<bool> adjustUnitsIn(
    DatabaseExecutor db,
    String medicineId,
    double delta,
  ) async {
    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [medicineId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final m = Medicine.fromMap(rows.first);

    // Nothing to count when the user doesn't track this supply.
    if (!m.trackInventory) return true;

    var loose = m.looseUnits - delta;
    var packages = m.packagesInHand;

    // Open packages to cover a negative loose balance.
    while (loose < 0 && packages > 0) {
      packages -= 1;
      loose += m.unitsPerPackage;
    }

    final covered = loose >= 0;
    if (!covered) {
      // Not enough stock anywhere: clamp to empty.
      loose = 0;
      packages = 0;
    }

    await db.update(
      _table,
      {'packages_in_hand': packages, 'loose_units': loose},
      where: 'id = ?',
      whereArgs: [medicineId],
    );
    return covered;
  }
}
