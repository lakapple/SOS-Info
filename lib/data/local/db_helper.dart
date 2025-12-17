import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/extracted_info.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rescue_v3.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE analysis (
        sms_address TEXT,
        sms_date INTEGER,
        phoneNumbers TEXT,
        content TEXT,
        peopleCount INTEGER,
        address TEXT,
        lat REAL,
        lng REAL,
        requestType TEXT,
        isAnalyzed INTEGER,
        is_sos INTEGER,
        PRIMARY KEY (sms_address, sms_date)
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE analysis ADD COLUMN lat REAL');
      await db.execute('ALTER TABLE analysis ADD COLUMN lng REAL');
    }
  }

  Future<void> saveState(String addr, int date, ExtractedInfo info, bool isSos) async {
    final db = await instance.database;
    final data = info.toJson();
    data['sms_address'] = addr;
    data['sms_date'] = date;
    data['is_sos'] = isSos ? 1 : 0;
    await db.insert('analysis', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getRecord(String addr, int date) async {
    final db = await instance.database;
    final res = await db.query('analysis', where: 'sms_address = ? AND sms_date = ?', whereArgs: [addr, date]);
    return res.isNotEmpty ? res.first : null;
  }
}