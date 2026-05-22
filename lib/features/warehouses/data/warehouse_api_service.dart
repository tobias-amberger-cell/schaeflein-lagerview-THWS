import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/order_volume_point.dart';
import '../../../models/pick_activity_heatmap.dart';
import '../../../models/relocation_candidate.dart';
import '../../../models/replenishment_candidate.dart';
import '../../../models/warehouse_heatmap_layer.dart';
import '../../../models/warehouse.dart';
import '../../../models/warehouse_operations_profile.dart';
import '../../../models/warehouse_trend.dart';

class WarehouseCreateRequest {
  const WarehouseCreateRequest({
    required this.name,
    required this.location,
    required this.status,
    required this.description,
    required this.lengthM,
    required this.widthM,
    required this.heightM,
    required this.rackRowCount,
    required this.rackLengthM,
    required this.rackWidthM,
    required this.rackLevels,
    required this.aisleWidthM,
    required this.zoneNames,
  });

  final String name;
  final String location;
  final WarehouseStatus status;
  final String description;
  final double lengthM;
  final double widthM;
  final double heightM;
  final int rackRowCount;
  final double rackLengthM;
  final double rackWidthM;
  final int rackLevels;
  final double aisleWidthM;
  final List<String> zoneNames;

  Map<String, Object> toJson() {
    return <String, Object>{
      'name': name,
      'location': location,
      'status': status.apiValue,
      'description': description,
      'length_m': lengthM,
      'width_m': widthM,
      'height_m': heightM,
      'rack_row_count': rackRowCount,
      'rack_length_m': rackLengthM,
      'rack_width_m': rackWidthM,
      'rack_levels': rackLevels,
      'aisle_width_m': aisleWidthM,
      'zones': zoneNames,
    };
  }
}

class WarehouseApiService {
  WarehouseApiService({
    required String baseUrl,
    http.Client? client,
  })  : _baseUrl = baseUrl,
        _client = client ?? http.Client();

  String _baseUrl;
  final http.Client _client;

  String get baseUrl => _baseUrl;

  void setBaseUrl(String value) {
    var normalized = value.trim();
    // Haengt oft versehentlich am Ende (z. B. "http://localhost:8000+").
    normalized = normalized.replaceAll(RegExp(r'[+\s]+$'), '');
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.isEmpty) {
      return;
    }
    _baseUrl = normalized;
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  // Hoch gesetzt, weil der kostenlose Render-Service nach Inaktivitaet
  // einschlaeft und beim ersten Aufruf erst hochfaehrt + die DB neu laedt
  // (~100 s). Kuerzere Timeouts wuerden den ersten Request abbrechen.
  static const Duration _requestTimeout = Duration(seconds: 180);

  Future<http.Response> _request(Future<http.Response> pending) async {
    try {
      return await pending.timeout(_requestTimeout);
    } on TimeoutException {
      throw const WarehouseApiException(
        'API nicht erreichbar (Timeout). Der kostenlose Server braucht beim '
        'ersten Aufruf bis zu 2 Minuten zum Aufwachen - bitte gleich erneut '
        'versuchen. Sonst Backend und URL pruefen.',
      );
    } on http.ClientException catch (error) {
      throw WarehouseApiException(
        'API-Verbindung fehlgeschlagen: ${error.message}. '
        'Android-Emulator: http://10.0.2.2:8000, echtes Geraet: http://<PC-IP>:8000.',
      );
    }
  }

  Future<List<Warehouse>> fetchWarehouses() async {
    final response = await _request(_client.get(_uri('/warehouses')));
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const WarehouseApiException('Ungültige Antwort für /warehouses.');
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => _toWarehouse(
            Map<String, Object?>.from(item.cast<Object?, Object?>()),
          ),
        )
        .toList(growable: false);
  }

  Future<Warehouse> fetchWarehouseById(String warehouseId) async {
    final response = await _request(_client.get(_uri('/warehouses/$warehouseId')));
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungültige Antwort für /warehouses/{id}.',
      );
    }
    return _toWarehouse(Map<String, Object?>.from(decoded.cast<Object?, Object?>()));
  }

  Future<Warehouse> createWarehouse(WarehouseCreateRequest request) async {
    final response = await _request(
      _client.post(
        _uri('/warehouses'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{201});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungültige Antwort für POST /warehouses.',
      );
    }
    return _toWarehouse(Map<String, Object?>.from(decoded.cast<Object?, Object?>()));
  }

  Future<Warehouse> updateWarehouse(
    String warehouseId,
    WarehouseCreateRequest request,
  ) async {
    final response = await _request(
      _client.put(
        _uri('/warehouses/$warehouseId'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungültige Antwort für PUT /warehouses/{id}.',
      );
    }
    return _toWarehouse(Map<String, Object?>.from(decoded.cast<Object?, Object?>()));
  }

  Future<void> deleteWarehouse(String warehouseId) async {
    final response = await _request(_client.delete(_uri('/warehouses/$warehouseId')));
    _ensureSuccess(response, expectedStatusCodes: <int>{204});
  }

  Future<Warehouse> generateModel(String warehouseId) async {
    final response = await _request(
      _client.post(_uri('/warehouses/$warehouseId/generate-model')),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungültige Antwort für POST /warehouses/{id}/generate-model.',
      );
    }
    return _toWarehouse(Map<String, Object?>.from(decoded.cast<Object?, Object?>()));
  }

  Future<WarehouseModelData?> fetchModel(String warehouseId) async {
    final response = await _request(_client.get(_uri('/warehouses/$warehouseId/model')));
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungültige Antwort für GET /warehouses/{id}/model.',
      );
    }
    final payload = Map<String, Object?>.from(decoded.cast<Object?, Object?>());
    final modelPayload = payload['model'] is Map
        ? Map<String, Object?>.from((payload['model'] as Map).cast<Object?, Object?>())
        : payload;
    if (!_looksLikeModelPayload(modelPayload)) {
      return null;
    }
    return _parseModel(modelPayload);
  }

  Future<Map<String, WarehouseOperationsProfile>> fetchOperationsProfiles() async {
    final warehouses = await fetchWarehouses();
    final result = <String, WarehouseOperationsProfile>{};
    for (final warehouse in warehouses) {
      final response =
          await _request(_client.get(_uri('/warehouses/${warehouse.id}/operations-profile')));
      _ensureSuccess(response, expectedStatusCodes: <int>{200});
      final decoded = _decodeJson(response.body);
      if (decoded is! Map) {
        throw const WarehouseApiException(
          'Ungueltige Antwort fuer /operations-profile.',
        );
      }
      final payload = Map<String, Object?>.from(decoded.cast<Object?, Object?>());
      result[warehouse.id] = WarehouseOperationsProfile(
        warehouseId: warehouse.id,
        dockCount: _toInt(payload['dock_count'], fallback: 0),
        activeDocks: _toInt(payload['active_docks'], fallback: 0),
        blockedSlots: _toInt(payload['blocked_slots'], fallback: 0),
        reservedSlots: _toInt(payload['reserved_slots'], fallback: 0),
        slaTargetPercent: _toInt(payload['sla_target_percent'], fallback: 0),
        slaCurrentPercent: _toInt(payload['sla_current_percent'], fallback: 0),
        avgDwellMinutes: _toInt(payload['avg_dwell_minutes'], fallback: 0),
        coldZoneCount: _toInt(payload['cold_zone_count'], fallback: 0),
        ambientZoneCount: _toInt(payload['ambient_zone_count'], fallback: 0),
        hazardousZoneCount: _toInt(payload['hazardous_zone_count'], fallback: 0),
        highBaySlots: _toInt(payload['high_bay_slots'], fallback: 0),
        blockStorageSlots: _toInt(payload['block_storage_slots'], fallback: 0),
        shuttleSlots: _toInt(payload['shuttle_slots'], fallback: 0),
        floorStorageSlots: _toInt(payload['floor_storage_slots'], fallback: 0),
        safetyIncidentsMonth: _toInt(payload['safety_incidents_month'], fallback: 0),
        qualityHolds: _toInt(payload['quality_holds'], fallback: 0),
      );
    }
    return result;
  }

  Future<List<WarehouseStorageLocation>> fetchStorageLocations({
    required String warehouseId,
    int limit = 120,
  }) async {
    final response = await _request(
      _client.get(_uri('/warehouses/$warehouseId/storage-locations?limit=$limit')),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const WarehouseApiException(
        'Ungueltige Antwort fuer /storage-locations.',
      );
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => Map<String, Object?>.from(item.cast<Object?, Object?>()),
        )
        .map(_toStorageLocation)
        .toList(growable: false);
  }

  Future<List<WarehouseTrendPoint>> fetchThroughputTrend({
    required String warehouseId,
    int days = 14,
  }) async {
    final response = await _request(
      _client.get(_uri('/warehouses/$warehouseId/throughput-trend?days=$days')),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const WarehouseApiException(
        'Ungueltige Antwort fuer /throughput-trend.',
      );
    }
    final points = <WarehouseTrendPoint>[];
    for (final item in decoded.whereType<Map>()) {
      final payload = Map<String, Object?>.from(item.cast<Object?, Object?>());
      final rawDate = payload['date']?.toString() ?? '';
      final parsed = DateTime.tryParse(rawDate);
      if (parsed == null) {
        continue;
      }
      points.add(
        WarehouseTrendPoint(
          date: DateTime(parsed.year, parsed.month, parsed.day),
          value: _toInt(payload['value'], fallback: 0),
        ),
      );
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  Future<List<OrderVolumePoint>> fetchOrderVolumeTrend({
    required String warehouseId,
    int days = 30,
  }) async {
    final response = await _request(
      _client.get(_uri('/warehouses/$warehouseId/order-volume-trend?days=$days')),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const WarehouseApiException(
        'Ungueltige Antwort fuer /order-volume-trend.',
      );
    }
    final points = <OrderVolumePoint>[];
    for (final item in decoded.whereType<Map>()) {
      final payload = Map<String, Object?>.from(item.cast<Object?, Object?>());
      final rawDate = payload['date']?.toString() ?? '';
      final parsed = DateTime.tryParse(rawDate);
      if (parsed == null) {
        continue;
      }
      points.add(
        OrderVolumePoint(
          date: DateTime(parsed.year, parsed.month, parsed.day),
          orders: _toInt(payload['orders'], fallback: 0),
          positions: _toInt(payload['positions'], fallback: 0),
          quantity: _toInt(payload['quantity'], fallback: 0),
        ),
      );
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  Future<PickActivityHeatmap> fetchPickActivityHeatmap({
    required String warehouseId,
  }) async {
    final response = await _request(
      _client.get(_uri('/warehouses/$warehouseId/pick-activity-heatmap')),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungueltige Antwort fuer /pick-activity-heatmap.',
      );
    }
    final payload = Map<String, Object?>.from(decoded.cast<Object?, Object?>());
    final cellsRaw = payload['cells'] is List
        ? payload['cells'] as List
        : const <Object>[];
    final cells = <PickActivityCell>[];
    for (final raw in cellsRaw.whereType<Map>()) {
      final cell = Map<String, Object?>.from(raw.cast<Object?, Object?>());
      cells.add(
        PickActivityCell(
          weekday: _toInt(cell['weekday'], fallback: 0),
          hour: _toInt(cell['hour'], fallback: 0),
          picks: _toInt(cell['picks'], fallback: 0),
        ),
      );
    }
    return PickActivityHeatmap(
      minDate: DateTime.tryParse(payload['min_date']?.toString() ?? ''),
      maxDate: DateTime.tryParse(payload['max_date']?.toString() ?? ''),
      maxPicks: _toInt(payload['max_picks'], fallback: 0),
      cells: cells,
    );
  }

  Future<List<WarehouseHeatmapLayerEntry>> fetchWarehouseHeatmapLayer({
    int limit = 500,
  }) async {
    final paths = <String>['/heatmap', '/warehouse-analytics-api/heatmap'];
    Object? lastError;
    List? decodedList;
    for (final path in paths) {
      try {
        final response = await _request(_client.get(_uri(path)));
        _ensureSuccess(response, expectedStatusCodes: <int>{200});
        final decoded = _decodeJson(response.body);
        if (decoded is List) {
          decodedList = decoded;
          break;
        }
        throw WarehouseApiException('Ungueltige Antwort fuer $path.');
      } catch (error) {
        lastError = error;
      }
    }
    if (decodedList == null) {
      throw WarehouseApiException(
        'Heatmap-Layer konnte nicht geladen werden. Letzter Fehler: $lastError',
      );
    }
    final entries = <WarehouseHeatmapLayerEntry>[];
    for (final item in decodedList.whereType<Map>()) {
      final payload = Map<String, Object?>.from(item.cast<Object?, Object?>());
      entries.add(
        WarehouseHeatmapLayerEntry(
          platzId: '${payload['PLATZ_ID'] ?? payload['platz_id'] ?? ''}'.trim(),
          regal: _toInt(payload['REGAL'] ?? payload['regal'], fallback: 0),
          fach: _toInt(payload['FACH'] ?? payload['fach'], fallback: 0),
          ebene: _toInt(payload['EBENE'] ?? payload['ebene'], fallback: 0),
          utilization: _toDouble(
            payload['UTILIZATION'] ?? payload['utilization'],
            fallback: 0,
          ),
          heatmapColor:
              '${payload['HEATMAP_COLOR'] ?? payload['heatmap_color'] ?? ''}'
                  .trim()
                  .toUpperCase(),
        ),
      );
      if (entries.length >= limit) {
        break;
      }
    }
    return entries;
  }

  Future<RelocationCandidateSummary> fetchRelocationCandidates({
    required String warehouseId,
    int limit = 12,
  }) async {
    final response = await _request(
      _client.get(
        _uri('/warehouses/$warehouseId/relocation-candidates?limit=$limit'),
      ),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungueltige Antwort fuer /relocation-candidates.',
      );
    }
    final payload = Map<String, Object?>.from(decoded.cast<Object?, Object?>());
    final summary = payload['summary'] is Map
        ? Map<String, Object?>.from(
            (payload['summary'] as Map).cast<Object?, Object?>(),
          )
        : <String, Object?>{};

    List<RelocationCandidate> parseList(Object? value) {
      if (value is! List) {
        return const <RelocationCandidate>[];
      }
      return value
          .whereType<Map>()
          .map(
            (entry) => Map<String, Object?>.from(
              entry.cast<Object?, Object?>(),
            ),
          )
          .map(_toCandidate)
          .toList(growable: false);
    }

    return RelocationCandidateSummary(
      unusedA: _toInt(summary['unused_a'], fallback: 0),
      hotC: _toInt(summary['hot_c'], fallback: 0),
      highLevelA: _toInt(summary['high_level_a'], fallback: 0),
      highPickThreshold:
          _toInt(payload['high_pick_threshold'], fallback: 100),
      highLevel: _toInt(payload['high_level'], fallback: 4),
      unusedAPlaces: parseList(payload['unused_a_places']),
      hotCPlaces: parseList(payload['hot_c_places']),
      highLevelAPlaces: parseList(payload['high_level_a_places']),
    );
  }

  RelocationCandidate _toCandidate(Map<String, Object?> payload) {
    return RelocationCandidate(
      placeId: '${payload['place_id'] ?? ''}'.trim(),
      rackNumber:
          _toInt(payload['rack_number'] ?? payload['rackNumber'], fallback: 0),
      levelNumber: _toInt(
        payload['level_number'] ?? payload['levelNumber'],
        fallback: 0,
      ),
      slotNumber: _toInt(
        payload['slot_number'] ?? payload['slotNumber'],
        fallback: 0,
      ),
      picks: _toInt(payload['picks'], fallback: 0),
      abcClass: '${payload['abc_class'] ?? payload['abcClass'] ?? 'C'}'
          .trim()
          .toUpperCase(),
      reason: '${payload['reason'] ?? ''}'.trim(),
    );
  }

  Future<ReplenishmentCandidateSummary> fetchReplenishmentCandidates({
    required String warehouseId,
    int limit = 12,
  }) async {
    final response = await _request(
      _client.get(
        _uri('/warehouses/$warehouseId/replenishment-candidates?limit=$limit'),
      ),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const WarehouseApiException(
        'Ungueltige Antwort fuer /replenishment-candidates.',
      );
    }
    final payload = Map<String, Object?>.from(decoded.cast<Object?, Object?>());
    final summary = payload['summary'] is Map
        ? Map<String, Object?>.from(
            (payload['summary'] as Map).cast<Object?, Object?>(),
          )
        : <String, Object?>{};

    List<ReplenishmentCandidate> parseList(Object? value) {
      if (value is! List) {
        return const <ReplenishmentCandidate>[];
      }
      return value
          .whereType<Map>()
          .map(
            (entry) => Map<String, Object?>.from(
              entry.cast<Object?, Object?>(),
            ),
          )
          .map(_toReplenishmentCandidate)
          .toList(growable: false);
    }

    return ReplenishmentCandidateSummary(
      urgent: _toInt(summary['urgent'], fallback: 0),
      overdue: _toInt(summary['overdue'], fallback: 0),
      medium: _toInt(summary['medium'], fallback: 0),
      pickThreshold: _toInt(payload['pick_threshold'], fallback: 50),
      mediumPickThreshold:
          _toInt(payload['medium_pick_threshold'], fallback: 20),
      overdueDays: _toInt(payload['overdue_days'], fallback: 14),
      pickLevel: _toInt(payload['pick_level'], fallback: 2),
      urgentPlaces: parseList(payload['urgent_places']),
      overduePlaces: parseList(payload['overdue_places']),
      mediumPlaces: parseList(payload['medium_places']),
    );
  }

  ReplenishmentCandidate _toReplenishmentCandidate(
    Map<String, Object?> payload,
  ) {
    return ReplenishmentCandidate(
      placeId: '${payload['place_id'] ?? ''}'.trim(),
      rackNumber:
          _toInt(payload['rack_number'] ?? payload['rackNumber'], fallback: 0),
      levelNumber: _toInt(
        payload['level_number'] ?? payload['levelNumber'],
        fallback: 0,
      ),
      slotNumber: _toInt(
        payload['slot_number'] ?? payload['slotNumber'],
        fallback: 0,
      ),
      picks: _toInt(payload['picks'], fallback: 0),
      daysEmpty: _toInt(payload['days_empty'] ?? payload['daysEmpty'], fallback: 0),
      leerDatum: '${payload['leer_datum'] ?? payload['leerDatum'] ?? ''}'.trim(),
      reason: '${payload['reason'] ?? ''}'.trim(),
    );
  }

  Future<Map<String, List<WarehouseAbcArticleSummary>>> fetchAbcArticles({
    required String warehouseId,
    int limit = 1200,
  }) async {
    final response = await _request(
      _client.get(_uri('/warehouses/$warehouseId/abc-articles?limit=$limit')),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const WarehouseApiException('Ungueltige Antwort fuer /abc-articles.');
    }
    final items = decoded
        .whereType<Map>()
        .map(
          (entry) => Map<String, Object?>.from(entry.cast<Object?, Object?>()),
        )
        .map(_toAbcSummary)
        .toList(growable: false);
    return <String, List<WarehouseAbcArticleSummary>>{
      warehouseId: items,
    };
  }

  Future<Map<String, List<WarehouseAbcSlotSummary>>> fetchAbcSlots({
    required String warehouseId,
    int limit = 10000,
  }) async {
    final response = await _request(
      _client.get(_uri('/warehouses/$warehouseId/abc-slots?limit=$limit')),
    );
    _ensureSuccess(response, expectedStatusCodes: <int>{200});
    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const WarehouseApiException('Ungueltige Antwort fuer /abc-slots.');
    }
    final items = decoded
        .whereType<Map>()
        .map(
          (entry) => Map<String, Object?>.from(entry.cast<Object?, Object?>()),
        )
        .map(_toAbcSlotSummary)
        .toList(growable: false);
    return <String, List<WarehouseAbcSlotSummary>>{
      warehouseId: items,
    };
  }

  Warehouse _toWarehouse(Map<String, Object?> payload) {
    final layoutPayload = payload['layout'] is Map
        ? Map<String, Object?>.from((payload['layout'] as Map).cast<Object?, Object?>())
        : <String, Object?>{};
    final zonePayload = payload['zones'] is List ? payload['zones'] as List : const <Object>[];
    final rawZones = zonePayload
        .whereType<Map>()
        .map((entry) => Map<String, Object?>.from(entry.cast<Object?, Object?>()))
        .toList(growable: false);

    final zoneNames = rawZones
        .map((entry) => '${entry['name'] ?? ''}'.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    final layoutSpec = WarehouseLayoutSpec(
      lengthM: _toDouble(layoutPayload['length_m'], fallback: 60),
      widthM: _toDouble(layoutPayload['width_m'], fallback: 40),
      heightM: _toDouble(layoutPayload['height_m'], fallback: 12),
      rackRowCount: _toInt(layoutPayload['rack_row_count'], fallback: 8),
      rackLengthM: _toDouble(layoutPayload['rack_length_m'], fallback: 18),
      rackWidthM: _toDouble(layoutPayload['rack_width_m'], fallback: 2.8),
      rackLevels: _toInt(layoutPayload['rack_levels'], fallback: 4),
      aisleWidthM: _toDouble(layoutPayload['aisle_width_m'], fallback: 3.2),
      zoneNames: zoneNames,
    );

    final zoneCount = zoneNames.isEmpty ? 1 : zoneNames.length;
    final metrics = _deriveMetrics(layoutSpec, zoneCount);
    final warehouseZones = _buildWarehouseZones(
      warehouseName: '${payload['name'] ?? ''}',
      zoneNames: zoneNames,
      rawZones: rawZones,
      metrics: metrics,
      warehouseId: '${payload['id'] ?? ''}',
    );
    final aggregatedTotalSlots = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.totalStorageSlots,
    );
    final aggregatedOccupiedSlots = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.occupiedStorageSlots,
    );
    final aggregatedArticles = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.articleCount,
    );
    final aggregatedInbound = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.inboundPerDay,
    );
    final aggregatedThroughput = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.throughputPerDay,
    );
    final aggregatedPickRate = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.pickRatePerHour,
    );
    final aggregatedA = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.abcAnalysis.aCount,
    );
    final aggregatedB = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.abcAnalysis.bCount,
    );
    final aggregatedC = warehouseZones.fold<int>(
      0,
      (sum, zone) => sum + zone.abcAnalysis.cCount,
    );

    WarehouseModelData? generatedModel;
    if (payload['model'] is Map) {
      generatedModel = _parseModel(
        Map<String, Object?>.from((payload['model'] as Map).cast<Object?, Object?>()),
      );
    }

    final explicitTotalSlots = _toInt(
      payload['total_storage_slots'] ?? payload['totalStorageSlots'],
      fallback: 0,
    );
    final explicitOccupiedSlots = _toInt(
      payload['occupied_storage_slots'] ?? payload['occupiedStorageSlots'],
      fallback: 0,
    );
    final explicitOverloadedSlots = _toInt(
      payload['overloaded_storage_slots'] ?? payload['overloadedStorageSlots'],
      fallback: 0,
    );
    final explicitArticleCount = _toInt(
      payload['article_count'] ?? payload['articleCount'],
      fallback: 0,
    );
    final explicitInbound = _toInt(
      payload['inbound_per_day'] ?? payload['inboundPerDay'],
      fallback: 0,
    );
    final explicitThroughput = _toInt(
      payload['throughput_per_day'] ?? payload['throughputPerDay'],
      fallback: 0,
    );
    final explicitPickRate = _toInt(
      payload['pick_rate_per_hour'] ?? payload['pickRatePerHour'],
      fallback: 0,
    );
    final explicitAbc = _parseAbcAnalysis(payload['abc_analysis']);

    return Warehouse(
      id: '${payload['id'] ?? ''}',
      name: '${payload['name'] ?? 'Lager'}',
      location: '${payload['location'] ?? '-'}',
      zoneCount: zoneCount,
      status: warehouseStatusFromApi(payload['status']?.toString()),
      description: '${payload['description'] ?? ''}',
      totalStorageSlots: explicitTotalSlots > 0
          ? explicitTotalSlots
          : (aggregatedTotalSlots > 0 ? aggregatedTotalSlots : metrics.totalSlots),
      occupiedStorageSlots: explicitOccupiedSlots > 0
          ? explicitOccupiedSlots
          : aggregatedOccupiedSlots,
      overloadedStorageSlots: explicitOverloadedSlots,
      articleCount: explicitArticleCount > 0 ? explicitArticleCount : aggregatedArticles,
      abcAnalysis: explicitAbc ??
          AbcAnalysis(
            aCount: aggregatedA,
            bCount: aggregatedB,
            cCount: aggregatedC,
          ),
      inboundPerDay: explicitInbound > 0 ? explicitInbound : aggregatedInbound,
      throughputPerDay: explicitThroughput > 0
          ? explicitThroughput
          : aggregatedThroughput,
      pickRatePerHour:
          explicitPickRate > 0 ? explicitPickRate : aggregatedPickRate,
      zones: warehouseZones,
      layoutSpec: layoutSpec,
      generatedModel: generatedModel,
    );
  }

  WarehouseStorageLocation _toStorageLocation(Map<String, Object?> payload) {
    return WarehouseStorageLocation(
      placeId: '${payload['place_id'] ?? payload['placeId'] ?? ''}'.trim(),
      area: '${payload['area'] ?? ''}',
      rackNumber: _toInt(payload['rack_number'] ?? payload['rackNumber'], fallback: 0),
      levelNumber:
          _toInt(payload['level_number'] ?? payload['levelNumber'], fallback: 0),
      slotNumber:
          _toInt(payload['slot_number'] ?? payload['slotNumber'], fallback: 0),
      abcClass: '${payload['abc_class'] ?? payload['abcClass'] ?? 'C'}'
          .trim()
          .toUpperCase(),
      status: '${payload['status'] ?? 'Frei'}',
      articleId: '${payload['article_id'] ?? payload['articleId'] ?? ''}'.trim(),
      daysSinceMovement: _toNullableInt(
        payload['days_since_movement'] ?? payload['daysSinceMovement'],
      ),
      movements30d: _toNullableInt(payload['movements_30d'] ?? payload['movements30d']),
    );
  }

  WarehouseAbcArticleSummary _toAbcSummary(Map<String, Object?> payload) {
    return WarehouseAbcArticleSummary(
      articleId: '${payload['article_id'] ?? payload['articleId'] ?? ''}'.trim(),
      articleDescription:
          '${payload['article_description'] ?? payload['articleDescription'] ?? ''}'
              .trim(),
      abcClass: '${payload['abc_class'] ?? payload['abcClass'] ?? 'C'}'
          .trim()
          .toUpperCase(),
      slotCount: _toInt(payload['slot_count'] ?? payload['slotCount'], fallback: 0),
      movements30d:
          _toInt(payload['movements_30d'] ?? payload['movements30d'], fallback: 0),
      maxIdleDays:
          _toInt(payload['max_idle_days'] ?? payload['maxIdleDays'], fallback: 0),
    );
  }

  WarehouseAbcSlotSummary _toAbcSlotSummary(Map<String, Object?> payload) {
    return WarehouseAbcSlotSummary(
      placeId: '${payload['place_id'] ?? payload['placeId'] ?? ''}'.trim(),
      halle: '${payload['halle'] ?? ''}'.trim(),
      bereich: '${payload['bereich'] ?? ''}'.trim(),
      regal: '${payload['regal'] ?? ''}'.trim(),
      fach: '${payload['fach'] ?? ''}'.trim(),
      ebene: '${payload['ebene'] ?? ''}'.trim(),
      anzPicks: _toInt(payload['anz_picks'] ?? payload['anzPicks'], fallback: 0),
      cumulativePct: _toDouble(
        payload['cumulative_pct'] ?? payload['cumulativePct'],
        fallback: 0,
      ),
      abcCalc: '${payload['abc_calc'] ?? payload['abcCalc'] ?? ''}'
          .trim()
          .toUpperCase(),
      abcClass: '${payload['abc_class'] ?? payload['abcClass'] ?? ''}'
          .trim()
          .toUpperCase(),
      articleId: '${payload['article_id'] ?? payload['articleId'] ?? ''}'.trim(),
      articleDescription:
          '${payload['article_description'] ?? payload['articleDescription'] ?? ''}'
              .trim(),
      maxLhm: _toDouble(payload['max_lhm'] ?? payload['maxLhm'], fallback: 0),
      istLhm: _toDouble(payload['ist_lhm'] ?? payload['istLhm'], fallback: 0),
      freeCapacity: _toDouble(
        payload['free_capacity'] ?? payload['freeCapacity'],
        fallback: 0,
      ),
      utilizationPct: _toDouble(
        payload['utilization_pct'] ?? payload['utilizationPct'],
        fallback: 0,
      ),
    );
  }

  AbcAnalysis? _parseAbcAnalysis(Object? value) {
    if (value is! Map) {
      return null;
    }
    final payload = Map<String, Object?>.from(value.cast<Object?, Object?>());
    final a = _toInt(payload['a_count'] ?? payload['aCount'], fallback: -1);
    final b = _toInt(payload['b_count'] ?? payload['bCount'], fallback: -1);
    final c = _toInt(payload['c_count'] ?? payload['cCount'], fallback: -1);
    if (a < 0 || b < 0 || c < 0) {
      return null;
    }
    return AbcAnalysis(aCount: a, bCount: b, cCount: c);
  }

  WarehouseModelData _parseModel(Map<String, Object?> payload) {
    final zonesPayload = payload['zones'] is List ? payload['zones'] as List : const <Object>[];
    final zones = zonesPayload
        .whereType<Map>()
        .map(
          (entry) => WarehouseModelZone(
            name: '${entry['name'] ?? 'Zone'}',
            x: _toDouble(entry['x'], fallback: 0),
            y: _toDouble(entry['y'], fallback: 0),
            width: _toDouble(entry['w'], fallback: 0.1),
            height: _toDouble(entry['h'], fallback: 0.1),
            utilization: _toNormalizedRatio(
              entry['utilization'] ?? entry['utilization_ratio'] ?? entry['utilization_percent'],
            ),
            pickRate: _toNormalizedRatio(
              entry['pick_rate'] ?? entry['pickRate'] ?? entry['pick_rate_ratio'],
            ),
            congestion: _toNormalizedRatio(
              entry['congestion'] ?? entry['congestion_ratio'] ?? entry['congestion_percent'],
            ),
            abcA: _toNormalizedRatio(
              entry['abc_a'] ?? entry['abcA'] ?? entry['a_ratio'] ?? entry['a_percent'],
            ),
          ),
        )
        .toList(growable: false);

    final generatedAtRaw = payload['generated_at']?.toString();
    final generatedAt =
        DateTime.tryParse(generatedAtRaw ?? '') ?? DateTime.now();

    return WarehouseModelData(
      generatedAt: generatedAt,
      warehouseLengthM: _toDouble(payload['warehouse_length_m'], fallback: 60),
      warehouseWidthM: _toDouble(payload['warehouse_width_m'], fallback: 40),
      warehouseHeightM: _toDouble(payload['warehouse_height_m'], fallback: 12),
      shelfRows: _toInt(payload['shelf_rows'], fallback: 6),
      shelfColumns: _toInt(payload['shelf_columns'], fallback: 8),
      shelfLevels: _toInt(payload['shelf_levels'], fallback: 4),
      zones: zones,
    );
  }

  List<WarehouseZone> _buildWarehouseZones({
    required String warehouseName,
    required List<String> zoneNames,
    required List<Map<String, Object?>> rawZones,
    required _DerivedMetrics metrics,
    required String warehouseId,
  }) {
    final names = zoneNames.isEmpty ? const <String>['Zone 1'] : zoneNames;
    final zoneCount = names.length;
    final totalPerZone = (metrics.totalSlots / zoneCount).round().clamp(1, metrics.totalSlots);
    final occupiedPerZone = (metrics.occupiedSlots / zoneCount)
        .round()
        .clamp(0, totalPerZone)
        .toInt();
    final articlesPerZone = (metrics.articleCount / zoneCount)
        .round()
        .clamp(0, metrics.articleCount)
        .toInt();

    return List<WarehouseZone>.generate(names.length, (index) {
      final rawZone = index < rawZones.length ? rawZones[index] : null;
      final rawName = '${rawZone?['name'] ?? names[index]}'.trim();
      final name = rawName.isEmpty ? 'Zone ${index + 1}' : rawName;
      final totalSlots = _toInt(
        rawZone?['total_storage_slots'] ?? rawZone?['totalSlots'],
        fallback: totalPerZone,
      ).clamp(1, 5000000).toInt();
      final occupiedSlots = _toInt(
        rawZone?['occupied_storage_slots'] ?? rawZone?['occupiedSlots'],
        fallback: occupiedPerZone,
      ).clamp(0, totalSlots).toInt();
      final articleCount = _toInt(
        rawZone?['article_count'] ?? rawZone?['articleCount'],
        fallback: articlesPerZone,
      ).clamp(0, 8000000).toInt();
      final aCount = _toInt(rawZone?['a_count'] ?? rawZone?['aCount'], fallback: -1);
      final bCount = _toInt(rawZone?['b_count'] ?? rawZone?['bCount'], fallback: -1);
      final cCount = _toInt(rawZone?['c_count'] ?? rawZone?['cCount'], fallback: -1);
      final zoneAbc = (aCount >= 0 && bCount >= 0 && cCount >= 0)
          ? (aCount, bCount, cCount)
          : _deriveAbc(articleCount);
      final inboundPerDay = _toInt(
        rawZone?['inbound_per_day'] ?? rawZone?['inboundPerDay'],
        fallback: (metrics.inboundPerDay / zoneCount).round(),
      ).clamp(0, 800000).toInt();
      final throughputPerDay = _toInt(
        rawZone?['throughput_per_day'] ?? rawZone?['throughputPerDay'],
        fallback: (metrics.throughputPerDay / zoneCount).round(),
      ).clamp(0, 800000).toInt();
      final pickRatePerHour = _toInt(
        rawZone?['pick_rate_per_hour'] ?? rawZone?['pickRatePerHour'],
        fallback: (metrics.pickRatePerHour / zoneCount).round(),
      ).clamp(0, 50000).toInt();

      return WarehouseZone(
        id: '${warehouseId.isEmpty ? warehouseName : warehouseId}-zone-$index',
        name: name,
        totalStorageSlots: totalSlots,
        occupiedStorageSlots: occupiedSlots,
        articleCount: articleCount,
        abcAnalysis: AbcAnalysis(
          aCount: zoneAbc.$1,
          bCount: zoneAbc.$2,
          cCount: zoneAbc.$3,
        ),
        inboundPerDay: inboundPerDay,
        throughputPerDay: throughputPerDay,
        pickRatePerHour: pickRatePerHour,
      );
    });
  }

  _DerivedMetrics _deriveMetrics(WarehouseLayoutSpec spec, int zoneCount) {
    final columns = (spec.lengthM / (spec.rackLengthM + spec.aisleWidthM))
        .floor()
        .clamp(1, 200)
        .toInt();
    final shelves = (spec.rackRowCount * columns).clamp(1, 10000);
    final slotsPerShelfLevel = (spec.rackLengthM / spec.rackWidthM)
        .floor()
        .clamp(1, 60)
        .toInt();
    final totalSlots = (shelves * spec.rackLevels * slotsPerShelfLevel)
        .clamp(1, 2000000)
        .toInt();
    final occupiedSlots = (totalSlots * 0.72).round().clamp(0, totalSlots).toInt();
    final articleCount = (occupiedSlots * 1.25).round().clamp(0, 3000000).toInt();
    final inbound = ((articleCount / zoneCount) * 0.06).round().clamp(0, 500000).toInt();
    final throughput = (inbound * 0.94).round().clamp(0, 500000).toInt();
    final pickRate = (throughput / 20).round().clamp(0, 20000).toInt();
    final abc = _deriveAbc(articleCount);

    return _DerivedMetrics(
      totalSlots: totalSlots,
      occupiedSlots: occupiedSlots,
      articleCount: articleCount,
      inboundPerDay: inbound,
      throughputPerDay: throughput,
      pickRatePerHour: pickRate,
      aCount: abc.$1,
      bCount: abc.$2,
      cCount: abc.$3,
    );
  }

  (int, int, int) _deriveAbc(int articleCount) {
    final a = (articleCount * 0.2).round();
    final b = (articleCount * 0.3).round();
    final c = (articleCount - a - b).clamp(0, articleCount).toInt();
    return (a, b, c);
  }

  Object? _decodeJson(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      throw const WarehouseApiException('Antwort ist kein gültiges JSON.');
    }
  }

  void _ensureSuccess(
    http.Response response, {
    required Set<int> expectedStatusCodes,
  }) {
    if (expectedStatusCodes.contains(response.statusCode)) {
      return;
    }
    String message = 'API Fehler (${response.statusCode}).';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        message = '${decoded['detail']}';
      }
    } catch (_) {
      // ignore parse errors
    }
    throw WarehouseApiException(message);
  }

  double _toDouble(Object? value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.replaceAll(',', '.').trim();
      return double.tryParse(normalized) ?? fallback;
    }
    return fallback;
  }

  int _toInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }

  int? _toNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  double? _toNormalizedRatio(Object? value) {
    final parsed = _toNullableDouble(value);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return null;
    }
    if (parsed <= 1) {
      return parsed.clamp(0, 1).toDouble();
    }
    if (parsed <= 100) {
      return (parsed / 100).clamp(0, 1).toDouble();
    }
    return 1;
  }

  double? _toNullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.replaceAll(',', '.').trim();
      return double.tryParse(normalized);
    }
    return null;
  }

  bool _looksLikeModelPayload(Map<String, Object?> payload) {
    if (payload['zones'] is List) {
      return true;
    }
    if (payload['shelf_rows'] != null ||
        payload['shelf_columns'] != null ||
        payload['shelf_levels'] != null) {
      return true;
    }
    if (payload['warehouse_length_m'] != null ||
        payload['warehouse_width_m'] != null ||
        payload['warehouse_height_m'] != null) {
      return true;
    }
    return false;
  }
}

class WarehouseApiException implements Exception {
  const WarehouseApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DerivedMetrics {
  const _DerivedMetrics({
    required this.totalSlots,
    required this.occupiedSlots,
    required this.articleCount,
    required this.inboundPerDay,
    required this.throughputPerDay,
    required this.pickRatePerHour,
    required this.aCount,
    required this.bCount,
    required this.cCount,
  });

  final int totalSlots;
  final int occupiedSlots;
  final int articleCount;
  final int inboundPerDay;
  final int throughputPerDay;
  final int pickRatePerHour;
  final int aCount;
  final int bCount;
  final int cCount;
}
