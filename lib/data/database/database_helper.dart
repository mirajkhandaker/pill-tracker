import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the app's single SQLite database connection and schema.
///
/// Use [DatabaseHelper.instance] in the app. Tests (or background isolates that
/// want their own connection) can construct an isolated helper with
/// [DatabaseHelper.forTesting], passing a file path or `inMemoryDatabasePath`.
///
/// Note on units: for the `liquid` form a medicine's `dose_unit` is always
/// stored as `ml`. Teaspoon/tablespoon are input-time conveniences converted to
/// ml before persistence (see Medicine model), so `dose_unit` never holds
/// `tsp`/`tbsp`.
class DatabaseHelper {
  DatabaseHelper._(this._overridePath);

  /// The app-wide singleton, backed by the default on-device database file.
  static final DatabaseHelper instance = DatabaseHelper._(null);

  /// Creates an isolated helper backed by [path]. Intended for tests; pass
  /// `inMemoryDatabasePath` for a throwaway in-memory database.
  factory DatabaseHelper.forTesting(String path) => DatabaseHelper._(path);

  static const String _dbName = 'pilltrack.db';
  static const int _dbVersion = 3;

  final String? _overridePath;
  Database? _db;

  Future<Database> getDb() async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final path = _overridePath ?? p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Enable FK enforcement so medicine -> schedules CASCADE delete works.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE medicines (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        dosage_text TEXT,
        notes TEXT,
        form TEXT NOT NULL,
        package_type TEXT NOT NULL,
        dose_unit TEXT NOT NULL,
        units_per_package REAL NOT NULL,
        packages_in_hand INTEGER NOT NULL DEFAULT 0,
        loose_units REAL NOT NULL DEFAULT 0,
        track_inventory INTEGER NOT NULL DEFAULT 1,
        is_prn INTEGER NOT NULL DEFAULT 0,
        refill_threshold_days INTEGER NOT NULL DEFAULT 3,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE schedules (
        id TEXT PRIMARY KEY,
        medicine_id TEXT NOT NULL,
        time_of_day TEXT NOT NULL,
        dose_amount REAL NOT NULL DEFAULT 1,
        is_variable_dose INTEGER NOT NULL DEFAULT 0,
        days_of_week TEXT NOT NULL,
        FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE
      )
    ''');

    // dose_logs.medicine_id cascades on hard-delete, but schedule_id is a plain
    // nullable column (NOT a foreign key) on purpose: editing a medicine deletes
    // and recreates its schedule rows, and a FK CASCADE there would wipe dose
    // history. Logs must outlive the schedule that produced them.
    batch.execute('''
      CREATE TABLE dose_logs (
        id TEXT PRIMARY KEY,
        medicine_id TEXT NOT NULL,
        schedule_id TEXT,
        scheduled_time INTEGER NOT NULL,
        action_time INTEGER,
        dose_amount REAL NOT NULL,
        status TEXT NOT NULL,
        FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_schedules_medicine_id ON schedules (medicine_id)',
    );
    batch.execute(
      'CREATE INDEX idx_dose_logs_medicine_id ON dose_logs (medicine_id)',
    );
    batch.execute(
      'CREATE INDEX idx_dose_logs_scheduled_time ON dose_logs (scheduled_time)',
    );
    batch.execute('CREATE INDEX idx_dose_logs_status ON dose_logs (status)');

    // Fresh installs run the same steps as upgrades, so a new database and an
    // upgraded one always end up with identical schemas.
    _migrateToV2(batch);
    _migrateToV3(batch);

    await batch.commit(noResult: true);
  }

  /// Stepwise migrations. Each `_migrateToVn` takes the schema from n-1 to n.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    final batch = db.batch();
    if (oldVersion < 2) _migrateToV2(batch);
    if (oldVersion < 3) _migrateToV3(batch);
    await batch.commit(noResult: true);
  }

  /// v2: prescriptions, plus a medicine's prescription link and course end.
  ///
  /// `medicines.prescription_id` is deliberately not a foreign key:
  /// prescriptions are only ever ended, never hard-deleted, and SQLite can't
  /// add FK constraints to an existing table without rebuilding it.
  static void _migrateToV2(Batch batch) {
    batch.execute('''
      CREATE TABLE prescriptions (
        id TEXT PRIMARY KEY,
        doctor_name TEXT NOT NULL,
        reason TEXT,
        notes TEXT,
        issued_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        ended_at INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute('ALTER TABLE medicines ADD COLUMN prescription_id TEXT');
    // Unix ms of local midnight on the course's last day; NULL = ongoing.
    batch.execute('ALTER TABLE medicines ADD COLUMN end_date INTEGER');
    batch.execute(
      'CREATE INDEX idx_medicines_prescription_id ON medicines (prescription_id)',
    );
  }

  /// v3: photos of a prescription (one row per page). Only the file name is
  /// stored; files live in the app's private documents directory, so moving
  /// app storage never breaks the reference.
  static void _migrateToV3(Batch batch) {
    batch.execute('''
      CREATE TABLE prescription_photos (
        id TEXT PRIMARY KEY,
        prescription_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (prescription_id) REFERENCES prescriptions (id)
          ON DELETE CASCADE
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_prescription_photos_rx '
      'ON prescription_photos (prescription_id)',
    );
  }

  // --- Thin convenience wrappers --------------------------------------------

  Future<int> insert(String table, Map<String, Object?> values) async {
    final db = await getDb();
    return db.insert(
      table,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await getDb();
    return db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await getDb();
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await getDb();
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? args,
  ]) async {
    final db = await getDb();
    return db.rawQuery(sql, args);
  }

  /// Closes the underlying connection (mainly for tests / teardown).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
