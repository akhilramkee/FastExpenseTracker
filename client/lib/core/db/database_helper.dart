import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/transaction_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'expense_tracker.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        raw_input TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT NOT NULL,
        tag TEXT NOT NULL,
        merchant TEXT,
        display_label TEXT,
        ai_confidence REAL,
        is_recurring INTEGER DEFAULT 0,
        sync_status TEXT DEFAULT 'pending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_deletes (
        id TEXT PRIMARY KEY
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_deletes (
          id TEXT PRIMARY KEY
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE transactions ADD COLUMN display_label TEXT');
    }
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    final db = await database;
    return await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TransactionModel>> getTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      return TransactionModel.fromMap(maps[i]);
    });
  }

  Future<DateTime?> getLatestTransactionDate() async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DateTime.parse(maps.first['created_at'] as String);
  }

  Future<int> getTransactionCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS count FROM transactions');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<TransactionModel>> getTransactionsByMonthAndYear(int month, int year) async {
    final db = await database;
    final period =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: "substr(created_at, 1, 7) = ?",
      whereArgs: [period],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) => TransactionModel.fromMap(maps[i]));
  }

  Future<List<TransactionModel>> getPendingTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'sync_status = ? OR sync_status = ?',
      whereArgs: [SyncStatus.pending.name, SyncStatus.failed.name],
    );

    return List.generate(maps.length, (i) {
      return TransactionModel.fromMap(maps[i]);
    });
  }

  Future<TransactionModel?> getTransactionById(String id) async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TransactionModel.fromMap(maps.first);
  }

  Future<int> updateTransaction(TransactionModel transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> updateSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    return await db.update(
      'transactions',
      {
        'sync_status': status.name,
        'updated_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTransaction(String id) async {
    final db = await database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> queueDelete(String id) async {
    final db = await database;
    await db.insert(
      'pending_deletes',
      {'id': id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> getPendingDeletes() async {
    final db = await database;
    final rows = await db.query('pending_deletes');
    return rows.map((row) => row['id'] as String).toList();
  }

  Future<void> clearPendingDelete(String id) async {
    final db = await database;
    await db.delete('pending_deletes', where: 'id = ?', whereArgs: [id]);
  }
}
