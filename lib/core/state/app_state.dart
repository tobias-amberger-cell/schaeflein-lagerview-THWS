import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../../data/warehouse_dummy_data.dart';
import '../../data/warehouse_operations_dummy_data.dart';
import '../../features/warehouses/data/warehouse_api_service.dart';
import '../../features/warehouses/data/warehouse_csv_service.dart';
import '../../models/viewer_heatmap.dart';
import '../../models/warehouse.dart';
import '../../models/warehouse_trend.dart';
import '../../models/warehouse_operations_profile.dart';

import 'control_tower_state_mixin.dart';
import 'notification_state_mixin.dart';
import 'settings_state_mixin.dart';
import 'tour_state_mixin.dart';
import 'viewer_state_mixin.dart';

export 'control_tower_state_mixin.dart';
export 'notification_state_mixin.dart';
export 'settings_state_mixin.dart' show AutoEscalationPreset, AutoEscalationPresetLabel;
export 'tour_state_mixin.dart';
export 'viewer_state_mixin.dart';

class RiskAlertAcknowledgement {
  const RiskAlertAcknowledgement({
    required this.acknowledgedAt,
    required this.warehouseId,
    required this.warehouseName,
    required this.zoneName,
    required this.metric,
    required this.score,
  });

  final DateTime acknowledgedAt;
  final String warehouseId;
  final String warehouseName;
  final String zoneName;
  final ViewerHeatmapMetric metric;
  final double score;
}

class AppState extends ChangeNotifier
    with
        SettingsStateMixin,
        NotificationStateMixin,
        TourStateMixin,
        ControlTowerStateMixin,
        ViewerStateMixin {
  static const String _csvDataDir =
      String.fromEnvironment('CSV_DATA_DIR', defaultValue: '');

  AppState() {
    initNotifications();
    initTours();
    seedControlTowerData();
  }

  // ── Auth ──────────────────────────────────────────────────────────────

  bool _isAuthenticated = false;
  String _userName = 'Warehouse Operator';
  String _userEmail = 'operator@schaeflein.de';

  bool get isAuthenticated => _isAuthenticated;
  @override
  String get userName => _userName;
  String get userEmail => _userEmail;

  Future<bool> login({required String email, required String password}) async {
    if (email.trim().isEmpty || password.trim().isEmpty) {
      return false;
    }
    _isAuthenticated = true;
    _userEmail = email.trim();
    _userName = _userEmail.split('@').first.replaceAll('.', ' ');
    notifyListeners();
    return true;
  }

  void logout() {
    _isAuthenticated = false;
    notifyListeners();
  }

  // ── Warehouse ─────────────────────────────────────────────────────────

  final List<Warehouse> _warehouses = <Warehouse>[];
  final Map<String, WarehouseOperationsProfile> _operationsProfiles =
      <String, WarehouseOperationsProfile>{...kWarehouseOperationsProfiles};
  final Set<String> _favoriteWarehouseIds = <String>{};
  final WarehouseApiService _warehouseApiService = WarehouseApiService(
    baseUrl: AppConstants.apiBaseUrl,
  );
  final WarehouseCsvService _warehouseCsvService = WarehouseCsvService(
    dataDirectory: _csvDataDir.isEmpty ? null : _csvDataDir,
  );

  String _warehouseSearchQuery = '';
  WarehouseStatus? _warehouseStatusFilter;
  Warehouse? _selectedWarehouse;
  Warehouse? _lastOpenedWarehouse;
  DateTime? _lastWarehouseSyncAt;
  bool _isWarehousesSyncing = false;
  String? _warehouseApiError;
  bool _warehouseOfflineMode = false;
  final Set<String> _modelGenerationInProgress = <String>{};
  List<WarehouseTrendPoint> _throughputTrend = <WarehouseTrendPoint>[];
  bool _hasLoadedThroughputTrend = false;

  String get warehouseSearchQuery => _warehouseSearchQuery;
  WarehouseStatus? get warehouseStatusFilter => _warehouseStatusFilter;
  Warehouse? get selectedWarehouse => _selectedWarehouse;
  Warehouse? get lastOpenedWarehouse => _lastOpenedWarehouse;
  Warehouse? get riskFocusWarehouse =>
      _selectedWarehouse ??
      _lastOpenedWarehouse ??
      (_warehouses.isEmpty ? null : _warehouses.first);
  List<Warehouse> get warehouses => List<Warehouse>.unmodifiable(_warehouses);
  List<Warehouse> get favoriteWarehouses => _warehouses
      .where((warehouse) => _favoriteWarehouseIds.contains(warehouse.id))
      .toList(growable: false);
  int get favoriteWarehouseCount => _favoriteWarehouseIds.length;
  int get availableWarehouseCount => _warehouses.length;
  DateTime? get lastWarehouseSyncAt => _lastWarehouseSyncAt;
  bool get isWarehousesSyncing => _isWarehousesSyncing;
  String? get warehouseApiError => _warehouseApiError;
  bool get isWarehouseOfflineMode => _warehouseOfflineMode;
  bool hasModelGenerationInProgress(String warehouseId) =>
      _modelGenerationInProgress.contains(warehouseId);
  bool get hasWarehouseFilters =>
      _warehouseSearchQuery.isNotEmpty || _warehouseStatusFilter != null;
  List<WarehouseTrendPoint> get throughputTrend =>
      List<WarehouseTrendPoint>.unmodifiable(_throughputTrend);

  List<Warehouse> get filteredWarehouses {
    final query = _warehouseSearchQuery.toLowerCase();
    return _warehouses.where((warehouse) {
      final matchesStatus = _warehouseStatusFilter == null ||
          warehouse.status == _warehouseStatusFilter;
      final matchesQuery = query.isEmpty ||
          warehouse.name.toLowerCase().contains(query) ||
          warehouse.location.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList(growable: false);
  }

  Warehouse? getWarehouseById(String warehouseId) {
    for (final warehouse in _warehouses) {
      if (warehouse.id == warehouseId) {
        return warehouse;
      }
    }
    return null;
  }

  WarehouseOperationsProfile getOperationsProfile(String warehouseId) {
    final fromData = _operationsProfiles[warehouseId];
    if (fromData != null) {
      return fromData;
    }
    final warehouse = getWarehouseById(warehouseId);
    if (warehouse == null) {
      return const WarehouseOperationsProfile(
        warehouseId: 'unknown',
        dockCount: 0,
        activeDocks: 0,
        blockedSlots: 0,
        reservedSlots: 0,
        slaTargetPercent: 95,
        slaCurrentPercent: 95,
        avgDwellMinutes: 0,
        coldZoneCount: 0,
        ambientZoneCount: 0,
        hazardousZoneCount: 0,
        highBaySlots: 0,
        blockStorageSlots: 0,
        shuttleSlots: 0,
        floorStorageSlots: 0,
        safetyIncidentsMonth: 0,
        qualityHolds: 0,
      );
    }
    final generated = _buildFallbackOperationsProfile(warehouse);
    _operationsProfiles[warehouseId] = generated;
    return generated;
  }

  void selectWarehouse(Warehouse warehouse) {
    _selectedWarehouse = warehouse;
    _lastOpenedWarehouse = warehouse;
    rebuildHeatmapData(warehouse);
    notifyListeners();
  }

  void setWarehouseSearchQuery(String value) {
    _warehouseSearchQuery = value;
    notifyListeners();
  }

  void setWarehouseStatusFilter(WarehouseStatus? status) {
    _warehouseStatusFilter = status;
    notifyListeners();
  }

  void clearWarehouseFilters() {
    _warehouseSearchQuery = '';
    _warehouseStatusFilter = null;
    notifyListeners();
  }

  bool isFavoriteWarehouse(String warehouseId) {
    return _favoriteWarehouseIds.contains(warehouseId);
  }

  bool toggleFavoriteWarehouse(String warehouseId) {
    if (!canToggleFavorites) {
      return false;
    }
    if (_favoriteWarehouseIds.contains(warehouseId)) {
      _favoriteWarehouseIds.remove(warehouseId);
    } else {
      _favoriteWarehouseIds.add(warehouseId);
    }
    notifyListeners();
    return true;
  }

  // ── Warehouse Sync ────────────────────────────────────────────────────

  Future<void> syncWarehouses() async {
    if (_isWarehousesSyncing) {
      return;
    }
    _isWarehousesSyncing = true;
    _hasLoadedThroughputTrend = false;
    _warehouseApiError = null;
    notifyListeners();

    List<Warehouse> next = <Warehouse>[];
    var loaded = false;
    var loadedFromCsv = false;
    try {
      if (!_warehouseOfflineMode) {
        try {
          next = await _warehouseApiService.fetchWarehouses();
          loaded = next.isNotEmpty;
          _warehouseApiError = null;
        } on WarehouseApiException catch (error) {
          _warehouseApiError = error.message;
          _warehouseOfflineMode = true;
        } catch (error) {
          _warehouseApiError = error.toString();
          _warehouseOfflineMode = true;
        }
      }

      if (!loaded) {
        try {
          final csvWarehouses =
              await _warehouseCsvService.loadWarehousesFromDisk();
          if (csvWarehouses.isNotEmpty) {
            next = csvWarehouses;
            loaded = true;
            loadedFromCsv = true;
          }
        } catch (error) {
          final prefix =
              _warehouseApiError == null ? '' : '${_warehouseApiError}\n';
          _warehouseApiError =
              '${prefix}CSV-Laden fehlgeschlagen: $error';
        }
      }

      if (!loaded) {
        next = kDummyWarehouses.toList(growable: false);
      }

      _warehouseOfflineMode =
          loadedFromCsv ? true : _warehouseOfflineMode;
      _warehouses
        ..clear()
        ..addAll(next);
      if (loadedFromCsv && next.isNotEmpty) {
        try {
          warehouseStorageLocationMap.clear();
          for (final warehouse in next) {
            final samples =
                await _warehouseCsvService.loadStorageLocationsFromDisk(
              limit: 120,
              warehouseId: warehouse.id,
            );
            if (samples.isNotEmpty) {
              warehouseStorageLocationMap[warehouse.id] = samples;
            }
          }
          if (warehouseStorageLocationMap.isEmpty) {
            final fallback = await _warehouseCsvService
                .loadStorageLocationsFromDisk(limit: 120);
            if (fallback.isNotEmpty) {
              warehouseStorageLocationMap[next.first.id] = fallback;
            }
          }
        } catch (_) {
          warehouseStorageLocationMap.clear();
        }
        try {
          final csvProfiles =
              await _warehouseCsvService.loadOperationsProfilesFromDisk();
          if (csvProfiles.isNotEmpty) {
            _operationsProfiles.addAll(csvProfiles);
          }
        } catch (_) {
          // Keep fallback profiles
        }
      } else {
        warehouseStorageLocationMap.clear();
      }
      _syncWarehouseSelections();
      _lastWarehouseSyncAt = DateTime.now();
    } finally {
      _isWarehousesSyncing = false;
      notifyListeners();
    }
  }

  Future<void> syncWarehousesFromCsv() async {
    final csvWarehouses =
        await _warehouseCsvService.loadWarehousesFromDisk();
    if (csvWarehouses.isEmpty) {
      return;
    }
    _hasLoadedThroughputTrend = false;
    _warehouses
      ..clear()
      ..addAll(csvWarehouses);
    warehouseStorageLocationMap.clear();
    for (final warehouse in csvWarehouses) {
      final samples =
          await _warehouseCsvService.loadStorageLocationsFromDisk(
        limit: 120,
        warehouseId: warehouse.id,
      );
      if (samples.isNotEmpty) {
        warehouseStorageLocationMap[warehouse.id] = samples;
      }
    }
    if (warehouseStorageLocationMap.isEmpty) {
      final fallback = await _warehouseCsvService
          .loadStorageLocationsFromDisk(limit: 120);
      if (fallback.isNotEmpty) {
        warehouseStorageLocationMap[csvWarehouses.first.id] = fallback;
      }
    }
    try {
      final csvProfiles =
          await _warehouseCsvService.loadOperationsProfilesFromDisk();
      if (csvProfiles.isNotEmpty) {
        _operationsProfiles.addAll(csvProfiles);
      }
    } catch (_) {
      // Keep fallback profiles
    }
    _warehouseOfflineMode = true;
    _syncWarehouseSelections();
    _lastWarehouseSyncAt = DateTime.now();
    notifyListeners();
  }

  Future<void> syncWarehousesFromApi() async {
    _warehouseOfflineMode = false;
    await syncWarehouses();
  }

  Future<List<WarehouseTrendPoint>> loadThroughputTrend(
      {int days = 14}) async {
    if (_hasLoadedThroughputTrend && _throughputTrend.isNotEmpty) {
      return _throughputTrend;
    }
    final trend = await _warehouseCsvService.loadThroughputTrendFromDisk(
        days: days);
    _throughputTrend = trend;
    _hasLoadedThroughputTrend = true;
    notifyListeners();
    return _throughputTrend;
  }

  Future<bool> syncWarehouseModelFromApi(
    String warehouseId, {
    bool suppressErrors = false,
    bool notify = true,
  }) async {
    try {
      final model = await _warehouseApiService.fetchModel(warehouseId);
      if (model == null) {
        return false;
      }
      final warehouse = getWarehouseById(warehouseId);
      if (warehouse == null) {
        return false;
      }
      _replaceWarehouse(warehouse.copyWith(generatedModel: model));
      return true;
    } on WarehouseApiException catch (error) {
      if (!suppressErrors) {
        _warehouseApiError = error.message;
      }
      if (notify) {
        notifyListeners();
      }
      return false;
    }
  }

  Future<bool> generateWarehouseModel(String warehouseId) async {
    if (_modelGenerationInProgress.contains(warehouseId)) {
      return false;
    }
    _modelGenerationInProgress.add(warehouseId);
    notifyListeners();

    final warehouse = getWarehouseById(warehouseId);
    if (warehouse == null) {
      _modelGenerationInProgress.remove(warehouseId);
      notifyListeners();
      return false;
    }

    try {
      if (_warehouseOfflineMode) {
        final model = _buildFallbackModel(warehouse);
        _replaceWarehouse(warehouse.copyWith(generatedModel: model));
      } else {
        final updated =
            await _warehouseApiService.generateModel(warehouseId);
        _replaceWarehouse(updated);
      }
      _warehouseApiError = null;
      return true;
    } on WarehouseApiException catch (error) {
      _warehouseApiError = error.message;
      _warehouseOfflineMode = true;
      return false;
    } catch (error) {
      _warehouseApiError = error.toString();
      _warehouseOfflineMode = true;
      return false;
    } finally {
      _modelGenerationInProgress.remove(warehouseId);
      notifyListeners();
    }
  }

  Future<bool> updateWarehouseStatus({
    required String warehouseId,
    required WarehouseStatus status,
  }) async {
    if (!canManageWarehouses) {
      return false;
    }
    final currentWarehouse = getWarehouseById(warehouseId);
    if (currentWarehouse == null) {
      return false;
    }
    if (currentWarehouse.status == status) {
      return true;
    }
    final updated = currentWarehouse.copyWith(status: status);
    _replaceWarehouse(updated);
    if (_warehouseOfflineMode) {
      return true;
    }
    try {
      await _warehouseApiService.updateWarehouse(
        warehouseId,
        _buildCreateRequest(updated),
      );
      return true;
    } on WarehouseApiException catch (error) {
      _warehouseApiError = error.message;
      return false;
    }
  }

  Future<bool> createWarehouse({
    required String name,
    required String location,
    required WarehouseStatus status,
    required String description,
    required double lengthM,
    required double widthM,
    required double heightM,
    required int rackRowCount,
    required double rackLengthM,
    required double rackWidthM,
    required int rackLevels,
    required double aisleWidthM,
    required List<String> zoneNames,
  }) async {
    if (!canManageWarehouses) {
      return false;
    }
    _warehouseApiError = null;

    final newWarehouse = _buildWarehouseFromInput(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      location: location,
      status: status,
      description: description,
      lengthM: lengthM,
      widthM: widthM,
      heightM: heightM,
      rackRowCount: rackRowCount,
      rackLengthM: rackLengthM,
      rackWidthM: rackWidthM,
      rackLevels: rackLevels,
      aisleWidthM: aisleWidthM,
      zoneNames: zoneNames,
    );

    if (_warehouseOfflineMode) {
      _warehouses.insert(0, newWarehouse);
      selectWarehouse(newWarehouse);
      notifyListeners();
      return true;
    }

    try {
      final created = await _warehouseApiService.createWarehouse(
        _buildCreateRequest(newWarehouse),
      );
      _warehouses.insert(0, created);
      selectWarehouse(created);
      notifyListeners();
      return true;
    } on WarehouseApiException catch (error) {
      _warehouseApiError = error.message;
      _warehouseOfflineMode = true;
      return false;
    }
  }

  Future<bool> updateWarehouse({
    required String warehouseId,
    required String name,
    required String location,
    required WarehouseStatus status,
    required String description,
    required double lengthM,
    required double widthM,
    required double heightM,
    required int rackRowCount,
    required double rackLengthM,
    required double rackWidthM,
    required int rackLevels,
    required double aisleWidthM,
    required List<String> zoneNames,
  }) async {
    if (!canManageWarehouses) {
      return false;
    }
    final current = getWarehouseById(warehouseId);
    if (current == null) {
      return false;
    }

    final updated = _buildWarehouseFromInput(
      id: warehouseId,
      name: name,
      location: location,
      status: status,
      description: description,
      lengthM: lengthM,
      widthM: widthM,
      heightM: heightM,
      rackRowCount: rackRowCount,
      rackLengthM: rackLengthM,
      rackWidthM: rackWidthM,
      rackLevels: rackLevels,
      aisleWidthM: aisleWidthM,
      zoneNames: zoneNames,
    ).copyWith(
      occupiedStorageSlots: current.occupiedStorageSlots,
      articleCount: current.articleCount,
      inboundPerDay: current.inboundPerDay,
      throughputPerDay: current.throughputPerDay,
      pickRatePerHour: current.pickRatePerHour,
    );

    _replaceWarehouse(updated);

    if (_warehouseOfflineMode) {
      return true;
    }

    try {
      final apiWarehouse = await _warehouseApiService.updateWarehouse(
        warehouseId,
        _buildCreateRequest(updated),
      );
      _replaceWarehouse(apiWarehouse);
      return true;
    } on WarehouseApiException catch (error) {
      _warehouseApiError = error.message;
      return false;
    }
  }

  Future<bool> deleteWarehouse(String warehouseId) async {
    if (!canManageWarehouses) {
      return false;
    }
    _warehouses.removeWhere((warehouse) => warehouse.id == warehouseId);
    _favoriteWarehouseIds.remove(warehouseId);
    if (_selectedWarehouse?.id == warehouseId) {
      _selectedWarehouse = null;
    }
    if (_lastOpenedWarehouse?.id == warehouseId) {
      _lastOpenedWarehouse = null;
    }
    _syncWarehouseSelections();
    notifyListeners();

    if (_warehouseOfflineMode) {
      return true;
    }

    try {
      await _warehouseApiService.deleteWarehouse(warehouseId);
      return true;
    } on WarehouseApiException catch (error) {
      _warehouseApiError = error.message;
      return false;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────

  void _syncWarehouseSelections() {
    if (_warehouses.isEmpty) {
      _selectedWarehouse = null;
      _lastOpenedWarehouse = null;
      viewerHeatmapItems.clear();
      return;
    }
    if (_selectedWarehouse == null) {
      _selectedWarehouse = _warehouses.first;
    }
    if (_lastOpenedWarehouse == null) {
      _lastOpenedWarehouse = _selectedWarehouse;
    }
    rebuildHeatmapData(_selectedWarehouse!);
  }

  void _replaceWarehouse(Warehouse warehouse) {
    final index =
        _warehouses.indexWhere((item) => item.id == warehouse.id);
    if (index == -1) {
      return;
    }
    _warehouses[index] = warehouse;
    if (_selectedWarehouse?.id == warehouse.id) {
      _selectedWarehouse = warehouse;
    }
    if (_lastOpenedWarehouse?.id == warehouse.id) {
      _lastOpenedWarehouse = warehouse;
    }
    rebuildHeatmapData(warehouse);
    notifyListeners();
  }

  Warehouse _buildWarehouseFromInput({
    required String id,
    required String name,
    required String location,
    required WarehouseStatus status,
    required String description,
    required double lengthM,
    required double widthM,
    required double heightM,
    required int rackRowCount,
    required double rackLengthM,
    required double rackWidthM,
    required int rackLevels,
    required double aisleWidthM,
    required List<String> zoneNames,
  }) {
    final normalizedZoneNames =
        zoneNames.where((name) => name.trim().isNotEmpty).toList();
    final zoneCount =
        normalizedZoneNames.isEmpty ? 1 : normalizedZoneNames.length;
    final totalSlots =
        (rackRowCount * rackLevels * 120).clamp(400, 40000);
    final occupiedSlots = (totalSlots * 0.72).round();
    final articleCount = (totalSlots * 3.2).round();

    final zones = List<WarehouseZone>.generate(zoneCount, (index) {
      final zoneName = normalizedZoneNames.isEmpty
          ? 'Zone ${index + 1}'
          : normalizedZoneNames[index];
      final zoneSlots = (totalSlots / zoneCount).round();
      final zoneOccupied = (zoneSlots * 0.7).round();
      return WarehouseZone(
        id: '$id-zone-${index + 1}',
        name: zoneName,
        totalStorageSlots: zoneSlots,
        occupiedStorageSlots: zoneOccupied,
        articleCount: (articleCount / zoneCount).round(),
        abcAnalysis: AbcAnalysis(
          aCount: (articleCount * 0.2 / zoneCount).round(),
          bCount: (articleCount * 0.3 / zoneCount).round(),
          cCount: (articleCount * 0.5 / zoneCount).round(),
        ),
        inboundPerDay: (700 / zoneCount).round(),
        throughputPerDay: (650 / zoneCount).round(),
        pickRatePerHour: (350 / zoneCount).round(),
      );
    });

    return Warehouse(
      id: id,
      name: name,
      location: location,
      zoneCount: zoneCount,
      status: status,
      description: description,
      totalStorageSlots: totalSlots,
      occupiedStorageSlots: occupiedSlots,
      articleCount: articleCount,
      abcAnalysis: AbcAnalysis(
        aCount: (articleCount * 0.2).round(),
        bCount: (articleCount * 0.3).round(),
        cCount: (articleCount * 0.5).round(),
      ),
      inboundPerDay: 850,
      throughputPerDay: 780,
      pickRatePerHour: 420,
      zones: zones,
      layoutSpec: WarehouseLayoutSpec(
        lengthM: lengthM,
        widthM: widthM,
        heightM: heightM,
        rackRowCount: rackRowCount,
        rackLengthM: rackLengthM,
        rackWidthM: rackWidthM,
        rackLevels: rackLevels,
        aisleWidthM: aisleWidthM,
        zoneNames: normalizedZoneNames,
      ),
    );
  }

  WarehouseCreateRequest _buildCreateRequest(Warehouse warehouse) {
    final layout = warehouse.layoutSpec;
    return WarehouseCreateRequest(
      name: warehouse.name,
      location: warehouse.location,
      status: warehouse.status,
      description: warehouse.description,
      lengthM: layout?.lengthM ?? 60,
      widthM: layout?.widthM ?? 40,
      heightM: layout?.heightM ?? 12,
      rackRowCount: layout?.rackRowCount ?? 8,
      rackLengthM: layout?.rackLengthM ?? 18,
      rackWidthM: layout?.rackWidthM ?? 2.8,
      rackLevels: layout?.rackLevels ?? 4,
      aisleWidthM: layout?.aisleWidthM ?? 3.2,
      zoneNames: layout?.zoneNames ?? <String>[],
    );
  }

  WarehouseOperationsProfile _buildFallbackOperationsProfile(
      Warehouse warehouse) {
    final dockCount = (warehouse.zoneCount + 8).clamp(4, 28);
    final activeDocks = (dockCount * 0.8).round();
    final totalSlots = warehouse.totalStorageSlots;
    final blockedSlots = (totalSlots * 0.02).round();
    final reservedSlots = (totalSlots * 0.04).round();
    return WarehouseOperationsProfile(
      warehouseId: warehouse.id,
      dockCount: dockCount,
      activeDocks: activeDocks,
      blockedSlots: blockedSlots,
      reservedSlots: reservedSlots,
      slaTargetPercent: 98,
      slaCurrentPercent: 95,
      avgDwellMinutes: 46,
      coldZoneCount: 1,
      ambientZoneCount: warehouse.zoneCount - 1,
      hazardousZoneCount: 1,
      highBaySlots: (totalSlots * 0.45).round(),
      blockStorageSlots: (totalSlots * 0.2).round(),
      shuttleSlots: (totalSlots * 0.18).round(),
      floorStorageSlots: (totalSlots * 0.17).round(),
      safetyIncidentsMonth: 1,
      qualityHolds: 6,
    );
  }

  WarehouseModelData _buildFallbackModel(Warehouse warehouse) {
    final layout = warehouse.layoutSpec;
    final length = layout?.lengthM ?? 60;
    final width = layout?.widthM ?? 40;
    final height = layout?.heightM ?? 12;
    final shelfRows = layout?.rackRowCount ?? 8;
    final shelfColumns = 8;
    final shelfLevels = layout?.rackLevels ?? 4;

    final zones = <WarehouseModelZone>[];
    final zoneCount =
        warehouse.zones.isEmpty ? 1 : warehouse.zones.length;
    final zoneWidth = width / zoneCount;
    for (var i = 0; i < zoneCount; i++) {
      final zone = warehouse.zones.isEmpty
          ? WarehouseZone(
              id: 'zone-1',
              name: 'Zone 1',
              totalStorageSlots: 1000,
              occupiedStorageSlots: 700,
              articleCount: 2200,
              abcAnalysis: const AbcAnalysis(
                  aCount: 440, bCount: 660, cCount: 1100),
              inboundPerDay: 240,
              throughputPerDay: 220,
              pickRatePerHour: 120,
            )
          : warehouse.zones[i];
      zones.add(
        WarehouseModelZone(
          name: zone.name,
          x: i * zoneWidth,
          y: 0,
          width: zoneWidth,
          height: length,
          utilization: zone.utilizationRatio,
          pickRate: (zone.pickRatePerHour / 400).clamp(0.0, 1.0),
          congestion: (zone.inboundPerDay / 500).clamp(0.0, 1.0),
          abcA: zone.abcAnalysis.aRatio,
        ),
      );
    }

    return WarehouseModelData(
      generatedAt: DateTime.now(),
      warehouseLengthM: length,
      warehouseWidthM: width,
      warehouseHeightM: height,
      shelfRows: shelfRows,
      shelfColumns: shelfColumns,
      shelfLevels: shelfLevels,
      zones: zones,
    );
  }
}
