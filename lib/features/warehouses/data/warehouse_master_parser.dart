import 'package:csv/csv.dart';

import '../../../models/warehouse.dart';
import '../../../models/warehouse_operations_profile.dart';
import '../../../models/warehouse_trend.dart';

class WarehouseMasterParser {
  const WarehouseMasterParser._();

  static List<Warehouse> parseWarehouses(String csvText) {
    final rows = _parseRows(csvText);
    if (rows.isEmpty) {
      return <Warehouse>[];
    }

    final aggregates = <String, _WarehouseAggregate>{};
    for (final row in rows) {
      final warehouseId = _warehouseIdFromRow(row);
      final aggregate = aggregates.putIfAbsent(
        warehouseId,
        () => _WarehouseAggregate(
          id: warehouseId,
          name: _warehouseNameFromRow(row),
          location: _locationFromRow(row),
        ),
      );
      aggregate.addRow(row);
    }

    final result = aggregates.values.map((aggregate) => aggregate.toWarehouse()).toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  static List<WarehouseStorageLocation> parseStorageLocations(
    String csvText, {
    required int limit,
    String? warehouseId,
  }) {
    final rows = _parseRows(csvText);
    if (rows.isEmpty || limit <= 0) {
      return <WarehouseStorageLocation>[];
    }

    final filtered = rows.where((row) {
      if (warehouseId == null || warehouseId.isEmpty) {
        return true;
      }
      return _warehouseIdFromRow(row) == warehouseId;
    }).toList(growable: false);

    if (filtered.isEmpty) {
      return <WarehouseStorageLocation>[];
    }

    final sorted = filtered.toList()
      ..sort((a, b) {
        final aRisk = _toDouble(_read(a, const <String>['kritikalitaet_score'])) ?? 0;
        final bRisk = _toDouble(_read(b, const <String>['kritikalitaet_score'])) ?? 0;
        final riskCompare = bRisk.compareTo(aRisk);
        if (riskCompare != 0) {
          return riskCompare;
        }
        final aMoves = _toInt(_read(a, const <String>['bewegungen_30d'])) ?? 0;
        final bMoves = _toInt(_read(b, const <String>['bewegungen_30d'])) ?? 0;
        return bMoves.compareTo(aMoves);
      });

    final locations = <WarehouseStorageLocation>[];
    final seenPlaceIds = <String>{};
    for (final row in sorted) {
      if (locations.length >= limit) {
        break;
      }
      final placeId = _read(row, const <String>['platz_id'])?.trim() ?? '';
      if (placeId.isEmpty || !seenPlaceIds.add(placeId)) {
        continue;
      }

      final rackRaw = _read(row, const <String>['regal']) ?? '';
      final levelRaw = _read(row, const <String>['ebene']) ?? '';
      final slotRaw = _read(row, const <String>['fach']) ?? '';

      final rackNumber = _rackNumberFromRaw(rackRaw, fallbackSeed: placeId);
      final levelNumber = (_toInt(levelRaw) ?? 0).clamp(0, 9999);
      final slotFromRaw = _toInt(slotRaw);
      final slotNumber = (slotFromRaw ?? _slotFromPlaceId(placeId)).clamp(1, 9999);

      final isBlocked = (_toInt(_read(row, const <String>['ist_gesperrt'])) ?? 0) > 0;
      final isOccupied =
          (_toInt(_read(row, const <String>['aktueller_belegt_status'])) ?? 0) > 0;
      final status = isBlocked
          ? 'Gesperrt'
          : (isOccupied ? 'Belegt' : 'Frei');

      locations.add(
        WarehouseStorageLocation(
          placeId: placeId,
          area: _read(row, const <String>['zone', 'standort']) ?? '',
          rackNumber: rackNumber,
          levelNumber: levelNumber,
          slotNumber: slotNumber,
          abcClass: (_read(row, const <String>['abc_klasse']) ?? '').toUpperCase(),
          status: status,
        ),
      );
    }

    return locations;
  }

  static Map<String, WarehouseOperationsProfile> parseOperationsProfiles(
    String csvText,
  ) {
    final rows = _parseRows(csvText);
    if (rows.isEmpty) {
      return <String, WarehouseOperationsProfile>{};
    }

    final aggregates = <String, _WarehouseAggregate>{};
    for (final row in rows) {
      final warehouseId = _warehouseIdFromRow(row);
      final aggregate = aggregates.putIfAbsent(
        warehouseId,
        () => _WarehouseAggregate(
          id: warehouseId,
          name: _warehouseNameFromRow(row),
          location: _locationFromRow(row),
        ),
      );
      aggregate.addRow(row);
    }

    return aggregates.map((key, agg) =>
        MapEntry(key, agg.toOperationsProfile()));
  }

  static List<WarehouseTrendPoint> parseThroughputTrend(
    String csvText, {
    required int days,
    String? warehouseId,
  }) {
    final rows = _parseRows(csvText);
    if (rows.isEmpty || days <= 0) {
      return <WarehouseTrendPoint>[];
    }

    final daily = <DateTime, int>{};
    for (final row in rows) {
      if (warehouseId != null && warehouseId.isNotEmpty) {
        if (_warehouseIdFromRow(row) != warehouseId) {
          continue;
        }
      }

      final activityDate = _activityDateFromRow(row);
      if (activityDate == null) {
        continue;
      }

      final activityValue = _toInt(_read(row, const <String>['bewegungen_30d'])) ?? 0;
      final fallbackValue = _toInt(_read(row, const <String>['bewegungen_6mon'])) ?? 0;
      final points = activityValue > 0 ? activityValue : (fallbackValue / 6).round();
      if (points <= 0) {
        continue;
      }

      final dayKey = DateTime(activityDate.year, activityDate.month, activityDate.day);
      daily.update(dayKey, (value) => value + points, ifAbsent: () => points);
    }

    if (daily.isEmpty) {
      return <WarehouseTrendPoint>[];
    }

    final sortedKeys = daily.keys.toList()..sort((a, b) => a.compareTo(b));
    final from = sortedKeys.length > days ? sortedKeys.length - days : 0;
    final limited = sortedKeys.sublist(from);
    return limited
        .map((date) => WarehouseTrendPoint(date: date, value: daily[date] ?? 0))
        .toList(growable: false);
  }

  static List<Map<String, String>> _parseRows(String csvText) {
    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csvText);

    if (rows.length <= 1) {
      return <Map<String, String>>[];
    }

    final header = rows.first
        .map((cell) => _normalizeKey(cell.toString()))
        .toList(growable: false);
    final result = <Map<String, String>>[];

    for (var i = 1; i < rows.length; i++) {
      final rawRow = rows[i];
      if (rawRow.isEmpty) {
        continue;
      }
      final row = <String, String>{};
      for (var col = 0; col < header.length; col++) {
        if (col >= rawRow.length) {
          break;
        }
        row[header[col]] = rawRow[col].toString();
      }
      if (row.isNotEmpty) {
        result.add(row);
      }
    }

    return result;
  }

  static String _warehouseIdFromRow(Map<String, String> row) {
    final lagerId = (_read(row, const <String>['lager_id']) ?? 'schlf').trim();
    final standort = (_read(row, const <String>['standort']) ?? '00').trim();
    if (standort.isEmpty) {
      return lagerId;
    }
    return '$lagerId-$standort';
  }

  static String _warehouseNameFromRow(Map<String, String> row) {
    final lagerId = (_read(row, const <String>['lager_id']) ?? '').trim();
    final standort = (_read(row, const <String>['standort']) ?? '').trim();
    if (lagerId.isEmpty && standort.isEmpty) {
      return 'Schäflein Lager';
    }
    if (standort.isEmpty) {
      return 'Schäflein Lager ${lagerId.toUpperCase()}';
    }
    return 'Schäflein Lager $standort';
  }

  static String _locationFromRow(Map<String, String> row) {
    final standort = (_read(row, const <String>['standort']) ?? '').trim();
    return standort.isEmpty ? 'Unbekannt' : 'Standort $standort';
  }

  static DateTime? _activityDateFromRow(Map<String, String> row) {
    final snapshot = _parseDate(_read(row, const <String>['quelle_timestamp']));
    final daysSince = _toInt(_read(row, const <String>['tage_seit_bewegung']));
    if (snapshot != null && daysSince != null) {
      return snapshot.subtract(Duration(days: daysSince.clamp(0, 3650)));
    }
    return _parseDate(_read(row, const <String>['letzter_bewegungszeitpunkt']));
  }

  static int _rackNumberFromRaw(String raw, {required String fallbackSeed}) {
    final direct = _toInt(raw);
    if (direct != null && direct > 0) {
      return direct;
    }
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final parsedDigits = _toInt(digitsOnly);
    if (parsedDigits != null && parsedDigits > 0) {
      return parsedDigits;
    }
    final hash = fallbackSeed.codeUnits.fold<int>(0, (sum, code) => sum + code);
    return (hash % 90) + 1;
  }

  static int _slotFromPlaceId(String placeId) {
    final digitsOnly = placeId.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= 3) {
      final tail = digitsOnly.substring(digitsOnly.length - 3);
      final parsed = _toInt(tail);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return 1;
  }

  static String? _read(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final value = row[_normalizeKey(key)];
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  static String _normalizeKey(String key) {
    return key.trim().toLowerCase().replaceAll('\ufeff', '');
  }

  static int? _toInt(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    final direct = int.tryParse(normalized);
    if (direct != null) {
      return direct;
    }
    final asDouble = double.tryParse(normalized);
    if (asDouble != null) {
      return asDouble.round();
    }
    return null;
  }

  static double? _toDouble(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized);
  }
}

class _WarehouseAggregate {
  _WarehouseAggregate({
    required this.id,
    required this.name,
    required this.location,
  });

  final String id;
  final String name;
  final String location;

  int totalSlots = 0;
  int occupiedSlots = 0;
  final Set<String> articleIds = <String>{};
  final Map<String, _ZoneAggregate> zones = <String, _ZoneAggregate>{};
  int abcA = 0;
  int abcB = 0;
  int abcC = 0;
  double inboundPerDay = 0;
  double throughputPerDay = 0;
  double pickRatePerHour = 0;
  int blockedSlots = 0;
  double dwellMinutesSum = 0;
  int dwellMinutesCount = 0;
  double criticalitySum = 0;
  int slowMoverCount = 0;
  final Map<String, int> placeTypeCounts = <String, int>{};

  void addRow(Map<String, String> row) {
    totalSlots++;

    final occupied = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['aktueller_belegt_status']),
        ) ??
        0;
    if (occupied > 0) {
      occupiedSlots++;
    }

    final isBlocked = (WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['ist_gesperrt']),
        ) ?? 0) > 0;
    if (isBlocked) {
      blockedSlots++;
    }

    final dwellMin = WarehouseMasterParser._toDouble(
      WarehouseMasterParser._read(row, const <String>['durchlaufzeit_avg_min']),
    );
    if (dwellMin != null && dwellMin > 0) {
      dwellMinutesSum += dwellMin;
      dwellMinutesCount++;
    }

    final criticality = WarehouseMasterParser._toDouble(
      WarehouseMasterParser._read(row, const <String>['kritikalitaet_score']),
    );
    if (criticality != null) {
      criticalitySum += criticality;
    }

    final daysSinceMovement = WarehouseMasterParser._toInt(
      WarehouseMasterParser._read(row, const <String>['tage_seit_bewegung']),
    );
    if (daysSinceMovement != null && daysSinceMovement > 90) {
      slowMoverCount++;
    }

    final placeType = (WarehouseMasterParser._read(row, const <String>['platz_typ']) ?? '')
        .trim()
        .toUpperCase();
    if (placeType.isNotEmpty) {
      placeTypeCounts.update(placeType, (v) => v + 1, ifAbsent: () => 1);
    }

    final articleId = WarehouseMasterParser._read(row, const <String>['artikel_id'])?.trim() ?? '';
    if (articleId.isNotEmpty) {
      articleIds.add(articleId);
    }

    final abc = (WarehouseMasterParser._read(row, const <String>['abc_klasse']) ?? '')
        .trim()
        .toUpperCase();
    switch (abc) {
      case 'A':
        abcA++;
        break;
      case 'B':
        abcB++;
        break;
      case 'C':
        abcC++;
        break;
    }

    final moves30 = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['bewegungen_30d']),
        ) ??
        0;
    final moves6m = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['bewegungen_6mon']),
        ) ??
        0;
    final picks30 = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['picks_30d']),
        ) ??
        0;

    inboundPerDay += moves30 / 30;
    throughputPerDay += moves6m / 180;
    pickRatePerHour += picks30 / (30 * 24);

    final zoneRaw = WarehouseMasterParser._read(row, const <String>['zone'])?.trim() ?? '';
    final zoneKey = zoneRaw.isEmpty ? 'N/A' : zoneRaw;
    final zone = zones.putIfAbsent(zoneKey, () => _ZoneAggregate(zoneRaw: zoneKey));
    zone.addRow(row);
  }

  WarehouseOperationsProfile toOperationsProfile() {
    final dockCount = (zones.length + 6).clamp(4, 28);
    final activeDocks = (dockCount * 0.85).round();
    final avgDwell = dwellMinutesCount > 0
        ? (dwellMinutesSum / dwellMinutesCount).round()
        : 0;
    final avgCriticality = totalSlots > 0 ? criticalitySum / totalSlots : 0;
    // SLA: derive from criticality — lower avg criticality = better SLA
    final slaTarget = 98;
    final slaCurrent = (100 - avgCriticality * 0.3).round().clamp(80, 100);

    // Place type mapping: P = Palette/Hochregal, U = Umschlag/Bodenlager
    final pSlots = placeTypeCounts['P'] ?? 0;
    final uSlots = placeTypeCounts['U'] ?? 0;
    final otherSlots = totalSlots - pSlots - uSlots;
    // Split P-type into high-bay and block storage estimate
    final highBay = (pSlots * 0.6).round();
    final blockStorage = (pSlots * 0.4).round();
    final shuttle = (otherSlots * 0.5).round();
    final floor = uSlots + (otherSlots - shuttle).clamp(0, otherSlots);

    return WarehouseOperationsProfile(
      warehouseId: id,
      dockCount: dockCount,
      activeDocks: activeDocks,
      blockedSlots: blockedSlots,
      reservedSlots: slowMoverCount,
      slaTargetPercent: slaTarget,
      slaCurrentPercent: slaCurrent,
      avgDwellMinutes: avgDwell,
      coldZoneCount: 1,
      ambientZoneCount: (zones.length - 1).clamp(1, 50),
      hazardousZoneCount: 0,
      highBaySlots: highBay,
      blockStorageSlots: blockStorage,
      shuttleSlots: shuttle,
      floorStorageSlots: floor,
      safetyIncidentsMonth: 0,
      qualityHolds: blockedSlots,
    );
  }

  Warehouse toWarehouse() {
    final zoneList = zones.values.map((zone) => zone.toZone(id)).toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    return Warehouse(
      id: id,
      name: name,
      location: location,
      zoneCount: zoneList.length,
      status: WarehouseStatus.online,
      description: 'Automatisch aus warehouse_ai_master.csv geladen.',
      totalStorageSlots: totalSlots,
      occupiedStorageSlots: occupiedSlots.clamp(0, totalSlots),
      articleCount: articleIds.length,
      abcAnalysis: AbcAnalysis(
        aCount: abcA,
        bCount: abcB,
        cCount: abcC,
      ),
      inboundPerDay: inboundPerDay.round(),
      throughputPerDay: throughputPerDay.round(),
      pickRatePerHour: pickRatePerHour.round(),
      zones: zoneList,
    );
  }
}

class _ZoneAggregate {
  _ZoneAggregate({required this.zoneRaw});

  final String zoneRaw;
  int totalSlots = 0;
  int occupiedSlots = 0;
  final Set<String> articleIds = <String>{};
  int abcA = 0;
  int abcB = 0;
  int abcC = 0;
  double inboundPerDay = 0;
  double throughputPerDay = 0;
  double pickRatePerHour = 0;

  void addRow(Map<String, String> row) {
    totalSlots++;

    final occupied = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['aktueller_belegt_status']),
        ) ??
        0;
    if (occupied > 0) {
      occupiedSlots++;
    }

    final articleId = WarehouseMasterParser._read(row, const <String>['artikel_id'])?.trim() ?? '';
    if (articleId.isNotEmpty) {
      articleIds.add(articleId);
    }

    final abc = (WarehouseMasterParser._read(row, const <String>['abc_klasse']) ?? '')
        .trim()
        .toUpperCase();
    switch (abc) {
      case 'A':
        abcA++;
        break;
      case 'B':
        abcB++;
        break;
      case 'C':
        abcC++;
        break;
    }

    final moves30 = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['bewegungen_30d']),
        ) ??
        0;
    final moves6m = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['bewegungen_6mon']),
        ) ??
        0;
    final picks30 = WarehouseMasterParser._toInt(
          WarehouseMasterParser._read(row, const <String>['picks_30d']),
        ) ??
        0;

    inboundPerDay += moves30 / 30;
    throughputPerDay += moves6m / 180;
    pickRatePerHour += picks30 / (30 * 24);
  }

  WarehouseZone toZone(String warehouseId) {
    final normalizedName = zoneRaw.isEmpty ? 'Zone N/A' : 'Zone $zoneRaw';
    final safeId = zoneRaw.isEmpty ? 'na' : zoneRaw;
    return WarehouseZone(
      id: '$warehouseId-zone-$safeId',
      name: normalizedName,
      totalStorageSlots: totalSlots,
      occupiedStorageSlots: occupiedSlots.clamp(0, totalSlots),
      articleCount: articleIds.length,
      abcAnalysis: AbcAnalysis(aCount: abcA, bCount: abcB, cCount: abcC),
      inboundPerDay: inboundPerDay.round(),
      throughputPerDay: throughputPerDay.round(),
      pickRatePerHour: pickRatePerHour.round(),
    );
  }
}
