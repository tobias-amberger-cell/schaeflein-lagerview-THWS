import 'package:csv/csv.dart';
import 'package:flutter/services.dart';

import '../../../models/warehouse.dart';
import '../../../models/warehouse_operations_profile.dart';
import '../../../models/warehouse_trend.dart';
import 'warehouse_master_parser.dart';

class WarehouseCsvService {
  WarehouseCsvService({this.dataDirectory});

  final String? dataDirectory;

  static const String _defaultWarehouseId = 'schlf-ber03';
  static const List<String> _masterAssets = <String>[
    'assets/data/warehouse_ai_master.csv',
  ];
  static const List<String> _platzAssets = <String>[
    'assets/data/df_platz_reduced.csv',
    'assets/data/df_platz_ber03_schlg_rti3.csv',
  ];
  static const List<String> _paletteAssets = <String>[
    'assets/data/df_palette_reduced.csv',
    'assets/data/df_palette_08042026_ber03_schlg_rti3.csv',
  ];
  static const List<String> _orderAssets = <String>[
    'assets/data/df_order_reduced.csv',
    'assets/data/df_order_6mon_schlg_rti3.csv',
  ];
  static const List<String> _tpaAssets = <String>[
    'assets/data/df_tpa_reduced.csv',
    'assets/data/df_tpa_6mon_ber03_schlg_rti3.csv',
  ];

  Future<List<Warehouse>> loadWarehousesFromDisk() async {
    return loadWarehousesFromAssets();
  }

  Future<List<Warehouse>> loadWarehousesFromAssets() async {
    final masterCsv = await _loadAsset(_masterAssets);
    if (masterCsv != null) {
      final parsed = WarehouseMasterParser.parseWarehouses(masterCsv);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    final platzCsv = await _loadAsset(_platzAssets);
    if (platzCsv == null) {
      return <Warehouse>[];
    }

    final paletteCsv = await _loadAsset(_paletteAssets);
    final orderCsv = await _loadAsset(_orderAssets);
    final tpaCsv = await _loadAsset(_tpaAssets);

    final totalSlots = _countRows(platzCsv);
    final occupiedSlots = paletteCsv == null ? 0 : _countRows(paletteCsv);
    final articleCount = orderCsv == null
        ? 0
        : _countUnique(orderCsv, const <String>[
            'artnr',
            'artikelnr',
            'artikel_nr',
            'artikel',
            'article',
            'sku',
          ]);
    final throughputPerDay = tpaCsv == null ? 0 : _estimateThroughput(tpaCsv);

    final abc = _deriveAbc(articleCount);
    return <Warehouse>[
      Warehouse(
        id: _defaultWarehouseId,
        name: 'Schäflein Hauptlager',
        location: 'Berg 03',
        zoneCount: 8,
        status: WarehouseStatus.online,
        description: 'Automatisiert aus CSV-Daten generiert.',
        totalStorageSlots: totalSlots,
        occupiedStorageSlots: occupiedSlots.clamp(0, totalSlots),
        articleCount: articleCount,
        abcAnalysis: abc,
        inboundPerDay: (throughputPerDay * 0.55).round(),
        throughputPerDay: throughputPerDay,
        pickRatePerHour: (throughputPerDay / 10).round(),
        zones: _buildZones(8),
      ),
    ];
  }

  Future<Map<String, WarehouseOperationsProfile>> loadOperationsProfilesFromDisk() async {
    final masterCsv = await _loadAsset(_masterAssets);
    if (masterCsv == null) {
      return <String, WarehouseOperationsProfile>{};
    }
    return WarehouseMasterParser.parseOperationsProfiles(masterCsv);
  }

  Future<List<WarehouseStorageLocation>> loadStorageLocationsFromAssets({
    int limit = 24,
    String? warehouseId,
  }) async {
    final masterCsv = await _loadAsset(_masterAssets);
    if (masterCsv != null) {
      final parsed = WarehouseMasterParser.parseStorageLocations(
        masterCsv,
        limit: limit,
        warehouseId: warehouseId,
      );
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    final platzCsv = await _loadAsset(_platzAssets);
    if (platzCsv == null) {
      return <WarehouseStorageLocation>[];
    }
    return _parseStorageLocations(platzCsv, limit);
  }

  Future<List<WarehouseStorageLocation>> loadStorageLocationsFromDisk({
    int limit = 24,
    String? warehouseId,
  }) async {
    return loadStorageLocationsFromAssets(limit: limit, warehouseId: warehouseId);
  }

  Future<List<WarehouseTrendPoint>> loadThroughputTrendFromAssets({
    int days = 14,
  }) async {
    final masterCsv = await _loadAsset(_masterAssets);
    if (masterCsv != null) {
      final parsed = WarehouseMasterParser.parseThroughputTrend(
        masterCsv,
        days: days,
      );
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    final tpaCsv = await _loadAsset(_tpaAssets);
    if (tpaCsv == null) {
      return <WarehouseTrendPoint>[];
    }
    return _parseThroughputTrend(tpaCsv, days);
  }

  Future<List<WarehouseTrendPoint>> loadThroughputTrendFromDisk({
    int days = 14,
  }) async {
    return loadThroughputTrendFromAssets(days: days);
  }

  Future<String?> _loadAsset(List<String> candidates) async {
    for (final path in candidates) {
      try {
        return await rootBundle.loadString(path);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  int _countRows(String csvText) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvText);
    if (rows.isEmpty) {
      return 0;
    }
    var count = 0;
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  int _countUnique(String csvText, List<String> candidateColumns) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvText);
    if (rows.isEmpty) {
      return 0;
    }
    final header = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList(growable: false);
    final index = _findHeaderIndex(header, candidateColumns);
    if (index == null) {
      return 0;
    }
    final unique = <String>{};
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || index >= row.length) {
        continue;
      }
      final value = row[index].toString().trim();
      if (value.isNotEmpty) {
        unique.add(value);
      }
    }
    return unique.length;
  }

  int _estimateThroughput(String csvText) {
    final total = _countRows(csvText);
    if (total == 0) {
      return 0;
    }
    return (total / 180).round();
  }

  int? _findHeaderIndex(List<String> header, List<String> candidates) {
    for (final candidate in candidates) {
      final index = header.indexOf(candidate);
      if (index != -1) {
        return index;
      }
    }
    return null;
  }

  List<WarehouseStorageLocation> _parseStorageLocations(
    String csvText,
    int limit,
  ) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvText);
    if (rows.isEmpty || limit <= 0) {
      return <WarehouseStorageLocation>[];
    }

    final header = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList(growable: false);
    final rackIndex = _findHeaderIndex(header, const <String>['regal', 'rack']);
    final levelIndex = _findHeaderIndex(header, const <String>['ebene', 'level']);
    final slotIndex = _findHeaderIndex(header, const <String>['fach', 'slot']);
    if (rackIndex == null || levelIndex == null || slotIndex == null) {
      return <WarehouseStorageLocation>[];
    }

    final placeIndex = _findHeaderIndex(
      header,
      const <String>['platz_id', 'platz', 'place_id'],
    );
    final areaIndex = _findHeaderIndex(header, const <String>['bereich', 'area']);
    final abcIndex = _findHeaderIndex(header, const <String>['abc_klasse', 'abc']);
    final statusIndex = _findHeaderIndex(header, const <String>['zustand', 'status']);

    final locations = <WarehouseStorageLocation>[];
    final seen = <String>{};
    for (var i = 1; i < rows.length; i++) {
      if (locations.length >= limit) {
        break;
      }
      final row = rows[i];
      if (row.isEmpty ||
          rackIndex >= row.length ||
          levelIndex >= row.length ||
          slotIndex >= row.length) {
        continue;
      }

      final rack = int.tryParse(row[rackIndex].toString()) ?? 0;
      final level = int.tryParse(row[levelIndex].toString()) ?? 0;
      final slot = int.tryParse(row[slotIndex].toString()) ?? 0;
      if (rack <= 0 || level < 0 || slot <= 0) {
        continue;
      }

      final key = '$rack-$level-$slot';
      if (!seen.add(key)) {
        continue;
      }

      final placeId = placeIndex != null && placeIndex < row.length
          ? row[placeIndex].toString().trim()
          : '';
      final area = areaIndex != null && areaIndex < row.length
          ? row[areaIndex].toString().trim()
          : '';
      final abcClass = abcIndex != null && abcIndex < row.length
          ? row[abcIndex].toString().trim()
          : '';
      final status = statusIndex != null && statusIndex < row.length
          ? row[statusIndex].toString().trim()
          : '';

      locations.add(
        WarehouseStorageLocation(
          placeId: placeId,
          area: area,
          rackNumber: rack,
          levelNumber: level,
          slotNumber: slot,
          abcClass: abcClass,
          status: status,
        ),
      );
    }
    return locations;
  }

  List<WarehouseTrendPoint> _parseThroughputTrend(String csvText, int days) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvText);
    if (rows.isEmpty) {
      return <WarehouseTrendPoint>[];
    }

    final header = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList(growable: false);
    final dateIndex = _findHeaderIndex(header, const <String>[
      'ende_datum',
      'datum',
      'date',
      'end_date',
      'created_at',
    ]);
    if (dateIndex == null) {
      return <WarehouseTrendPoint>[];
    }

    final counts = <DateTime, int>{};
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || dateIndex >= row.length) {
        continue;
      }
      final rawDate = row[dateIndex].toString().trim();
      if (rawDate.isEmpty) {
        continue;
      }
      final parsed = _parseDate(rawDate);
      if (parsed == null) {
        continue;
      }
      final dayKey = DateTime(parsed.year, parsed.month, parsed.day);
      counts.update(dayKey, (value) => value + 1, ifAbsent: () => 1);
    }

    final sortedKeys = counts.keys.toList()..sort((a, b) => a.compareTo(b));
    if (sortedKeys.isEmpty) {
      return <WarehouseTrendPoint>[];
    }
    final limitedKeys = sortedKeys.length > days
        ? sortedKeys.sublist(sortedKeys.length - days)
        : sortedKeys;
    return limitedKeys
        .map((key) => WarehouseTrendPoint(date: key, value: counts[key] ?? 0))
        .toList(growable: false);
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

  AbcAnalysis _deriveAbc(int articleCount) {
    if (articleCount == 0) {
      return const AbcAnalysis(aCount: 0, bCount: 0, cCount: 0);
    }
    final aCount = (articleCount * 0.2).round();
    final bCount = (articleCount * 0.3).round();
    final cCount = (articleCount - aCount - bCount).clamp(0, articleCount);
    return AbcAnalysis(aCount: aCount, bCount: bCount, cCount: cCount);
  }

  List<WarehouseZone> _buildZones(int count) {
    return List<WarehouseZone>.generate(
      count,
      (index) => WarehouseZone(
        id: 'zone-${index + 1}',
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
}
