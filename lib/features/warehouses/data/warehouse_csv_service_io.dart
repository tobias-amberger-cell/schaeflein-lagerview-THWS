import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';

import '../../../models/warehouse.dart';

class WarehouseCsvService {
  WarehouseCsvService({this.dataDirectory});

  final String? dataDirectory;

  static const String _defaultWarehouseId = 'schlf-ber03';

  Future<List<Warehouse>> loadWarehousesFromDisk() async {
    if (dataDirectory == null || dataDirectory!.isEmpty) {
      return <Warehouse>[];
    }

    final dir = Directory(dataDirectory!);
    if (!await dir.exists()) {
      return <Warehouse>[];
    }

    final platzFile = _resolveFile(
      dir,
      reducedName: 'df_platz_reduced.csv',
      originalName: 'df_platz_ber03_schlg_rti3.csv',
    );
    final paletteFile = _resolveFile(
      dir,
      reducedName: 'df_palette_reduced.csv',
      originalName: 'df_palette_08042026_ber03_schlg_rti3.csv',
    );
    final orderFile = _resolveFile(
      dir,
      reducedName: 'df_order_reduced.csv',
      originalName: 'df_order_6mon_schlg_rti3.csv',
    );
    final tpaFile = _resolveFile(
      dir,
      reducedName: 'df_tpa_reduced.csv',
      originalName: 'df_tpa_6mon_ber03_schlg_rti3.csv',
    );

    if (!await platzFile.exists()) {
      return <Warehouse>[];
    }

    final totalSlots = await _countRows(platzFile);
    final occupiedSlots =
        (await paletteFile.exists()) ? await _countRows(paletteFile) : 0;
    final articleCount = (await orderFile.exists())
        ? await _countUnique(
            orderFile,
            const <String>['artnr', 'artikel', 'article', 'sku'],
          )
        : 0;
    final throughputPerDay =
        (await tpaFile.exists()) ? await _estimateThroughput(tpaFile) : 0;

    final abc = _deriveAbc(totalSlots, articleCount);

    final warehouse = Warehouse(
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
    );

    return <Warehouse>[warehouse];
  }

  Future<List<WarehouseStorageLocation>> loadStorageLocationsFromDisk({
    int limit = 24,
  }) async {
    if (dataDirectory == null || dataDirectory!.isEmpty) {
      return <WarehouseStorageLocation>[];
    }
    final dir = Directory(dataDirectory!);
    if (!await dir.exists()) {
      return <WarehouseStorageLocation>[];
    }
    final platzFile = _resolveFile(
      dir,
      reducedName: 'df_platz_reduced.csv',
      originalName: 'df_platz_ber03_schlg_rti3.csv',
    );
    if (!await platzFile.exists()) {
      return <WarehouseStorageLocation>[];
    }
    final csvText = await platzFile.readAsString();
    return _parseStorageLocations(csvText, limit);
  }

  Future<int> _countRows(File file) async {
    final stream = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const CsvToListConverter(eol: '\n'));
    var count = 0;
    var isHeader = true;
    await for (final row in stream) {
      if (isHeader) {
        isHeader = false;
        continue;
      }
      if (row.isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  Future<int> _countUnique(File file, List<String> candidateColumns) async {
    final stream = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const CsvToListConverter(eol: '\n'));
    final unique = <String>{};
    var header = <String>[];
    var isHeader = true;
    await for (final row in stream) {
      if (isHeader) {
        header =
            row.map((cell) => cell.toString().trim().toLowerCase()).toList();
        isHeader = false;
        continue;
      }
      if (row.isEmpty) {
        continue;
      }
      final index = _findHeaderIndex(header, candidateColumns);
      if (index == null || index >= row.length) {
        continue;
      }
      final value = row[index].toString().trim();
      if (value.isNotEmpty) {
        unique.add(value);
      }
    }
    return unique.length;
  }

  Future<int> _estimateThroughput(File file) async {
    final total = await _countRows(file);
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
        .toList();
    final rackIndex = _findHeaderIndex(header, const <String>['regal', 'rack']);
    final levelIndex = _findHeaderIndex(header, const <String>['ebene', 'level']);
    final slotIndex = _findHeaderIndex(header, const <String>['fach', 'slot']);
    if (rackIndex == null || levelIndex == null || slotIndex == null) {
      return <WarehouseStorageLocation>[];
    }
    final placeIndex =
        _findHeaderIndex(header, const <String>['platz_id', 'platz', 'place_id']);
    final areaIndex = _findHeaderIndex(header, const <String>['bereich', 'area']);
    final abcIndex =
        _findHeaderIndex(header, const <String>['abc_klasse', 'abc']);
    final statusIndex =
        _findHeaderIndex(header, const <String>['zustand', 'status']);

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

  AbcAnalysis _deriveAbc(int totalSlots, int articleCount) {
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

  File _resolveFile(
    Directory dir, {
    required String reducedName,
    required String originalName,
  }) {
    final reduced = File('${dir.path}${Platform.pathSeparator}$reducedName');
    if (reduced.existsSync()) {
      return reduced;
    }
    return File('${dir.path}${Platform.pathSeparator}$originalName');
  }
}
