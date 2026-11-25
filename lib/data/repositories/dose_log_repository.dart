import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/dose_log.dart';
import 'medicine_repository.dart';

/// Result of logging a PRN dose: the stored log plus whether inventory could
/// cover it (false means the caller should warn the user).
typedef PrnLogResult = ({DoseLog log, bool covered});

/// Result of [DoseLogRepository.addLog]: whether the log was stored (false
/// when that scheduled dose was already logged) and whether stock covered it.
typedef AddLogResult = ({bool added, bool covered});

class DoseLogRepository {
  DoseLogRepository(this._db);

  final DatabaseHelper _db;
  static const _table = 'dose_logs';
  static const _uuid = Uuid();

  Future<void> insert(DoseLog log) => _db.insert(_table, log.toMap());

  Future<List<DoseLog>> getPending() async {
    final rows = await _db.query(
      _table,
      where: 'status = ?',
      whereArgs: [DoseLog.statusPending],
      orderBy: 'scheduled_time',
    );
    return rows.map(DoseLog.fromMap).toList();
  }

  Future<List<DoseLog>> getByMedicine(String medicineId, int sinceMs) async {
    final rows = await _db.query(
      _table,
      where: 'medicine_id = ? AND scheduled_time >= ?',
      whereArgs: [medicineId, sinceMs],
      orderBy: 'scheduled_time DESC',
    );
    return rows.map(DoseLog.fromMap).toList();
  }

  /// All logs for any of [medicineIds], newest first.
  Future<List<DoseLog>> getByMedicines(Iterable<String> medicineIds) async {
    final ids = medicineIds.toList();
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.query(
      _table,
      where: 'medicine_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'scheduled_time DESC',
    );
    return rows.map(DoseLog.fromMap).toList();
  }

  Future<List<DoseLog>> getByDateRange(int startMs, int endMs) async {
    final rows = await _db.query(
      _table,
      where: 'scheduled_time >= ? AND scheduled_time < ?',
      whereArgs: [startMs, endMs],
      orderBy: 'scheduled_time DESC',
    );
    return rows.map(DoseLog.fromMap).toList();
  }

  Future<List<DoseLog>> getTodayLogs() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(start.year, start.month, start.day + 1);
    return getByDateRange(
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    );
  }

  Future<void> updateStatus(String id, String status, int? actionTime) =>
      _db.update(
        _table,
        {'status': status, 'action_time': actionTime},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Units actually consumed by [log] (0 unless it was taken).
  static double _consumed(DoseLog log) => log.isTaken ? log.doseAmount : 0;

  /// Saves a corrected log ([updated] replaces [original]) and keeps the
  /// medicine's stock consistent: the difference in amount taken is consumed
  /// or given back, in the same transaction as the log change.
  Future<void> updateLog(DoseLog original, DoseLog updated) async {
    final db = await _db.getDb();
    await db.transaction((txn) async {
      await txn.update(
        _table,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [original.id],
      );
      final delta = _consumed(updated) - _consumed(original);
      if (delta != 0) {
        await MedicineRepository.adjustUnitsIn(txn, original.medicineId, delta);
      }
    });
  }

  /// Records a new log and consumes its amount from stock, in one
  /// transaction.
  ///
  /// A scheduled dose is logged at most once per day: if its schedule already
  /// has a taken or skipped log that day, nothing is written and `added` is
  /// false. Because the check runs inside the transaction, a double tap, or
  /// "Taken" pressed both in the app and on the notification, can't log the
  /// dose (and use up stock) twice. `covered` is false when stock couldn't
  /// fully cover the dose.
  Future<AddLogResult> addLog(DoseLog log) async {
    final db = await _db.getDb();
    return db.transaction<AddLogResult>((txn) async {
      final scheduleId = log.scheduleId;
      if (scheduleId != null &&
          await _isLogged(txn, scheduleId, log.scheduledTime)) {
        return (added: false, covered: true);
      }
      await txn.insert(_table, log.toMap());
      final consumed = _consumed(log);
      final covered =
          consumed == 0 ||
          await MedicineRepository.adjustUnitsIn(txn, log.medicineId, consumed);
      return (added: true, covered: covered);
    });
  }

  /// Whether [scheduleId] already has a taken/skipped log on the local day of
  /// [scheduledMs].
  static Future<bool> _isLogged(
    DatabaseExecutor db,
    String scheduleId,
    int scheduledMs,
  ) async {
    final t = DateTime.fromMillisecondsSinceEpoch(scheduledMs);
    final start = DateTime(t.year, t.month, t.day);
    final end = DateTime(t.year, t.month, t.day + 1);
    final rows = await db.query(
      _table,
      columns: ['id'],
      where:
          'schedule_id = ? AND scheduled_time >= ? AND scheduled_time < ? '
          'AND status != ?',
      whereArgs: [
        scheduleId,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
        DoseLog.statusPending,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Removes a log entirely (e.g. "Taken" tapped by mistake). A scheduled dose
  /// goes back to pending; anything it consumed is returned to stock.
  Future<void> deleteLog(DoseLog log) async {
    final db = await _db.getDb();
    await db.transaction((txn) async {
      await txn.delete(_table, where: 'id = ?', whereArgs: [log.id]);
      final consumed = _consumed(log);
      if (consumed != 0) {
        await MedicineRepository.adjustUnitsIn(txn, log.medicineId, -consumed);
      }
    });
  }

  /// Logs an as-needed dose as taken (scheduled == action == now) and
  /// decrements inventory. Returns the stored log and whether stock covered it.
  Future<PrnLogResult> logPrnDose(String medicineId, double doseAmount) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final log = DoseLog(
      id: _uuid.v4(),
      medicineId: medicineId,
      scheduleId: null,
      scheduledTime: nowMs,
      actionTime: nowMs,
      doseAmount: doseAmount,
      status: DoseLog.statusTaken,
    );
    final result = await addLog(log);
    return (log: log, covered: result.covered);
  }
}
