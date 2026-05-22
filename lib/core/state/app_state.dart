import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../services/database_service.dart';
import '../../features/warehouses/data/warehouse_api_service.dart';
import '../../features/warehouses/data/warehouse_csv_service.dart';
import '../../models/order_volume_point.dart';
import '../../models/pick_activity_heatmap.dart';
import '../../models/relocation_candidate.dart';
import '../../models/replenishment_candidate.dart';
import '../../models/viewer_heatmap.dart';
import '../../models/warehouse_heatmap_layer.dart';
import '../../models/warehouse.dart';
import '../../models/warehouse_trend.dart';
import '../../models/warehouse_operations_profile.dart';

import 'notification_state_mixin.dart';
import 'settings_state_mixin.dart';

import 'viewer_state_mixin.dart';

export 'notification_state_mixin.dart';
export 'settings_state_mixin.dart' show AutoEscalationPreset, AutoEscalationPresetLabel;

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
        ViewerStateMixin {
  AppState() {
    initNotifications();
    // DB-Pfad-Auswahl pre-fuellen, damit der Dropdown im Header schon
    // selektierbar ist, bevor der erste Sync durch ist.
    _availableDatabasePaths.addAll(<String>{
      AppConstants.apiBaseUrl,
      'http://localhost:8000',
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8000',
    });
    _activeDatabasePath = _warehouseApiService.baseUrl;
  }

  // â”€â”€ Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  bool _isAuthenticated = false;
  String _userName = 'Warehouse Operator';
  String _userEmail = 'operator@schaeflein.de';

  bool get isAuthenticated => _isAuthenticated;
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

  // â”€â”€ Warehouse â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  final List<Warehouse> _warehouses = <Warehouse>[];
  final Map<String, WarehouseOperationsProfile> _operationsProfiles =
      <String, WarehouseOperationsProfile>{};
  final Set<String> _favoriteWarehouseIds = <String>{};
  final WarehouseApiService _warehouseApiService = WarehouseApiService(
    baseUrl: AppConstants.apiBaseUrl,
  );
  final WarehouseCsvService _warehouseCsvService = WarehouseCsvService();
  final DatabaseService _databaseService = createDatabaseService();

  String _warehouseSearchQuery = '';
  WarehouseStatus? _warehouseStatusFilter;
  Warehouse? _selectedWarehouse;
  Warehouse? _lastOpenedWarehouse;
  DateTime? _lastWarehouseSyncAt;
  bool _isWarehousesSyncing = false;
  String? _warehouseApiError;
  // StandardmÃ¤ÃŸig offline-first: Daten primÃ¤r aus lokaler warehouse.db laden.
  bool _warehouseOfflineMode = false;
  bool _localDatabasePrepared = false;
  String? _localDatabaseBootstrapError;
  final Set<String> _modelGenerationInProgress = <String>{};
  List<WarehouseTrendPoint> _throughputTrend = <WarehouseTrendPoint>[];
  List<OrderVolumePoint> _orderVolumeTrend = <OrderVolumePoint>[];
  PickActivityHeatmap _pickActivityHeatmap = PickActivityHeatmap.empty;
  List<WarehouseHeatmapLayerEntry> _warehouseHeatmapLayer =
      const <WarehouseHeatmapLayerEntry>[];
  RelocationCandidateSummary _relocationCandidates =
      RelocationCandidateSummary.empty;
  ReplenishmentCandidateSummary _replenishmentCandidates =
      ReplenishmentCandidateSummary.empty;
  final Map<String, List<WarehouseAbcArticleSummary>> _warehouseAbcArticlesMap =
      <String, List<WarehouseAbcArticleSummary>>{};
  final Map<String, List<WarehouseAbcSlotSummary>> _warehouseAbcSlotsMap =
      <String, List<WarehouseAbcSlotSummary>>{};
  final Map<String, String> _warehouseExternalModelPathMap =
      <String, String>{};
  final Set<String> _storageLoadInProgress = <String>{};
  bool _abcLoadInProgress = false;
  bool _abcSlotsLoadInProgress = false;
  bool _orderVolumeLoadInProgress = false;
  bool _pickActivityLoadInProgress = false;
  bool _warehouseHeatmapLayerLoadInProgress = false;
  bool _relocationLoadInProgress = false;
  bool _replenishmentLoadInProgress = false;
  final List<String> _availableDatabasePaths = <String>[];
  String? _activeDatabasePath;
  bool _hasLoadedThroughputTrend = false;
  int _loadedThroughputDays = 0;
  bool _hasLoadedOrderVolume = false;
  bool _hasLoadedPickActivity = false;
  bool _hasLoadedWarehouseHeatmapLayer = false;
  bool _hasLoadedRelocation = false;
  bool _hasLoadedReplenishment = false;
  int _dashboardKpiHorizonDays = 30;
  final Set<String> _dashboardSelectedHalls = <String>{};
  final Set<String> _dashboardSelectedAbcClasses = <String>{};
  double _dashboardUtilizationFilterMin = 0;
  double _dashboardUtilizationFilterMax = 150;
  bool _dashboardOnlyOccupied = false;
  int _dashboardTopArticlesLimit = 100;

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
  String? get localDatabaseBootstrapError => _localDatabaseBootstrapError;
  bool hasModelGenerationInProgress(String warehouseId) =>
      _modelGenerationInProgress.contains(warehouseId);
  bool get hasWarehouseFilters =>
      _warehouseSearchQuery.isNotEmpty || _warehouseStatusFilter != null;
  List<WarehouseTrendPoint> get throughputTrend =>
      List<WarehouseTrendPoint>.unmodifiable(_throughputTrend);
  List<OrderVolumePoint> get orderVolumeTrend =>
      List<OrderVolumePoint>.unmodifiable(_orderVolumeTrend);
  PickActivityHeatmap get pickActivityHeatmap => _pickActivityHeatmap;
  List<WarehouseHeatmapLayerEntry> get warehouseHeatmapLayer =>
      List<WarehouseHeatmapLayerEntry>.unmodifiable(_warehouseHeatmapLayer);
  RelocationCandidateSummary get relocationCandidates => _relocationCandidates;
  ReplenishmentCandidateSummary get replenishmentCandidates =>
      _replenishmentCandidates;
  int get dashboardKpiHorizonDays => _dashboardKpiHorizonDays;
  Set<String> get dashboardSelectedHalls =>
      Set<String>.unmodifiable(_dashboardSelectedHalls);
  Set<String> get dashboardSelectedAbcClasses =>
      Set<String>.unmodifiable(_dashboardSelectedAbcClasses);
  double get dashboardUtilizationFilterMin => _dashboardUtilizationFilterMin;
  double get dashboardUtilizationFilterMax => _dashboardUtilizationFilterMax;
  bool get dashboardOnlyOccupied => _dashboardOnlyOccupied;
  int get dashboardTopArticlesLimit => _dashboardTopArticlesLimit;
  bool get hasDashboardStorageFilters =>
      _dashboardSelectedHalls.isNotEmpty ||
      _dashboardSelectedAbcClasses.isNotEmpty ||
      _dashboardOnlyOccupied;
  bool get hasDashboardUtilizationFilter =>
      _dashboardUtilizationFilterMin > 0 || _dashboardUtilizationFilterMax < 150;
  List<String> get availableDatabasePaths =>
      List<String>.unmodifiable(_availableDatabasePaths);
  String? get activeDatabasePath => _activeDatabasePath;

  List<WarehouseAbcArticleSummary> getAbcArticlesForWarehouse(
    String warehouseId,
  ) {
    final entries = _warehouseAbcArticlesMap[warehouseId];
    if (entries == null) {
      return const <WarehouseAbcArticleSummary>[];
    }
    return List<WarehouseAbcArticleSummary>.unmodifiable(entries);
  }

  List<WarehouseAbcSlotSummary> getAbcSlotsForWarehouse(String warehouseId) {
    final entries = _warehouseAbcSlotsMap[warehouseId];
    if (entries == null) {
      return const <WarehouseAbcSlotSummary>[];
    }
    return List<WarehouseAbcSlotSummary>.unmodifiable(entries);
  }

  Future<void> ensureStorageLocationsLoadedForWarehouse(
    String warehouseId, {
    int limit = 120,
  }) async {
    if (warehouseId.trim().isEmpty) {
      return;
    }
    if (_storageLoadInProgress.contains(warehouseId)) {
      return;
    }
    final existing = warehouseStorageLocationMap[warehouseId];
    if (existing != null && existing.isNotEmpty) {
      return;
    }
    _storageLoadInProgress.add(warehouseId);
    try {
      final samples = _warehouseOfflineMode
          ? await _loadStorageLocationsFromDisk(
              warehouseId: warehouseId,
              limit: limit,
              dbPath: _activeDatabasePath,
            )
          : await _warehouseApiService.fetchStorageLocations(
              warehouseId: warehouseId,
              limit: limit,
            );
      if (samples.isNotEmpty) {
        warehouseStorageLocationMap[warehouseId] = samples;
      }
    } catch (_) {
      // no-op: UI nutzt Fallbacks, bis Daten verfuegbar sind.
    } finally {
      _storageLoadInProgress.remove(warehouseId);
      notifyListeners();
    }
  }

  Future<void> ensureAbcArticlesLoadedForWarehouse({
    required String warehouseId,
    int limit = 10000,
  }) async {
    if (warehouseId.trim().isEmpty || _abcLoadInProgress) {
      return;
    }
    final existing = _warehouseAbcArticlesMap[warehouseId];
    if (existing != null && existing.isNotEmpty) {
      return;
    }
    _abcLoadInProgress = true;
    try {
      final data = _warehouseOfflineMode
          ? await _loadAbcArticlesFromDisk(
              dbPath: _activeDatabasePath,
              limit: limit,
            )
          : await _warehouseApiService.fetchAbcArticles(
              warehouseId: warehouseId,
              limit: limit,
            );
      if (data.isNotEmpty) {
        _warehouseAbcArticlesMap
          ..clear()
          ..addAll(data);
      }
    } catch (_) {
      // no-op: Karte zeigt bis dahin Sample-basierte Fallbacks.
    } finally {
      _abcLoadInProgress = false;
      notifyListeners();
    }
  }

  Future<void> ensureAbcSlotsLoadedForWarehouse({
    required String warehouseId,
    int limit = 20000,
  }) async {
    if (warehouseId.trim().isEmpty || _abcSlotsLoadInProgress) {
      return;
    }
    final existing = _warehouseAbcSlotsMap[warehouseId];
    if (existing != null && existing.isNotEmpty) {
      return;
    }
    _abcSlotsLoadInProgress = true;
    try {
      final data = _warehouseOfflineMode
          ? await _loadAbcSlotsFromDisk(
              dbPath: _activeDatabasePath,
              limit: limit,
            )
          : await _warehouseApiService.fetchAbcSlots(
              warehouseId: warehouseId,
              limit: limit,
            );
      if (data.isNotEmpty) {
        _warehouseAbcSlotsMap
          ..clear()
          ..addAll(data);
      }
    } catch (_) {
      // no-op
    } finally {
      _abcSlotsLoadInProgress = false;
      notifyListeners();
    }
  }

  String? getExternalModelPathForWarehouse(String warehouseId) {
    return _warehouseExternalModelPathMap[warehouseId];
  }

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
    return _emptyOperationsProfile(warehouseId);
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

  void setDashboardKpiHorizonDays(int days) {
    if (days == _dashboardKpiHorizonDays) {
      return;
    }
    _dashboardKpiHorizonDays = days;
    notifyListeners();
  }

  void setDashboardSelectedHalls(Iterable<String> halls) {
    final normalized = halls
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (setEquals(normalized, _dashboardSelectedHalls)) {
      return;
    }
    _dashboardSelectedHalls
      ..clear()
      ..addAll(normalized);
    notifyListeners();
  }

  void setDashboardSelectedAbcClasses(Iterable<String> classes) {
    final normalized = classes
        .map((value) => value.trim().toUpperCase())
        .where((value) => value == 'A' || value == 'B' || value == 'C')
        .toSet();
    if (setEquals(normalized, _dashboardSelectedAbcClasses)) {
      return;
    }
    _dashboardSelectedAbcClasses
      ..clear()
      ..addAll(normalized);
    notifyListeners();
  }

  void setDashboardUtilizationFilter({
    required double min,
    required double max,
  }) {
    final nextMin = min.clamp(0.0, 150.0).toDouble();
    final nextMax = max.clamp(0.0, 150.0).toDouble();
    final safeMin = nextMin <= nextMax ? nextMin : nextMax;
    final safeMax = nextMax >= nextMin ? nextMax : nextMin;
    if (_dashboardUtilizationFilterMin == safeMin &&
        _dashboardUtilizationFilterMax == safeMax) {
      return;
    }
    _dashboardUtilizationFilterMin = safeMin;
    _dashboardUtilizationFilterMax = safeMax;
    notifyListeners();
  }

  void setDashboardOnlyOccupied(bool value) {
    if (_dashboardOnlyOccupied == value) {
      return;
    }
    _dashboardOnlyOccupied = value;
    notifyListeners();
  }

  void setDashboardTopArticlesLimit(int value) {
    final next = value.clamp(5, 100).toInt();
    if (_dashboardTopArticlesLimit == next) {
      return;
    }
    _dashboardTopArticlesLimit = next;
    notifyListeners();
  }

  Future<bool> useDatabaseFile(String dbFilePath) async {
    final nextBaseUrl = dbFilePath.trim();
    if (nextBaseUrl.isEmpty) {
      return false;
    }
    _activeDatabasePath = nextBaseUrl;
    _warehouseApiError = null;
    if (!_looksLikeDatabasePath(nextBaseUrl)) {
      _warehouseApiService.setBaseUrl(nextBaseUrl);
    }
    notifyListeners();
    await syncWarehouses(force: true);
    return _warehouses.isNotEmpty;
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

  Future<void> prepareLocalDatabaseIfNeeded() async {
    if (_localDatabasePrepared || kIsWeb) {
      return;
    }
    _localDatabasePrepared = true;
    final result = await _databaseService.ensureDatabaseReady();
    if (result.isSuccess) {
      final dbPath = result.databasePath!.trim();
      _activeDatabasePath = dbPath;
      _warehouseOfflineMode = true;
      _localDatabaseBootstrapError = null;
      if (!_availableDatabasePaths.contains(dbPath)) {
        _availableDatabasePaths.add(dbPath);
      }
      notifyListeners();
      return;
    }

    _localDatabaseBootstrapError = result.errorMessage;
    if (_localDatabaseBootstrapError != null &&
        _localDatabaseBootstrapError!.trim().isNotEmpty) {
      debugPrint(_localDatabaseBootstrapError);
    }
  }

  // â”€â”€ Warehouse Sync â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> syncWarehouses({bool force = false}) async {
    if (_isWarehousesSyncing) {
      if (!force) {
        while (_isWarehousesSyncing) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        return;
      }
      while (_isWarehousesSyncing) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
    _isWarehousesSyncing = true;
    _hasLoadedThroughputTrend = false;
    _hasLoadedOrderVolume = false;
    _hasLoadedPickActivity = false;
    _hasLoadedWarehouseHeatmapLayer = false;
    _hasLoadedRelocation = false;
    _hasLoadedReplenishment = false;
    _orderVolumeTrend = const <OrderVolumePoint>[];
    _pickActivityHeatmap = PickActivityHeatmap.empty;
    _warehouseHeatmapLayer = const <WarehouseHeatmapLayerEntry>[];
    _relocationCandidates = RelocationCandidateSummary.empty;
    _replenishmentCandidates = ReplenishmentCandidateSummary.empty;
    _warehouseApiError = null;
    notifyListeners();

    List<Warehouse> next = <Warehouse>[];
    try {
      final source = _activeDatabasePath?.trim();
      final wantsLocalDbSource = source != null &&
          source.isNotEmpty &&
          _looksLikeDatabasePath(source);
      if (source != null &&
          source.isNotEmpty &&
          _looksLikeDatabasePath(source)) {
        if (kIsWeb) {
          // Web kann keine lokale SQLite-Datei direkt lesen.
          // Statt Crash: API probieren und klare Meldung setzen.
          try {
            next = await _fetchWarehousesWithFallback();
            _warehouseApiError = null;
            _warehouseOfflineMode = false;
            _activeDatabasePath = _warehouseApiService.baseUrl;
          } catch (error) {
            next = <Warehouse>[];
            _warehouseApiError =
                'DB-only Modus ist im Web nicht direkt moeglich. Nutze eine API-URL (z. B. http://localhost:8000). Letzter API-Fehler: $error';
            _warehouseOfflineMode = false;
          }
        } else {
          next = await _loadWarehousesFromDisk(source);
          _warehouseApiError = null;
          _warehouseOfflineMode = true;
        }
      } else {
        try {
          next = await _fetchWarehousesWithFallback();
          _warehouseApiError = null;
          _warehouseOfflineMode = false;
        } catch (error) {
          if (kIsWeb) {
            next = <Warehouse>[];
            _warehouseApiError = 'API-Laden fehlgeschlagen: $error';
            _warehouseOfflineMode = false;
          } else {
            next = await _loadWarehousesFromDisk(source);
            _warehouseApiError = next.isEmpty
                ? 'API-Laden fehlgeschlagen: $error'
                : null;
            _warehouseOfflineMode = true;
          }
        }
      }
      if (kIsWeb && wantsLocalDbSource) {
        // Verhindert, dass bei Web-Session eine lokale .db als aktive Quelle stehen bleibt.
        _activeDatabasePath = _warehouseApiService.baseUrl;
      }
      unawaited(_refreshDatabaseSelectors());
      _warehouses
        ..clear()
        ..addAll(next);
      warehouseStorageLocationMap.clear();
      _warehouseAbcArticlesMap.clear();

      if (next.isNotEmpty) {
        _syncWarehouseSelections();
        _lastWarehouseSyncAt = DateTime.now();
        notifyListeners();
        unawaited(_warmupWarehouseAuxiliaryData(next));
      } else {
        _warehouseApiError ??= 'Keine API-Daten verfuegbar.';
        _operationsProfiles.clear();
        warehouseStorageLocationMap.clear();
        _warehouseAbcArticlesMap.clear();
        _warehouseExternalModelPathMap.clear();
        _activeDatabasePath = _warehouseApiService.baseUrl;
      }

      _syncWarehouseSelections();
      _lastWarehouseSyncAt = DateTime.now();
    } finally {
      _isWarehousesSyncing = false;
      notifyListeners();
    }
  }

  Future<List<Warehouse>> _fetchWarehousesWithFallback() async {
    final original = _warehouseApiService.baseUrl;
    final tried = <String>{};
    final candidates = <String>[
      original,
      if (original.contains('localhost'))
        original.replaceFirst('localhost', '127.0.0.1'),
      if (original.contains('localhost'))
        original.replaceFirst('localhost', '10.0.2.2'),
      if (original.contains('127.0.0.1'))
        original.replaceFirst('127.0.0.1', 'localhost'),
      if (original.contains('127.0.0.1'))
        original.replaceFirst('127.0.0.1', '10.0.2.2'),
      if (original.contains('10.0.2.2'))
        original.replaceFirst('10.0.2.2', 'localhost'),
      if (original.contains('10.0.2.2'))
        original.replaceFirst('10.0.2.2', '127.0.0.1'),
    ];

    Object? lastError;
    for (final raw in candidates) {
      final candidate = raw.trim();
      if (candidate.isEmpty || tried.contains(candidate)) {
        continue;
      }
      tried.add(candidate);
      _warehouseApiService.setBaseUrl(candidate);
      try {
        final data = await _warehouseApiService.fetchWarehouses();
        _activeDatabasePath = _warehouseApiService.baseUrl;
        return data;
      } catch (error) {
        lastError = error;
      }
    }

    _warehouseApiService.setBaseUrl(original);
    throw lastError ?? Exception('Keine API-Quelle erreichbar.');
  }

  Future<void> _refreshDatabaseSelectors() async {
    final currentBaseUrl = _activeDatabasePath?.trim().isNotEmpty == true
        ? _activeDatabasePath!.trim()
        : _warehouseApiService.baseUrl;
    final localDbPaths = await _warehouseCsvService.loadAvailableDatabasePathsFromDisk();
    _availableDatabasePaths
      ..clear()
      ..addAll(
        <String>{
          currentBaseUrl,
          AppConstants.apiBaseUrl,
          'http://localhost:8000',
          'http://127.0.0.1:8000',
          'http://10.0.2.2:8000',
          ...localDbPaths,
        },
      );
    _activeDatabasePath = currentBaseUrl;
    notifyListeners();
  }

  Future<void> _warmupWarehouseAuxiliaryData(
    List<Warehouse> warehouses,
  ) async {
    try {
      _warehouseAbcArticlesMap.clear();
      // Nicht mehr als gebundeltes Asset (zu gross), sondern vom GitHub-Release.
      const preferredModelPath = AppConstants.modelDownloadUrl;

      _warehouseExternalModelPathMap.clear();
      String? sharedModelPath;
      try {
        final modelPaths = await _loadExternalModelPathsFromDisk(_activeDatabasePath);
        _warehouseExternalModelPathMap.addAll(modelPaths);
        if (modelPaths.isNotEmpty) {
          sharedModelPath = modelPaths.values.first;
        }
      } catch (_) {
        // no-op: Fallback unten greift.
      }

      if (sharedModelPath != null && sharedModelPath.trim().isNotEmpty) {
        for (final warehouse in warehouses) {
          _warehouseExternalModelPathMap.putIfAbsent(
            warehouse.id,
            () => sharedModelPath!,
          );
        }
      } else if (!_warehouseOfflineMode) {
        for (final warehouse in warehouses) {
          // API-Fallback, wenn lokal keine Modellquelle gefunden wurde.
          _warehouseExternalModelPathMap[warehouse.id] =
              preferredModelPath;
        }
      }

      // Nutzerwunsch: explizit das angelieferte SampleScene-Modell verwenden.
      // Damit wird eine versehentlich priorisierte, vereinfachte GLB-Datei
      // (z. B. warehouse.model.glb) nicht mehr als Hauptquelle genutzt.
      for (final warehouse in warehouses) {
        _warehouseExternalModelPathMap[warehouse.id] = preferredModelPath;
      }

      try {
        final dbProfiles = _warehouseOfflineMode
            ? await _loadOperationsProfilesFromDisk(_activeDatabasePath)
            : await _warehouseApiService.fetchOperationsProfiles();
        _operationsProfiles
          ..clear()
          ..addAll(dbProfiles);
        for (final warehouse in warehouses) {
          _operationsProfiles.putIfAbsent(
            warehouse.id,
            () => _emptyOperationsProfile(warehouse.id),
          );
        }
      } catch (_) {
        _operationsProfiles.clear();
        for (final warehouse in warehouses) {
          _operationsProfiles[warehouse.id] =
              _emptyOperationsProfile(warehouse.id);
        }
      }

      final focusWarehouseId = riskFocusWarehouse?.id;
      if (focusWarehouseId != null && focusWarehouseId.isNotEmpty) {
        unawaited(
          ensureStorageLocationsLoadedForWarehouse(
            focusWarehouseId,
            limit: 120,
          ),
        );
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> syncWarehousesFromCsv() async {
    final localDbPath =
        _activeDatabasePath?.trim().isNotEmpty == true &&
            _looksLikeDatabasePath(_activeDatabasePath!)
        ? _activeDatabasePath!.trim()
        : await _warehouseCsvService.loadActiveDatabasePathFromDisk();
    if (localDbPath == null || localDbPath.trim().isEmpty) {
      _warehouseApiError = 'Keine lokale warehouse.db gefunden.';
      notifyListeners();
      return;
    }
    await useDatabaseFile(localDbPath);
  }

  Future<void> syncWarehousesFromApi() async {
    await syncWarehouses(force: true);
  }

  Future<List<WarehouseTrendPoint>> loadThroughputTrend(
      {int days = 14}) async {
    if (_hasLoadedThroughputTrend &&
        _loadedThroughputDays == days &&
        _throughputTrend.isNotEmpty) {
      return _throughputTrend;
    }
    final warehouse = riskFocusWarehouse;
    if (warehouse == null) {
      return const <WarehouseTrendPoint>[];
    }
    final trend = _warehouseOfflineMode
        ? await _warehouseCsvService.loadThroughputTrendFromDisk(days: days)
        : await _warehouseApiService.fetchThroughputTrend(
            warehouseId: warehouse.id,
            days: days,
          );
    _throughputTrend = trend;
    _hasLoadedThroughputTrend = true;
    _loadedThroughputDays = days;
    notifyListeners();
    return _throughputTrend;
  }

  Future<List<OrderVolumePoint>> ensureOrderVolumeTrendLoaded({
    int days = 30,
    bool force = false,
  }) async {
    // Short-Circuit auf _hasLoaded allein - sonst Endlos-Refetch bei leerer Antwort.
    if (!force && _hasLoadedOrderVolume) {
      return _orderVolumeTrend;
    }
    if (_orderVolumeLoadInProgress) {
      return _orderVolumeTrend;
    }
    final warehouse = riskFocusWarehouse;
    if (warehouse == null || _warehouseOfflineMode) {
      // Offline-Pfad fuer Auftragsdaten existiert nicht; Karte bleibt leer.
      return const <OrderVolumePoint>[];
    }
    _orderVolumeLoadInProgress = true;
    try {
      final points = await _warehouseApiService.fetchOrderVolumeTrend(
        warehouseId: warehouse.id,
        days: days,
      );
      _orderVolumeTrend = points;
      _hasLoadedOrderVolume = true;
    } catch (_) {
      // Karte zeigt bei Fehler leeren Zustand.
    } finally {
      _orderVolumeLoadInProgress = false;
      notifyListeners();
    }
    return _orderVolumeTrend;
  }

  Future<ReplenishmentCandidateSummary> ensureReplenishmentCandidatesLoaded({
    bool force = false,
    int limit = 12,
  }) async {
    if (!force && _hasLoadedReplenishment) {
      return _replenishmentCandidates;
    }
    if (_replenishmentLoadInProgress) {
      return _replenishmentCandidates;
    }
    final warehouse = riskFocusWarehouse;
    if (warehouse == null || _warehouseOfflineMode) {
      return ReplenishmentCandidateSummary.empty;
    }
    _replenishmentLoadInProgress = true;
    try {
      final summary = await _warehouseApiService.fetchReplenishmentCandidates(
        warehouseId: warehouse.id,
        limit: limit,
      );
      _replenishmentCandidates = summary;
      _hasLoadedReplenishment = true;
    } catch (_) {
      // Bei Fehler bleibt der bisherige Wert erhalten.
    } finally {
      _replenishmentLoadInProgress = false;
      notifyListeners();
    }
    return _replenishmentCandidates;
  }

  Future<RelocationCandidateSummary> ensureRelocationCandidatesLoaded({
    bool force = false,
    int limit = 12,
  }) async {
    if (!force && _hasLoadedRelocation) {
      return _relocationCandidates;
    }
    if (_relocationLoadInProgress) {
      return _relocationCandidates;
    }
    final warehouse = riskFocusWarehouse;
    if (warehouse == null || _warehouseOfflineMode) {
      return RelocationCandidateSummary.empty;
    }
    _relocationLoadInProgress = true;
    try {
      final summary = await _warehouseApiService.fetchRelocationCandidates(
        warehouseId: warehouse.id,
        limit: limit,
      );
      _relocationCandidates = summary;
      _hasLoadedRelocation = true;
    } catch (_) {
      // Bei Fehler bleibt der bisherige Wert erhalten.
    } finally {
      _relocationLoadInProgress = false;
      notifyListeners();
    }
    return _relocationCandidates;
  }

  Future<PickActivityHeatmap> ensurePickActivityHeatmapLoaded({
    bool force = false,
  }) async {
    if (!force && _hasLoadedPickActivity) {
      return _pickActivityHeatmap;
    }
    if (_pickActivityLoadInProgress) {
      return _pickActivityHeatmap;
    }
    final warehouse = riskFocusWarehouse;
    if (warehouse == null || _warehouseOfflineMode) {
      return PickActivityHeatmap.empty;
    }
    _pickActivityLoadInProgress = true;
    try {
      final heatmap = await _warehouseApiService.fetchPickActivityHeatmap(
        warehouseId: warehouse.id,
      );
      _pickActivityHeatmap = heatmap;
      _hasLoadedPickActivity = true;
    } catch (_) {
      // Bei Fehler bleibt der bisherige Wert (oder empty) erhalten.
    } finally {
      _pickActivityLoadInProgress = false;
      notifyListeners();
    }
    return _pickActivityHeatmap;
  }

  Future<List<WarehouseHeatmapLayerEntry>> ensureWarehouseHeatmapLayerLoaded({
    bool force = false,
    int limit = 500,
  }) async {
    if (!force && _hasLoadedWarehouseHeatmapLayer) {
      return _warehouseHeatmapLayer;
    }
    if (_warehouseHeatmapLayerLoadInProgress) {
      return _warehouseHeatmapLayer;
    }
    if (_warehouseOfflineMode) {
      return const <WarehouseHeatmapLayerEntry>[];
    }
    _warehouseHeatmapLayerLoadInProgress = true;
    try {
      final entries = await _warehouseApiService.fetchWarehouseHeatmapLayer(
        limit: limit,
      );
      _warehouseHeatmapLayer = entries;
      _hasLoadedWarehouseHeatmapLayer = true;
    } catch (error) {
      // Bei Fehler bleibt der bisherige Wert erhalten.
      if (kDebugMode) {
        debugPrint('Heatmap-Layer load failed: $error');
      }
    } finally {
      _warehouseHeatmapLayerLoadInProgress = false;
      notifyListeners();
    }
    return _warehouseHeatmapLayer;
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
        _warehouseApiError =
            'Model-Generierung ist ohne Backend deaktiviert. Bitte vorhandenes 3D-Modell verwenden.';
        return false;
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
    _warehouseApiError = 'API ist derzeit read-only (kein Status-Update).';
    notifyListeners();
    return false;
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
    _warehouseApiError = 'API ist derzeit read-only (kein neues Lager anlegen).';
    notifyListeners();
    return false;
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
    _warehouseApiError = 'API ist derzeit read-only (kein Lager-Update).';
    notifyListeners();
    return false;
  }

  Future<bool> deleteWarehouse(String warehouseId) async {
    if (!canManageWarehouses) {
      return false;
    }
    _warehouseApiError = 'API ist derzeit read-only (kein Lager-Loeschen).';
    notifyListeners();
    return false;
  }

  // â”€â”€ Private helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _syncWarehouseSelections() {
    if (_warehouses.isEmpty) {
      _selectedWarehouse = null;
      _lastOpenedWarehouse = null;
      viewerHeatmapItems.clear();
      return;
    }
    _selectedWarehouse ??= _warehouses.first;
    _lastOpenedWarehouse ??= _selectedWarehouse;
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

  bool _looksLikeDatabasePath(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return false;
    }
    return normalized.endsWith('.db') ||
        normalized.contains(r'\') ||
        normalized.contains('/');
  }

  Future<List<Warehouse>> _loadWarehousesFromDisk(String? dbPath) async {
    final service = (dbPath != null && dbPath.trim().isNotEmpty)
        ? WarehouseCsvService(dataDirectory: dbPath.trim())
        : _warehouseCsvService;
    List<Warehouse> data = <Warehouse>[];
    try {
      data = await service.loadWarehousesFromDisk();
    } on UnsupportedError {
      return <Warehouse>[];
    }
    if (data.isNotEmpty) {
      _activeDatabasePath =
          dbPath?.trim().isNotEmpty == true
              ? dbPath!.trim()
              : await service.loadActiveDatabasePathFromDisk();
    }
    return data;
  }

  Future<Map<String, WarehouseOperationsProfile>> _loadOperationsProfilesFromDisk(
    String? dbPath,
  ) {
    final service = (dbPath != null && dbPath.trim().isNotEmpty)
        ? WarehouseCsvService(dataDirectory: dbPath.trim())
        : _warehouseCsvService;
    return service.loadOperationsProfilesFromDisk();
  }

  Future<List<WarehouseStorageLocation>> _loadStorageLocationsFromDisk({
    required String warehouseId,
    required int limit,
    required String? dbPath,
  }) {
    final service = (dbPath != null && dbPath.trim().isNotEmpty)
        ? WarehouseCsvService(dataDirectory: dbPath.trim())
        : _warehouseCsvService;
    return service.loadStorageLocationsFromDisk(
      warehouseId: warehouseId,
      limit: limit,
    );
  }

  Future<Map<String, List<WarehouseAbcSlotSummary>>> _loadAbcSlotsFromDisk({
    required String? dbPath,
    required int limit,
  }) {
    final service = (dbPath != null && dbPath.trim().isNotEmpty)
        ? WarehouseCsvService(dataDirectory: dbPath.trim())
        : _warehouseCsvService;
    return service.loadAbcSlotsFromDisk(limit: limit);
  }

  Future<Map<String, List<WarehouseAbcArticleSummary>>> _loadAbcArticlesFromDisk({
    required String? dbPath,
    required int limit,
  }) {
    final service = (dbPath != null && dbPath.trim().isNotEmpty)
        ? WarehouseCsvService(dataDirectory: dbPath.trim())
        : _warehouseCsvService;
    return service.loadAbcArticlesFromDisk(limit: limit);
  }

  Future<Map<String, String>> _loadExternalModelPathsFromDisk(String? dbPath) {
    final service = (dbPath != null && dbPath.trim().isNotEmpty)
        ? WarehouseCsvService(dataDirectory: dbPath.trim())
        : _warehouseCsvService;
    return service.loadExternalModelPathsFromDisk();
  }

  WarehouseOperationsProfile _emptyOperationsProfile(String warehouseId) {
    return WarehouseOperationsProfile(
      warehouseId: warehouseId,
      dockCount: 0,
      activeDocks: 0,
      blockedSlots: 0,
      reservedSlots: 0,
      slaTargetPercent: 0,
      slaCurrentPercent: 0,
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

}


