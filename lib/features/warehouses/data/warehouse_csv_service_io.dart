import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../models/warehouse.dart';
import '../../../models/warehouse_operations_profile.dart';
import '../../../models/warehouse_trend.dart';

class WarehouseCsvService {
  WarehouseCsvService({this.dataDirectory});

  final String? dataDirectory;

  static const String _defaultWarehouseId = 'schlf-ber03';
  static const String _defaultWarehouseName = 'Schaeflein Lager BER03';
  static const String _defaultWarehouseLocation = 'Standort BER03';

  static const List<String> _databaseFileNames = <String>['warehouse.db'];
  static const List<String> _externalModelFileNames = <String>[
    // Laufzeitfaehige Modelle zuerst (GLB/GLTF), Unity-Quelle als Fallback.
    'SampleScene.glb',
    'warehouse.model.glb',
    'warehouse.model.gltf',
    'warehouse.model.fbx',
    'warehouse.model.obj',
    'warehouse.scene.unity',
  ];

  static const String _platzTable = 'df_platz_ber03_schlg_rti3';
  static const String _paletteTable = 'df_palette_08042026_ber03_schlg_rti3';
  static const String _tpaTable = 'df_tpa_6mon_ber03_schlg_rti3';

  Future<List<Warehouse>> loadWarehousesFromDisk() async {
    final dbFile = await _resolveDatabaseFile();
    if (dbFile == null) {
      return <Warehouse>[];
    }
    return Isolate.run<List<Warehouse>>(
      () => _loadWarehousesFromDatabaseIsolate(dbFile.path),
      debugName: 'warehouse-db-load-warehouses',
    );
  }

  Future<Map<String, WarehouseOperationsProfile>>
      loadOperationsProfilesFromDisk() async {
    final dbFile = await _resolveDatabaseFile();
    if (dbFile == null) {
      return <String, WarehouseOperationsProfile>{};
    }
    return Isolate.run<Map<String, WarehouseOperationsProfile>>(
      () => _loadOperationsProfilesFromDatabaseIsolate(dbFile.path),
      debugName: 'warehouse-db-load-profiles',
    );
  }

  Future<List<WarehouseStorageLocation>> loadStorageLocationsFromDisk({
    int limit = 24,
    String? warehouseId,
  }) async {
    if (warehouseId != null &&
        warehouseId.isNotEmpty &&
        warehouseId != _defaultWarehouseId) {
      return <WarehouseStorageLocation>[];
    }

    final dbFile = await _resolveDatabaseFile();
    if (dbFile == null) {
      return <WarehouseStorageLocation>[];
    }
    return Isolate.run<List<WarehouseStorageLocation>>(
      () => _loadStorageLocationsFromDatabaseIsolate(dbFile.path, limit),
      debugName: 'warehouse-db-load-storage',
    );
  }

  Future<List<WarehouseTrendPoint>> loadThroughputTrendFromDisk({
    int days = 14,
  }) async {
    final dbFile = await _resolveDatabaseFile();
    if (dbFile == null) {
      return <WarehouseTrendPoint>[];
    }
    return Isolate.run<List<WarehouseTrendPoint>>(
      () => _loadThroughputTrendFromDatabaseIsolate(dbFile.path, days),
      debugName: 'warehouse-db-load-trend',
    );
  }

  Future<Map<String, String>> loadExternalModelPathsFromDisk() async {
    final modelFile = await _resolveExternalModelFile();
    if (modelFile == null) {
      return <String, String>{};
    }
    return <String, String>{_defaultWarehouseId: modelFile.path};
  }

  Future<String?> loadActiveDatabasePathFromDisk() async {
    final dbFile = await _resolveDatabaseFile();
    return dbFile?.path;
  }

  Future<List<String>> loadAvailableDatabasePathsFromDisk() async {
    final paths = <String>{};
    final configured = dataDirectory?.trim();
    if (configured != null && configured.isNotEmpty) {
      final configuredFile = File(configured);
      if (configuredFile.path.toLowerCase().endsWith('.db')) {
        if (await configuredFile.exists()) {
          return <String>[configuredFile.path];
        }
      } else {
        final dir = Directory(configured);
        if (await dir.exists()) {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is File && entity.path.toLowerCase().endsWith('.db')) {
              paths.add(entity.path);
            }
          }
        }
      }
    }

    final cwd = Directory.current.path;
    final directories = <Directory>[
      Directory(cwd),
      Directory('$cwd${Platform.pathSeparator}data'),
      Directory('$cwd${Platform.pathSeparator}assets${Platform.pathSeparator}data'),
    ];
    for (final dir in directories) {
      if (!await dir.exists()) {
        continue;
      }
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.db')) {
          paths.add(entity.path);
        }
      }
    }

    final sorted = paths.toList(growable: false)..sort();
    return sorted;
  }

  Future<Map<String, List<WarehouseAbcArticleSummary>>>
      loadAbcArticlesFromDisk({
    int limit = 5000,
  }) async {
    final dbFile = await _resolveDatabaseFile();
    if (dbFile == null) {
      return <String, List<WarehouseAbcArticleSummary>>{};
    }
    return Isolate.run<Map<String, List<WarehouseAbcArticleSummary>>>(
      () => _loadAbcArticlesFromDatabaseIsolate(dbFile.path, limit),
      debugName: 'warehouse-db-load-abc',
    );
  }

  Future<Map<String, List<WarehouseAbcSlotSummary>>> loadAbcSlotsFromDisk({
    int limit = 10000,
  }) async {
    final dbFile = await _resolveDatabaseFile();
    if (dbFile == null) {
      return <String, List<WarehouseAbcSlotSummary>>{};
    }
    return Isolate.run<Map<String, List<WarehouseAbcSlotSummary>>>(
      () => _loadAbcSlotsFromDatabaseIsolate(dbFile.path, limit),
      debugName: 'warehouse-db-load-abc-slots',
    );
  }

  Future<File?> _resolveDatabaseFile() async {
    final candidates = <File>[];
    final configured = dataDirectory?.trim();
    if (configured != null && configured.isNotEmpty) {
      final configuredFile = File(configured);
      if (configuredFile.path.toLowerCase().endsWith('.db')) {
        if (await configuredFile.exists()) {
          return configuredFile;
        }
        candidates.add(configuredFile);
      } else {
        for (final fileName in _databaseFileNames) {
          final candidate =
              File('${configuredFile.path}${Platform.pathSeparator}$fileName');
          if (await candidate.exists()) {
            return candidate;
          }
          candidates.add(candidate);
        }
      }
    }

    final cwd = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final searchRoots = <String>{cwd, exeDir};

    // Wenn die App aus build/windows/... läuft, liegt die DB oft mehrere Ebenen höher.
    for (final root in List<String>.from(searchRoots)) {
      final expanded = _collectParentDirectories(root, maxDepth: 8);
      searchRoots.addAll(expanded);
    }

    for (final fileName in _databaseFileNames) {
      candidates.add(File(fileName));
      candidates.add(File('data${Platform.pathSeparator}$fileName'));
      candidates.add(File('assets${Platform.pathSeparator}data${Platform.pathSeparator}$fileName'));
      for (final root in searchRoots) {
        candidates.add(File('$root${Platform.pathSeparator}$fileName'));
        candidates.add(
          File('$root${Platform.pathSeparator}data${Platform.pathSeparator}$fileName'),
        );
        candidates.add(
          File(
            '$root${Platform.pathSeparator}assets${Platform.pathSeparator}data${Platform.pathSeparator}$fileName',
          ),
        );
      }
    }

    for (final candidate in candidates) {
      if (await candidate.exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<File?> _resolveExternalModelFile() async {
    final candidates = <File>[];
    final configured = dataDirectory?.trim();
    if (configured != null && configured.isNotEmpty) {
      final configuredFile = File(configured);
      if (_hasSupportedModelExtension(configuredFile.path)) {
        candidates.add(configuredFile);
      } else {
        for (final fileName in _externalModelFileNames) {
          candidates.add(
            File('${configuredFile.path}${Platform.pathSeparator}$fileName'),
          );
        }
      }
    }

    final cwd = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final searchRoots = <String>{cwd, exeDir};
    for (final root in List<String>.from(searchRoots)) {
      searchRoots.addAll(_collectParentDirectories(root, maxDepth: 8));
    }

    for (final fileName in _externalModelFileNames) {
      candidates.add(File(fileName));
      candidates.add(File('data${Platform.pathSeparator}$fileName'));
      candidates.add(
        File('assets${Platform.pathSeparator}models${Platform.pathSeparator}$fileName'),
      );
      for (final root in searchRoots) {
        candidates.add(File('$root${Platform.pathSeparator}$fileName'));
        candidates.add(
          File('$root${Platform.pathSeparator}data${Platform.pathSeparator}$fileName'),
        );
        candidates.add(
          File(
            '$root${Platform.pathSeparator}assets${Platform.pathSeparator}models${Platform.pathSeparator}$fileName',
          ),
        );
      }
    }

    // Unity-Quellszene aus importiertem Projekt (Fallback, falls kein GLB/GLTF vorliegt).
    candidates.add(
      File(
        'assets${Platform.pathSeparator}unity_source${Platform.pathSeparator}Scenes${Platform.pathSeparator}SampleScene.unity',
      ),
    );
    for (final root in searchRoots) {
      candidates.add(
        File(
          '$root${Platform.pathSeparator}assets${Platform.pathSeparator}unity_source${Platform.pathSeparator}Scenes${Platform.pathSeparator}SampleScene.unity',
        ),
      );
    }

    for (final candidate in candidates) {
      if (await candidate.exists()) {
        return candidate;
      }
    }
    return null;
  }

  List<String> _collectParentDirectories(String startPath, {int maxDepth = 6}) {
    final result = <String>[];
    var current = Directory(startPath);
    for (var i = 0; i < maxDepth; i++) {
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      result.add(parent.path);
      current = parent;
    }
    return result;
  }

  List<Warehouse> _loadWarehousesFromDatabase(File dbFile) {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);

      final overviewRows = db.select('''
        SELECT
          COUNT(*) AS total_slots,
          SUM(CASE WHEN COALESCE(ZUSTAND, 0) > 0 THEN 1 ELSE 0 END) AS occupied_slots,
          SUM(CASE WHEN
                CAST(COALESCE(MAX_LHM, 0) AS REAL) > 0
                AND CAST(COALESCE(IST_LHM, 0) AS REAL) > CAST(COALESCE(MAX_LHM, 0) AS REAL)
              THEN 1 ELSE 0 END) AS overloaded_slots,
          SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'A' THEN 1 ELSE 0 END) AS abc_a,
          SUM(CASE WHEN UPPER(TRIM(COALESCE(ABC_KLASSE, ''))) = 'B' THEN 1 ELSE 0 END) AS abc_b
        FROM $_platzTable
        WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''
      ''');
      final totalSlots = _readInt(overviewRows, 'total_slots');
      if (totalSlots <= 0) {
        return <Warehouse>[];
      }
      final occupiedSlots = _readInt(
        db.select('''
          SELECT COUNT(*) AS cnt
          FROM (
            SELECT DISTINCT TRIM(COALESCE(PLATZ, '')) AS place_id
            FROM $_paletteTable
            WHERE TRIM(COALESCE(PLATZ,'')) <> ''
          )
        '''),
        'cnt',
      );
      final articleCount = _readInt(
        db.select('''
          SELECT COUNT(*) AS cnt
          FROM (
            SELECT DISTINCT TRIM(COALESCE(ARTIKELNR, '')) AS article_id
            FROM $_tpaTable
            WHERE TRIM(COALESCE(ARTIKELNR,'')) <> ''
          )
        '''),
        'cnt',
      );

      final overloadedSlots = _readInt(overviewRows, 'overloaded_slots');
      final abcA = _readInt(overviewRows, 'abc_a');
      final abcB = _readInt(overviewRows, 'abc_b');
      final abcC = (totalSlots - abcA - abcB).clamp(0, totalSlots);

      final throughputPerDay = (occupiedSlots * 0.18).round();
      final pickRatePerHour = (throughputPerDay / 8).round();

      final inboundPerDay = (throughputPerDay * 1.06).round();
      final zones = _buildZonesFromDatabase(db);

      return <Warehouse>[
        Warehouse(
          id: _defaultWarehouseId,
          name: _defaultWarehouseName,
          location: _defaultWarehouseLocation,
          zoneCount: zones.length,
          status: WarehouseStatus.online,
          description:
              'Stellplaetze, Belegung, Artikel und ABC direkt aus warehouse.db geladen. Pick/h und Durchsatz sind aus DB-Daten abgeleitet.',
          totalStorageSlots: totalSlots,
          occupiedStorageSlots: occupiedSlots.clamp(0, totalSlots),
          overloadedStorageSlots: overloadedSlots,
          articleCount: articleCount,
          abcAnalysis: AbcAnalysis(aCount: abcA, bCount: abcB, cCount: abcC),
          inboundPerDay: inboundPerDay,
          throughputPerDay: throughputPerDay,
          pickRatePerHour: pickRatePerHour.clamp(0, 5000),
          zones: zones,
        ),
      ];
    } catch (_) {
      return <Warehouse>[];
    } finally {
      db?.dispose();
    }
  }

  Map<String, WarehouseOperationsProfile> _loadOperationsProfilesFromDatabase(
    File dbFile,
  ) {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);

      final totalSlots = _readInt(
        db.select(
          "SELECT COUNT(*) AS cnt FROM $_platzTable WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''",
        ),
        'cnt',
      );
      if (totalSlots <= 0) {
        return <String, WarehouseOperationsProfile>{};
      }

      final blockedSlots = _readInt(
        db.select(
          'SELECT COUNT(*) AS cnt FROM $_platzTable WHERE COALESCE(ZUSTAND, 0) >= 150',
        ),
        'cnt',
      );
      final reservedSlots = _readInt(
        db.select(
          "SELECT COUNT(*) AS cnt FROM $_platzTable WHERE TRIM(COALESCE(SPERR_KNZ,'')) <> ''",
        ),
        'cnt',
      );
      final avgDwellDays = _readInt(
        db.select('''
          SELECT ROUND(AVG(diff_days), 0) AS avg_days
          FROM (
            SELECT julianday('now') - julianday(LEER_DATUM) AS diff_days
            FROM $_platzTable
            WHERE TRIM(COALESCE(LEER_DATUM,'')) <> ''
          )
        '''),
        'avg_days',
      );

      final palletType = _readInt(
        db.select(
          "SELECT COUNT(*) AS cnt FROM $_platzTable WHERE UPPER(TRIM(COALESCE(PLATZ_TYP,''))) = 'P'",
        ),
        'cnt',
      );
      final floorType = _readInt(
        db.select(
          "SELECT COUNT(*) AS cnt FROM $_platzTable WHERE UPPER(TRIM(COALESCE(PLATZ_TYP,''))) = 'F'",
        ),
        'cnt',
      );
      final blockType = _readInt(
        db.select(
          "SELECT COUNT(*) AS cnt FROM $_platzTable WHERE UPPER(TRIM(COALESCE(PLATZ_TYP,''))) = 'U'",
        ),
        'cnt',
      );

      final profile = WarehouseOperationsProfile(
        warehouseId: _defaultWarehouseId,
        dockCount: 0,
        activeDocks: 0,
        blockedSlots: blockedSlots.clamp(0, totalSlots),
        reservedSlots: reservedSlots.clamp(0, totalSlots),
        slaTargetPercent: 0,
        slaCurrentPercent: 0,
        avgDwellMinutes: (avgDwellDays * 60).clamp(0, 9999),
        coldZoneCount: 0,
        ambientZoneCount: 0,
        hazardousZoneCount: 0,
        highBaySlots: palletType.clamp(0, totalSlots),
        blockStorageSlots: blockType.clamp(0, totalSlots),
        shuttleSlots:
            (totalSlots - palletType - floorType - blockType).clamp(0, totalSlots),
        floorStorageSlots: floorType.clamp(0, totalSlots),
        safetyIncidentsMonth: 0,
        qualityHolds: blockedSlots.clamp(0, 9999),
      );

      return <String, WarehouseOperationsProfile>{
        _defaultWarehouseId: profile,
      };
    } catch (_) {
      return <String, WarehouseOperationsProfile>{};
    } finally {
      db?.dispose();
    }
  }

  List<WarehouseStorageLocation> _loadStorageLocationsFromDatabase(
    File dbFile, {
    required int limit,
  }) {
    if (limit <= 0) {
      return <WarehouseStorageLocation>[];
    }

    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);
      final rows = db.select('''
        SELECT
          TRIM(p.PLATZ_ID) AS place_id,
          CAST(COALESCE(p.BEREICH, 0) AS TEXT) AS area,
          CAST(COALESCE(p.REGAL, '0') AS INTEGER) AS rack_number,
          CAST(COALESCE(p.EBENE, 0) AS INTEGER) AS level_number,
          CAST(COALESCE(p.FACH, 0) AS INTEGER) AS slot_number,
          UPPER(TRIM(COALESCE(p.ABC_KLASSE, ''))) AS abc_class,
          CAST(COALESCE(p.ZUSTAND, 0) AS INTEGER) AS status_code,
          '' AS artikel_id,
          COALESCE(p.LEER_DATUM, '') AS last_move_day,
          CAST(COALESCE(p.ANZ_PICKS, 0) AS INTEGER) AS movements_30d
        FROM $_platzTable p
        WHERE TRIM(COALESCE(p.PLATZ_ID,'')) <> ''
        ORDER BY CAST(COALESCE(p.REGAL, '0') AS INTEGER) ASC, CAST(COALESCE(p.EBENE, 0) AS INTEGER) ASC, CAST(COALESCE(p.FACH, 0) AS INTEGER) ASC
        LIMIT ?
      ''', <Object>[limit]);

      final now = DateTime.now();
      final result = <WarehouseStorageLocation>[];
      final seen = <String>{};

      for (final row in rows) {
        final placeId = (row['place_id'] ?? '').toString().trim();
        if (placeId.isEmpty || !seen.add(placeId)) {
          continue;
        }

        final rack = _asInt(row['rack_number']);
        final level = _asInt(row['level_number']);
        final slot = _asInt(row['slot_number']);
        if (rack <= 0 || slot <= 0 || level < 0) {
          continue;
        }

        final lastMoveRaw = (row['last_move_day'] ?? '').toString().trim();
        final lastMove = _parseDate(lastMoveRaw);
        final daysSinceMovement = lastMove == null
            ? null
            : now
                .difference(DateTime(lastMove.year, lastMove.month, lastMove.day))
                .inDays;

        result.add(
          WarehouseStorageLocation(
            placeId: placeId,
            area: (row['area'] ?? '').toString(),
            rackNumber: rack,
            levelNumber: level,
            slotNumber: slot,
            abcClass: _normalizeAbcClass((row['abc_class'] ?? '').toString()),
            status: _statusLabelFromCode(_asInt(row['status_code'])),
            articleId: (row['artikel_id'] ?? '').toString().trim(),
            daysSinceMovement: daysSinceMovement,
            movements30d: _asInt(row['movements_30d']),
          ),
        );
      }

      return result;
    } catch (_) {
      return <WarehouseStorageLocation>[];
    } finally {
      db?.dispose();
    }
  }

  List<WarehouseTrendPoint> _loadThroughputTrendFromDatabase(
    File dbFile, {
    required int days,
  }) {
    if (days <= 0) {
      return <WarehouseTrendPoint>[];
    }

    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);
      final rows = db.select('''
        SELECT ENDE_DATUM AS day, COUNT(*) AS count
        FROM $_tpaTable
        WHERE TRIM(COALESCE(ENDE_DATUM,'')) <> ''
        GROUP BY ENDE_DATUM
        ORDER BY ENDE_DATUM DESC
        LIMIT ?
      ''', <Object>[days]);

      final parsed = <WarehouseTrendPoint>[];
      for (final row in rows) {
        final day = _parseDate((row['day'] ?? '').toString().trim());
        if (day == null) {
          continue;
        }
        parsed.add(
          WarehouseTrendPoint(
            date: DateTime(day.year, day.month, day.day),
            value: _asInt(row['count']),
          ),
        );
      }
      parsed.sort((a, b) => a.date.compareTo(b.date));
      return parsed;
    } catch (_) {
      return <WarehouseTrendPoint>[];
    } finally {
      db?.dispose();
    }
  }

  Map<String, List<WarehouseAbcArticleSummary>> _loadAbcArticlesFromDatabase(
    File dbFile, {
    required int limit,
  }) {
    if (limit <= 0) {
      return <String, List<WarehouseAbcArticleSummary>>{};
    }

    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);
      final rows = db.select('''
        WITH article_events AS (
          SELECT
            TRIM(COALESCE(t.ARTIKELNR, '')) AS article_id,
            TRIM(COALESCE(t.Z_PLATZ, '')) AS place_id,
            DATE(t.ENDE_DATUM) AS move_day
          FROM $_tpaTable t
          WHERE TRIM(COALESCE(t.ARTIKELNR, '')) <> ''
            AND TRIM(COALESCE(t.ENDE_DATUM, '')) <> ''
        ),
        article_base AS (
          SELECT
            e.article_id,
            COUNT(*) AS movements_30d,
            CAST(julianday('now') - julianday(MAX(e.move_day)) AS INTEGER) AS max_idle_days
          FROM article_events e
          GROUP BY e.article_id
        ),
        article_slots AS (
          SELECT
            e.article_id,
            COUNT(DISTINCT e.place_id) AS slot_count
          FROM article_events e
          WHERE e.place_id <> ''
          GROUP BY e.article_id
        ),
        article_names AS (
          SELECT
            TRIM(COALESCE(t.ARTIKELNR, '')) AS article_id,
            MAX(TRIM(COALESCE(t.ARTBEZ1, ''))) AS article_description
          FROM $_tpaTable t
          WHERE TRIM(COALESCE(t.ARTIKELNR, '')) <> ''
          GROUP BY TRIM(COALESCE(t.ARTIKELNR, ''))
        ),
        article_abc_votes AS (
          SELECT
            e.article_id,
            UPPER(TRIM(COALESCE(p.ABC_KLASSE, ''))) AS abc_class,
            COUNT(*) AS vote_count
          FROM article_events e
          INNER JOIN $_platzTable p
            ON TRIM(COALESCE(p.PLATZ_ID, '')) = e.place_id
          WHERE e.place_id <> ''
            AND UPPER(TRIM(COALESCE(p.ABC_KLASSE, ''))) IN ('A', 'B', 'C')
          GROUP BY e.article_id, UPPER(TRIM(COALESCE(p.ABC_KLASSE, '')))
        ),
        ranked_votes AS (
          SELECT
            v.article_id,
            v.abc_class,
            v.vote_count,
            ROW_NUMBER() OVER (
              PARTITION BY v.article_id
              ORDER BY v.vote_count DESC,
                CASE v.abc_class WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END
            ) AS rn
          FROM article_abc_votes v
        )
        SELECT
          b.article_id,
          COALESCE(n.article_description, '') AS article_description,
          COALESCE(r.abc_class, '') AS abc_class,
          COALESCE(s.slot_count, 0) AS slot_count,
          COALESCE(b.movements_30d, 0) AS movements_30d,
          COALESCE(b.max_idle_days, 0) AS max_idle_days
        FROM article_base b
        LEFT JOIN article_slots s
          ON s.article_id = b.article_id
        LEFT JOIN article_names n
          ON n.article_id = b.article_id
        LEFT JOIN ranked_votes r
          ON r.article_id = b.article_id
         AND r.rn = 1
        ORDER BY b.movements_30d DESC, b.article_id ASC
        LIMIT ?
      ''', <Object>[limit]);

      if (rows.isEmpty) {
        return <String, List<WarehouseAbcArticleSummary>>{};
      }

      // Pareto-Klassifizierung der Bewegungen: A bis 80 %, B bis 95 %, C Rest.
      // Rows sind bereits nach movements_30d DESC sortiert.
      var totalMoves = 0;
      for (final row in rows) {
        totalMoves += _asInt(row['movements_30d']);
      }
      final summaries = <WarehouseAbcArticleSummary>[];
      var cum = 0;
      for (final row in rows) {
        final articleId = (row['article_id'] ?? '').toString().trim();
        if (articleId.isEmpty) {
          continue;
        }
        final movements = _asInt(row['movements_30d']);
        final slotCount = _asInt(row['slot_count']);
        final idleDays = _asInt(row['max_idle_days']);
        cum += movements;
        final cumPct = totalMoves > 0 ? (cum / totalMoves) * 100 : 0;
        final paretoClass = cumPct <= 80
            ? 'A'
            : (cumPct <= 95 ? 'B' : 'C');
        summaries.add(
          WarehouseAbcArticleSummary(
            articleId: articleId,
            articleDescription:
                (row['article_description'] ?? '').toString().trim(),
            abcClass: paretoClass,
            slotCount: slotCount,
            movements30d: movements,
            maxIdleDays: idleDays,
          ),
        );
      }

      if (summaries.isEmpty) {
        return <String, List<WarehouseAbcArticleSummary>>{};
      }

      return <String, List<WarehouseAbcArticleSummary>>{
        _defaultWarehouseId: summaries,
      };
    } catch (_) {
      return <String, List<WarehouseAbcArticleSummary>>{};
    } finally {
      db?.dispose();
    }
  }

  Map<String, List<WarehouseAbcSlotSummary>> _loadAbcSlotsFromDatabase(
    File dbFile, {
    required int limit,
  }) {
    if (limit <= 0) {
      return <String, List<WarehouseAbcSlotSummary>>{};
    }

    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);
      final rows = db.select(
        '''
        WITH top_article AS (
          SELECT
            TRIM(COALESCE(t.Q_PLATZ, '')) AS place_id,
            TRIM(COALESCE(t.ARTIKELNR, '')) AS article_id,
            TRIM(COALESCE(t.ARTBEZ1, '')) AS article_description,
            COUNT(*) AS picks_for_article,
            ROW_NUMBER() OVER (
              PARTITION BY TRIM(COALESCE(t.Q_PLATZ, ''))
              ORDER BY COUNT(*) DESC, TRIM(COALESCE(t.ARTIKELNR, '')) ASC
            ) AS rn
          FROM $_tpaTable t
          WHERE TRIM(COALESCE(t.Q_PLATZ, '')) <> ''
          GROUP BY
            TRIM(COALESCE(t.Q_PLATZ, '')),
            TRIM(COALESCE(t.ARTIKELNR, '')),
            TRIM(COALESCE(t.ARTBEZ1, ''))
        )
        SELECT
          TRIM(COALESCE(p.PLATZ_ID, '')) AS place_id,
          TRIM(COALESCE(p.HAUSNR, '')) AS halle,
          TRIM(COALESCE(p.BEREICH, '')) AS bereich,
          TRIM(COALESCE(p.REGAL, '')) AS regal,
          TRIM(COALESCE(p.FACH, '')) AS fach,
          TRIM(COALESCE(p.EBENE, '')) AS ebene,
          CAST(COALESCE(p.ANZ_PICKS, 0) AS INTEGER) AS anz_picks,
          UPPER(TRIM(COALESCE(p.ABC_KLASSE, ''))) AS abc_klasse,
          CAST(COALESCE(p.MAX_LHM, 0) AS REAL) AS max_lhm,
          CAST(COALESCE(p.IST_LHM, 0) AS REAL) AS ist_lhm,
          COALESCE(a.article_id, '') AS article_id,
          COALESCE(a.article_description, '') AS article_description
        FROM $_platzTable p
        LEFT JOIN top_article a
          ON a.place_id = TRIM(COALESCE(p.PLATZ_ID, ''))
         AND a.rn = 1
        WHERE TRIM(COALESCE(p.PLATZ_ID, '')) <> ''
        ORDER BY anz_picks DESC, place_id ASC
        LIMIT ?
        ''',
        <Object>[limit],
      );

      if (rows.isEmpty) {
        return <String, List<WarehouseAbcSlotSummary>>{};
      }

      var totalPicks = 0;
      for (final row in rows) {
        totalPicks += _asInt(row['anz_picks']);
      }

      final summaries = <WarehouseAbcSlotSummary>[];
      var cumulativePicks = 0;
      for (final row in rows) {
        final picks = _asInt(row['anz_picks']);
        cumulativePicks += picks;
        final cumPct = totalPicks > 0
            ? (cumulativePicks / totalPicks * 10000).round() / 100.0
            : 0.0;
        final calc = cumPct <= 80
            ? 'A'
            : (cumPct <= 95 ? 'B' : 'C');
        final master = (row['abc_klasse'] ?? '').toString().trim().toUpperCase();
        summaries.add(
          () {
            final maxLhm = _asDouble(row['max_lhm']);
            final istLhm = _asDouble(row['ist_lhm']);
            final freeCap = maxLhm - istLhm;
            final util = maxLhm > 0
                ? ((istLhm / maxLhm) * 10000).round() / 100.0
                : 0.0;
            return WarehouseAbcSlotSummary(
              placeId: (row['place_id'] ?? '').toString().trim(),
              halle: (row['halle'] ?? '').toString().trim(),
              bereich: (row['bereich'] ?? '').toString().trim(),
              regal: (row['regal'] ?? '').toString().trim(),
              fach: (row['fach'] ?? '').toString().trim(),
              ebene: (row['ebene'] ?? '').toString().trim(),
              anzPicks: picks,
              cumulativePct: cumPct,
              abcCalc: calc,
              abcClass: master == 'A' || master == 'B' || master == 'C'
                  ? master
                  : '',
              articleId: (row['article_id'] ?? '').toString().trim(),
              articleDescription:
                  (row['article_description'] ?? '').toString().trim(),
              maxLhm: maxLhm,
              istLhm: istLhm,
              freeCapacity: freeCap,
              utilizationPct: util,
            );
          }(),
        );
      }

      if (summaries.isEmpty) {
        return <String, List<WarehouseAbcSlotSummary>>{};
      }

      return <String, List<WarehouseAbcSlotSummary>>{
        _defaultWarehouseId: summaries,
      };
    } catch (_) {
      return <String, List<WarehouseAbcSlotSummary>>{};
    } finally {
      db?.dispose();
    }
  }

  List<WarehouseZone> _buildZonesFromDatabase(sqlite.Database db) {
    final rows = db.select('''
      WITH base AS (
        SELECT CAST(COALESCE(REGAL, '0') AS INTEGER) AS rack, TRIM(PLATZ_ID) AS platz, UPPER(TRIM(COALESCE(ABC_KLASSE,''))) AS abc_class
        FROM $_platzTable
        WHERE TRIM(COALESCE(PLATZ_ID,'')) <> ''
      ),
      occ AS (
        SELECT DISTINCT TRIM(PLATZ) AS platz
        FROM $_paletteTable
        WHERE TRIM(COALESCE(PLATZ,'')) <> ''
      ),
      placed AS (
        SELECT
          'Lager BER03' AS zone_name,
          platz,
          abc_class,
          CASE WHEN occ.platz IS NULL THEN 0 ELSE 1 END AS occupied
        FROM base
        LEFT JOIN occ ON occ.platz = base.platz
      )
      SELECT
        zone_name,
        COUNT(*) AS total_slots,
        SUM(occupied) AS occupied_slots,
        SUM(CASE WHEN abc_class = 'A' THEN 1 ELSE 0 END) AS a_count,
        SUM(CASE WHEN abc_class = 'B' THEN 1 ELSE 0 END) AS b_count
      FROM placed
      GROUP BY zone_name
      ORDER BY zone_name
    ''');

    final zoneList = <WarehouseZone>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final total = _asInt(row['total_slots']);
      final occupied = _asInt(row['occupied_slots']).clamp(0, total);
      final a = _asInt(row['a_count']).clamp(0, total);
      final b = _asInt(row['b_count']).clamp(0, total);
      final c = (total - a - b).clamp(0, total);
      final zoneName = (row['zone_name'] ?? 'Zone ${i + 1}').toString();

      zoneList.add(
        WarehouseZone(
          id: '$_defaultWarehouseId-z${i + 1}',
          name: zoneName,
          totalStorageSlots: total,
          occupiedStorageSlots: occupied,
          articleCount: total.clamp(0, 50000),
          abcAnalysis: AbcAnalysis(aCount: a, bCount: b, cCount: c),
          inboundPerDay: 0,
          throughputPerDay: 0,
          pickRatePerHour: 0,
        ),
      );
    }

    if (zoneList.isEmpty) {
      return _fallbackZones(3);
    }

    final totalOccupied =
        zoneList.fold<int>(0, (sum, zone) => sum + zone.occupiedStorageSlots);
    final totalThroughput = (totalOccupied * 0.18).round();
    final totalPickRate = (totalThroughput / 8).round();

    final totalSlots =
        zoneList.fold<int>(0, (sum, zone) => sum + zone.totalStorageSlots);
    if (totalSlots <= 0) {
      return zoneList;
    }

    return zoneList.map((zone) {
      final ratio = zone.totalStorageSlots / totalSlots;
      return WarehouseZone(
        id: zone.id,
        name: zone.name,
        totalStorageSlots: zone.totalStorageSlots,
        occupiedStorageSlots: zone.occupiedStorageSlots,
        articleCount: zone.articleCount,
        abcAnalysis: zone.abcAnalysis,
        inboundPerDay: (totalThroughput * ratio * 1.06).round(),
        throughputPerDay: (totalThroughput * ratio).round(),
        pickRatePerHour: (totalPickRate * ratio).round(),
      );
    }).toList(growable: false);
  }

  List<WarehouseZone> _fallbackZones(int count) {
    return List<WarehouseZone>.generate(
      count,
      (index) => WarehouseZone(
        id: '$_defaultWarehouseId-zone-${index + 1}',
        name: 'Zone ${index + 1}',
        totalStorageSlots: 0,
        occupiedStorageSlots: 0,
        articleCount: 0,
        abcAnalysis: const AbcAnalysis(aCount: 0, bCount: 0, cCount: 0),
        inboundPerDay: 0,
        throughputPerDay: 0,
        pickRatePerHour: 0,
      ),
    );
  }

  int _readInt(List<sqlite.Row> rows, String column) {
    if (rows.isEmpty) {
      return 0;
    }
    return _asInt(rows.first[column]);
  }

  double _asDouble(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().trim().replaceAll(',', '.')) ?? 0;
  }

  int _asInt(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  bool _hasSupportedModelExtension(String path) {
    final normalized = path.toLowerCase();
    return normalized.endsWith('.fbx') ||
        normalized.endsWith('.glb') ||
        normalized.endsWith('.gltf') ||
        normalized.endsWith('.obj') ||
        normalized.endsWith('.unity');
  }

  String _normalizeAbcClass(String raw) {
    final value = raw.trim().toUpperCase();
    if (value == 'A' || value == 'B' || value == 'C') {
      return value;
    }
    return 'C';
  }

  String _statusLabelFromCode(int code) {
    if (code >= 150) {
      return 'Gesperrt';
    }
    if (code > 0) {
      return 'Belegt';
    }
    return 'Frei';
  }

  DateTime? _parseDate(String raw) {
    final normalized = raw.trim();
    final iso = DateTime.tryParse(normalized);
    if (iso != null) {
      return iso;
    }

    final parts = normalized.split('.');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }
}

List<Warehouse> _loadWarehousesFromDatabaseIsolate(String dbPath) {
  final service = WarehouseCsvService(dataDirectory: dbPath);
  return service._loadWarehousesFromDatabase(File(dbPath));
}

Map<String, WarehouseOperationsProfile>
    _loadOperationsProfilesFromDatabaseIsolate(String dbPath) {
  final service = WarehouseCsvService(dataDirectory: dbPath);
  return service._loadOperationsProfilesFromDatabase(File(dbPath));
}

List<WarehouseStorageLocation> _loadStorageLocationsFromDatabaseIsolate(
  String dbPath,
  int limit,
) {
  final service = WarehouseCsvService(dataDirectory: dbPath);
  return service._loadStorageLocationsFromDatabase(
    File(dbPath),
    limit: limit,
  );
}

List<WarehouseTrendPoint> _loadThroughputTrendFromDatabaseIsolate(
  String dbPath,
  int days,
) {
  final service = WarehouseCsvService(dataDirectory: dbPath);
  return service._loadThroughputTrendFromDatabase(
    File(dbPath),
    days: days,
  );
}

Map<String, List<WarehouseAbcArticleSummary>>
    _loadAbcArticlesFromDatabaseIsolate(
  String dbPath,
  int limit,
) {
  final service = WarehouseCsvService(dataDirectory: dbPath);
  return service._loadAbcArticlesFromDatabase(
    File(dbPath),
    limit: limit,
  );
}

Map<String, List<WarehouseAbcSlotSummary>> _loadAbcSlotsFromDatabaseIsolate(
  String dbPath,
  int limit,
) {
  final service = WarehouseCsvService(dataDirectory: dbPath);
  return service._loadAbcSlotsFromDatabase(File(dbPath), limit: limit);
}
