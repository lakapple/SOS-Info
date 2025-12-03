import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'gemini_service.dart';

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

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // We use (address + date) as a composite unique key to identify specific SMS
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
        isAnalyzed INTEGER
      )
    ''');
    // Index for fast lookup
    await db.execute('CREATE INDEX idx_sms ON analysis(sms_address, sms_date)');
  }

  // SAVE ANALYSIS
  Future<void> cacheAnalysis(String smsAddress, int smsDate, ExtractedInfo info) async {
    final db = await instance.database;
    final data = info.toJson();
    data['sms_address'] = smsAddress;
    data['sms_date'] = smsDate;

    // Remove old entry if exists (re-analysis)
    await db.delete(
      'analysis',
      where: 'sms_address = ? AND sms_date = ?',
      whereArgs: [smsAddress, smsDate],
    );

    await db.insert('analysis', data);
  }

  // GET ANALYSIS
  Future<ExtractedInfo?> getCachedAnalysis(String smsAddress, int smsDate) async {
    final db = await instance.database;
    final maps = await db.query(
      'analysis',
      where: 'sms_address = ? AND sms_date = ?',
      whereArgs: [smsAddress, smsDate],
    );

    if (maps.isNotEmpty) {
      return ExtractedInfo.fromJson(maps.first);
    } else {
      return null;
    }
  }
}