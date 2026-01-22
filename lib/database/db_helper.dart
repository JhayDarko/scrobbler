import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/scrobble.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get db async => _db ??= await _initDb();

  Future<Database> _initDb() async {
    try {
      String path = join(await getDatabasesPath(), 'scrobbles.db');
      return await openDatabase(
        path,
        version: 2, // Incrementada versión para migración
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      print('❌ Error inicializando base de datos: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scrobbles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        duration INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        UNIQUE(track, artist, timestamp)
      )
    ''');

    // Crear índices para mejorar performance
    await db.execute('CREATE INDEX idx_is_synced ON scrobbles(is_synced)');
    await db.execute('CREATE INDEX idx_timestamp ON scrobbles(timestamp DESC)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migración de v1 a v2: agregar constraint UNIQUE
      // SQLite no permite ALTER TABLE para agregar constraints, así que recreamos
      await db.execute('DROP TABLE IF EXISTS scrobbles_backup');
      await db.execute('''
        CREATE TABLE scrobbles_backup AS SELECT * FROM scrobbles
      ''');
      await db.execute('DROP TABLE scrobbles');
      await _onCreate(db, newVersion);
      await db.execute('''
        INSERT OR IGNORE INTO scrobbles (id, track, artist, album, duration, timestamp, is_synced)
        SELECT id, track, artist, album, duration, timestamp, is_synced FROM scrobbles_backup
      ''');
      await db.execute('DROP TABLE scrobbles_backup');
    }
  }

  /// Insertar nuevo scrobble con prevención inteligente de duplicados
  Future<int> insertScrobble(Scrobble scrobble) async {
    final dbClient = await db;
    
    try {
      // Verificar duplicados recientes (últimos 2 minutos)
      final twoMinutesAgo = DateTime.now().subtract(const Duration(minutes: 2));
      final recentDuplicates = await dbClient.query(
        'scrobbles',
        where: 'track = ? AND artist = ? AND timestamp >= ?',
        whereArgs: [
          scrobble.track,
          scrobble.artist,
          twoMinutesAgo.toIso8601String(),
        ],
        limit: 1,
      );
      
      if (recentDuplicates.isNotEmpty) {
        print('🚫 Scrobble duplicado detectado, ignorando');
        return 0; // Retornar 0 para indicar que fue ignorado
      }
      
      // Insertar con manejo de conflictos
      return await dbClient.insert(
        'scrobbles',
        scrobble.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore, // Ignorar si hay conflicto UNIQUE
      );
    } catch (e) {
      print('❌ Error insertando scrobble: $e');
      return 0;
    }
  }

  Future<void> updateScrobbleDuration(int id, int newDuration) async {
    final dbClient = await db;
    await dbClient.update(
      'scrobbles',
      {'duration': newDuration},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Obtener scrobbles no sincronizados
  Future<List<Map<String, dynamic>>> getUnsynced() async {
    try {
      final dbClient = await db;
      return await dbClient.query(
        'scrobbles',
        where: 'is_synced = 0',
        orderBy: 'timestamp ASC',
      );
    } catch (e) {
      print('❌ Error obteniendo scrobbles no sincronizados: $e');
      return [];
    }
  }

  /// Obtener todos los scrobbles
  Future<List<Scrobble>> getScrobbles({int limit = 100}) async {
    try {
      final dbClient = await db;
      final maps = await dbClient.query(
        'scrobbles',
        orderBy: 'id DESC',
        limit: limit,
      );
      return maps.map((map) => Scrobble.fromMap(map)).toList();
    } catch (e) {
      print('❌ Error obteniendo scrobbles: $e');
      return [];
    }
  }

  /// Marcar scrobble como sincronizado
  Future<bool> markAsSynced(int id) async {
    try {
      final dbClient = await db;
      final count = await dbClient.update(
        'scrobbles',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count > 0) {
        print('✅ Scrobble $id marcado como sincronizado');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error marcando scrobble como sincronizado: $e');
      return false;
    }
  }

  /// Contar scrobbles totales
  Future<int> getScrobbleCount() async {
    try {
      final dbClient = await db;
      final result = await dbClient.rawQuery(
        'SELECT COUNT(*) as count FROM scrobbles',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      print('❌ Error contando scrobbles: $e');
      return 0;
    }
  }

  /// Verificar si existe un scrobble duplicado reciente
  Future<bool> isDuplicate(
    String track,
    String artist,
    DateTime timestamp,
  ) async {
    try {
      final dbClient = await db;
      final windowStart = timestamp.subtract(const Duration(minutes: 2));
      final windowEnd = timestamp.add(const Duration(minutes: 2));
      
      final result = await dbClient.query(
        'scrobbles',
        where: 'track = ? AND artist = ? AND timestamp >= ? AND timestamp <= ?',
        whereArgs: [
          track,
          artist,
          windowStart.toIso8601String(),
          windowEnd.toIso8601String(),
        ],
        limit: 1,
      );
      
      return result.isNotEmpty;
    } catch (e) {
      print('❌ Error verificando duplicado: $e');
      return false;
    }
  }

  /// Limpiar scrobbles viejos (sincronizados y más antiguos de 30 días)
  Future<int> cleanOldScrobbles() async {
    try {
      final dbClient = await db;
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final count = await dbClient.delete(
        'scrobbles',
        where: 'is_synced = 1 AND timestamp < ?',
        whereArgs: [thirtyDaysAgo.toIso8601String()],
      );
      if (count > 0) {
        print('🗑️ Limpiados $count scrobbles antiguos');
      }
      return count;
    } catch (e) {
      print('❌ Error limpiando scrobbles antiguos: $e');
      return 0;
    }
  }
}
