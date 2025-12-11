import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/extracted_info.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rescue_analysis.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    // Increased version to 2 to trigger upgrade
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE analysis (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sms_address TEXT,
        sms_date INTEGER,
        phoneNumbers TEXT,
        content TEXT,
        peopleCount INTEGER,
        address TEXT,
        requestType TEXT,
        isAnalyzed INTEGER,
        is_sos INTEGER  -- NEW COLUMN: 0 or 1. If NULL, use prefix logic.
      )
    ''');
    await db.execute('CREATE INDEX idx_sms ON analysis(sms_address, sms_date)');
  }

  // Handle migration for existing apps
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE analysis ADD COLUMN is_sos INTEGER');
    }
  }

  // --- SAVE STATE (INFO + IS_SOS) ---
  Future<void> saveMessageState(String smsAddress, int smsDate, ExtractedInfo info, bool isSos) async {
    final db = await instance.database;
    final data = info.toJson();
    data['sms_address'] = smsAddress;
    data['sms_date'] = smsDate;
    data['is_sos'] = isSos ? 1 : 0; // Save the manual overrides

    // Use conflict algorithm replace to handle updates easily
    // Note: We query first to ensure we don't overwrite if not needed, 
    // but DELETE+INSERT is safest for full object updates.
    await db.delete(
      'analysis',
      where: 'sms_address = ? AND sms_date = ?',
      whereArgs: [smsAddress, smsDate],
    );
    await db.insert('analysis', data);
  }

  // --- GET CACHED DATA (RETURNS RAW MAP) ---
  Future<Map<String, dynamic>?> getCachedData(String smsAddress, int smsDate) async {
    final db = await instance.database;
    final maps = await db.query(
      'analysis',
      where: 'sms_address = ? AND sms_date = ?',
      whereArgs: [smsAddress, smsDate],
    );

    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }
}