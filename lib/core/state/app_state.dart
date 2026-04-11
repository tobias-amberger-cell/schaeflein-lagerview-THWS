import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../../data/tour_dummy_data.dart';
import '../../data/warehouse_dummy_data.dart';
import '../../data/warehouse_operations_dummy_data.dart';
import '../../features/warehouses/data/warehouse_api_service.dart';
import '../../features/warehouses/data/warehouse_csv_service.dart';
import '../../features/viewer/domain/viewer_type.dart';
import '../../models/app_notification_item.dart';
import '../../models/control_tower_audit_entry.dart';
import '../../models/control_tower_event.dart';
import '../../models/control_tower_ticket.dart';
import '../../models/control_tower_ticket_activity.dart';
import '../../models/tour.dart';
import '../../models/user_role.dart';
import '../../models/viewer_heatmap.dart';
import '../../models/warehouse.dart';
import '../../models/warehouse_operations_profile.dart';

enum AutoEscalationPreset {
  conservative,
  standard,
  aggressive,
  custom,
}

extension AutoEscalationPresetLabel on AutoEscalationPreset {
  String get labelKey {
    switch (this) {
      case AutoEscalationPreset.conservative:
        return 'autoEscalationPresetConservative';
      case AutoEscalationPreset.standard:
        return 'autoEscalationPresetStandard';
      case AutoEscalationPreset.aggressive:
        return 'autoEscalationPresetAggressive';
      case AutoEscalationPreset.custom:
        return 'autoEscalationPresetCustom';
    }
  }
}

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

class AppState extends ChangeNotifier {
  static const String _prefDarkMode = 'settings.dark_mode';
  static const String _prefNotificationsEnabled = 'settings.notifications_enabled';
  static const String _prefLanguageCode = 'settings.language_code';
  static const String _prefViewerType = 'settings.viewer_type';
  static const String _prefUserRole = 'settings.user_role';
  static const String _prefAutoEscFirstMinutes = 'settings.auto_escalation_first';
  static const String _prefAutoEscSecondMinutes =
      'settings.auto_escalation_second';
  static const String _prefControlTowerEventStatusFilter =
      'settings.control_tower.event_status_filter';
  static const String _prefControlTowerEventSeverityFilter =
      'settings.control_tower.event_severity_filter';
  static const String _prefControlTowerEventTimeFilter =
      'settings.control_tower.event_time_filter';
  static const String _prefControlTowerEventVisibleCount =
      'settings.control_tower.event_visible_count';
  static const String _prefControlTowerAuditVisibleCount =
      'settings.control_tower.audit_visible_count';
  static const String _prefViewerHeatmapZoneTypeFilter =
      'settings.viewer.heatmap_zone_type_filter';
  static const String _prefViewerHeatmapSeverityFilter =
      'settings.viewer.heatmap_severity_filter';
  static const String _prefViewerHeatmapLiveModeEnabled =
      'settings.viewer.heatmap_live_mode_enabled';
  static const String _prefViewerHeatmapAutoFocusEnabled =
      'settings.viewer.heatmap_auto_focus_enabled';
  static const String _prefStorageFilterQuery = 'viewer.storage.filter_query';
  static const String _prefStorageSortByAbc = 'viewer.storage.sort_abc';
  static const String _prefStorageVisibleCount = 'viewer.storage.visible_count';
  static const String _prefSettingsLastSavedAt = 'settings.last_saved_at';

  static const String _csvDataDir =
      String.fromEnvironment('CSV_DATA_DIR', defaultValue: '');

  AppState() {
    _notifications.addAll(_defaultNotifications());
    _tours.addAll(buildDummyTours(DateTime.now()));
    _seedControlTowerData();
  }

  bool _isAuthenticated = false;
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;
  String _languageCode = 'de';
  ViewerType _viewerType = ViewerType.nativePlaceholder;
  UserRole _userRole = UserRole.operator;
  String _warehouseSearchQuery = '';
  WarehouseStatus? _warehouseStatusFilter;
  bool _viewerZonesVisible = false;
  bool _viewerTourRunning = false;
  bool _viewerHeatmapVisible = false;
  String? _viewerFocusZoneName;
  int _viewerFocusRequestId = 0;
  int _viewerFocusRackNumber = 1;
  int _viewerFocusLevelNumber = 1;
  int _viewerFocusSlotNumber = 1;
  int _viewerFocusLocationRequestId = 0;
  int _viewerResetCount = 0;
  int _autoEscalationFirstStepMinutes = 0;
  int _autoEscalationSecondStepMinutes = 30;
  ViewerHeatmapMetric _viewerHeatmapMetric = ViewerHeatmapMetric.utilization;
  String _tourSearchQuery = '';
  TourStatus? _tourStatusFilter;
  String _controlTowerEventStatusFilter = 'open';
  String _controlTowerEventSeverityFilter = 'all';
  String _controlTowerEventTimeFilter = 'last24Hours';
  int _controlTowerEventVisibleCount = 10;
  int _controlTowerAuditVisibleCount = 8;
  String _viewerHeatmapZoneTypeFilter = 'all';
  String _viewerHeatmapSeverityFilter = 'all';
  bool _viewerHeatmapLiveModeEnabled = !kIsWeb;
  bool _viewerHeatmapAutoFocusEnabled = false;
  String _storageFilterQuery = '';
  bool _storageSortByAbc = true;
  int _storageVisibleSampleCount = 12;

  Warehouse? _selectedWarehouse;
  Warehouse? _lastOpenedWarehouse;

  final List<Warehouse> _warehouses = <Warehouse>[];
  final List<TransportTour> _tours = <TransportTour>[];
  final Map<String, WarehouseOperationsProfile> _operationsProfiles =
      <String, WarehouseOperationsProfile>{...kWarehouseOperationsProfiles};
  final Set<String> _favoriteWarehouseIds = <String>{};
  final List<AppNotificationItem> _notifications = <AppNotificationItem>[];
  final List<ControlTowerEvent> _controlTowerEvents = <ControlTowerEvent>[];
  final List<ControlTowerTicket> _controlTowerTickets = <ControlTowerTicket>[];
  final Map<String, List<ControlTowerTicketActivity>> _controlTowerTicketActivities =
      <String, List<ControlTowerTicketActivity>>{};
  final List<ControlTowerAuditEntry> _controlTowerAuditLog =
      <ControlTowerAuditEntry>[];
  final Set<String> _acknowledgedControlTowerEventIds = <String>{};
  final Set<String> _escalatedControlTowerEventIds = <String>{};
  final List<ViewerHeatmapEntry> _viewerHeatmapData = <ViewerHeatmapEntry>[];
  final Random _random = Random();
  final WarehouseApiService _warehouseApiService = WarehouseApiService(
    baseUrl: AppConstants.apiBaseUrl,
  );
  final WarehouseCsvService _warehouseCsvService = WarehouseCsvService(
    dataDirectory: _csvDataDir.isEmpty ? null : _csvDataDir,
  );
  final Map<String, List<WarehouseStorageLocation>> _warehouseStorageLocations =
      <String, List<WarehouseStorageLocation>>{};
  WarehouseStorageLocation? _selectedStorageLocation;

  DateTime? _lastWarehouseSyncAt;
  bool _hasLoadedPersistedSettings = false;
  bool _isWarehousesSyncing = false;
  String? _warehouseApiError;
  bool _warehouseOfflineMode = false;
  final Set<String> _modelGenerationInProgress = <String>{};
  DateTime? _settingsLastSavedAt;
  DateTime? _lastControlTowerHeartbeat;
  bool _controlTowerFeedActive = true;
  DateTime? _autoEscalationAlertAcknowledgedAt;

  String _userName = 'Warehouse Operator';
  String _userEmail = 'operator@schaeflein.de';

  SharedPreferences? _prefs;

  bool get isAuthenticated => _isAuthenticated;
  bool get isDarkMode => _isDarkMode;
  bool get notificationsEnabled => _notificationsEnabled;
  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);
  ViewerType get viewerType => _viewerType;
  UserRole get userRole => _userRole;
  String get userRoleLabelKey => _userRole.labelKey;
  String get warehouseSearchQuery => _warehouseSearchQuery;
  WarehouseStatus? get warehouseStatusFilter => _warehouseStatusFilter;
  bool get viewerZonesVisible => _viewerZonesVisible;
  bool get viewerTourRunning => _viewerTourRunning;
  bool get viewerHeatmapVisible => _viewerHeatmapVisible;
  String? get viewerFocusZoneName => _viewerFocusZoneName;
  int get viewerFocusRequestId => _viewerFocusRequestId;
  int get viewerFocusRackNumber => _viewerFocusRackNumber;
  int get viewerFocusLevelNumber => _viewerFocusLevelNumber;
  int get viewerFocusSlotNumber => _viewerFocusSlotNumber;
  int get viewerFocusLocationRequestId => _viewerFocusLocationRequestId;
  int get viewerResetCount => _viewerResetCount;
  int get autoEscalationFirstStepMinutes => _autoEscalationFirstStepMinutes;
  int get autoEscalationSecondStepMinutes => _autoEscalationSecondStepMinutes;
  DateTime? get settingsLastSavedAt => _settingsLastSavedAt;
  DateTime? get lastWarehouseSyncAt => _lastWarehouseSyncAt;
  bool get hasLoadedPersistedSettings => _hasLoadedPersistedSettings;
  bool get isWarehousesSyncing => _isWarehousesSyncing;
  String? get warehouseApiError => _warehouseApiError;
  bool get isWarehouseOfflineMode => _warehouseOfflineMode;
  bool hasModelGenerationInProgress(String warehouseId) =>
      _modelGenerationInProgress.contains(warehouseId);
  ViewerHeatmapMetric get viewerHeatmapMetric => _viewerHeatmapMetric;
  String get tourSearchQuery => _tourSearchQuery;
  TourStatus? get tourStatusFilter => _tourStatusFilter;
  String get controlTowerEventStatusFilter => _controlTowerEventStatusFilter;
  String get controlTowerEventSeverityFilter => _controlTowerEventSeverityFilter;
  String get controlTowerEventTimeFilter => _controlTowerEventTimeFilter;
  int get controlTowerEventVisibleCount => _controlTowerEventVisibleCount;
  int get controlTowerAuditVisibleCount => _controlTowerAuditVisibleCount;
  String get viewerHeatmapZoneTypeFilter => _viewerHeatmapZoneTypeFilter;
  String get viewerHeatmapSeverityFilter => _viewerHeatmapSeverityFilter;
  bool get viewerHeatmapLiveModeEnabled => _viewerHeatmapLiveModeEnabled;
  bool get viewerHeatmapAutoFocusEnabled => _viewerHeatmapAutoFocusEnabled;
  String get storageFilterQuery => _storageFilterQuery;
  bool get storageSortByAbc => _storageSortByAbc;
  int get storageVisibleSampleCount => _storageVisibleSampleCount;
  Warehouse? get selectedWarehouse => _selectedWarehouse;
  Warehouse? get lastOpenedWarehouse => _lastOpenedWarehouse;
  Warehouse? get riskFocusWarehouse =>
      _selectedWarehouse ?? _lastOpenedWarehouse ?? (_warehouses.isEmpty ? null : _warehouses.first);
  List<Warehouse> get warehouses => List<Warehouse>.unmodifiable(_warehouses);
  List<TransportTour> get tours => List<TransportTour>.unmodifiable(_tours);
  List<Warehouse> get favoriteWarehouses => _warehouses
      .where((warehouse) => _favoriteWarehouseIds.contains(warehouse.id))
      .toList(growable: false);
  int get favoriteWarehouseCount => _favoriteWarehouseIds.length;
  int get availableWarehouseCount => _warehouses.length;
  List<AppNotificationItem> get notifications =>
      List<AppNotificationItem>.unmodifiable(_notifications);
  int get unreadNotificationCount =>
      _notifications.where((item) => !item.isRead).length;
  bool get canUseViewerControls => _userRole != UserRole.viewer;
  bool get canToggleFavorites => _userRole != UserRole.viewer;
  bool get canManageWarehouses => _userRole != UserRole.viewer;
  bool get canExportReports => _userRole != UserRole.viewer;
  bool get canAccessControlTower => _userRole != UserRole.viewer;
  bool get canAcknowledgeControlTowerEvents => _userRole != UserRole.viewer;
  bool get canEscalateControlTowerEvents => _userRole != UserRole.viewer;
  bool get isControlTowerFeedActive => _controlTowerFeedActive;
  DateTime? get lastControlTowerHeartbeat => _lastControlTowerHeartbeat;
  bool get hasWarehouseFilters =>
      _warehouseSearchQuery.isNotEmpty || _warehouseStatusFilter != null;
  bool get hasTourFilters =>
      _tourSearchQuery.isNotEmpty || _tourStatusFilter != null;
  String get userName => _userName;
  String get userEmail => _userEmail;
  List<ViewerHeatmapEntry> get viewerHeatmapData =>
      List<ViewerHeatmapEntry>.unmodifiable(_viewerHeatmapData);

  List<WarehouseStorageLocation> getStorageLocationsForWarehouse(String warehouseId) {
    return _warehouseStorageLocations[warehouseId] ?? const <WarehouseStorageLocation>[];
  }

  WarehouseStorageLocation? get selectedStorageLocation => _selectedStorageLocation;

  String? get topRiskZoneName {
    if (_viewerHeatmapData.isEmpty) {
      return null;
    }
    final sorted = List<ViewerHeatmapEntry>.from(_viewerHeatmapData)
      ..sort((a, b) => b.utilization.compareTo(a.utilization));
    return sorted.first.zoneName;
  }

  double get topRiskScore {
    if (_viewerHeatmapData.isEmpty) {
      return 0.0;
    }
    var maxValue = 0.0;
    for (final entry in _viewerHeatmapData) {
      final value = entry.valueFor(_viewerHeatmapMetric);
      if (value > maxValue) {
        maxValue = value;
      }
    }
    return maxValue.clamp(0.0, 1.0);
  }

  bool get hasCriticalTopRisk => topRiskScore >= 0.85;

  int get criticalControlTowerTicketCount => _controlTowerTickets
      .where((ticket) =>
          ticket.severity == ControlTowerEventSeverity.critical &&
          !ticket.isResolved)
      .length;

  AutoEscalationPreset get autoEscalationPreset {
    if (_autoEscalationFirstStepMinutes == 15 &&
        _autoEscalationSecondStepMinutes == 60) {
      return AutoEscalationPreset.conservative;
    }
    if (_autoEscalationFirstStepMinutes == 0 &&
        _autoEscalationSecondStepMinutes == 30) {
      return AutoEscalationPreset.standard;
    }
    if (_autoEscalationFirstStepMinutes == 0 &&
        _autoEscalationSecondStepMinutes == 10) {
      return AutoEscalationPreset.aggressive;
    }
    return AutoEscalationPreset.custom;
  }

  List<Warehouse> get filteredWarehouses {
    final query = _warehouseSearchQuery.toLowerCase();
    return _warehouses.where((warehouse) {
      final matchesStatus =
          _warehouseStatusFilter == null || warehouse.status == _warehouseStatusFilter;
      final matchesQuery = query.isEmpty ||
          warehouse.name.toLowerCase().contains(query) ||
          warehouse.location.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList(growable: false);
  }

  List<TransportTour> get filteredTours {
    final query = _tourSearchQuery.toLowerCase();
    return _tours.where((tour) {
      final matchesStatus = _tourStatusFilter == null || tour.status == _tourStatusFilter;
      final matchesQuery = query.isEmpty ||
          tour.code.toLowerCase().contains(query) ||
          tour.driverName.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList(growable: false);
  }

  int get activeToursCount => _tours
      .where((tour) =>
          tour.status == TourStatus.inTransit || tour.status == TourStatus.loading)
      .length;

  int get delayedToursCount =>
      _tours.where((tour) => tour.status == TourStatus.delayed).length;

  int get completedToursCount =>
      _tours.where((tour) => tour.status == TourStatus.completed).length;

  List<ControlTowerEvent> get controlTowerEvents =>
      List<ControlTowerEvent>.unmodifiable(_controlTowerEvents);

  List<ControlTowerTicket> get controlTowerTickets =>
      List<ControlTowerTicket>.unmodifiable(_controlTowerTickets);

  List<ControlTowerAuditEntry> get controlTowerAuditLog =>
      List<ControlTowerAuditEntry>.unmodifiable(_controlTowerAuditLog);

  int get openControlTowerTicketCount => _controlTowerTickets
      .where((ticket) => ticket.status == ControlTowerTicketStatus.open)
      .length;

  int get overdueControlTowerTicketCount {
    final now = DateTime.now();
    return _controlTowerTickets
        .where((ticket) => ticket.isSlaBreachedAt(now))
        .length;
  }

  int get escalatedControlTowerEventCount => _escalatedControlTowerEventIds.length;

  int get pendingAutoEscalationAlertCount => _controlTowerTickets
      .where((ticket) => ticket.severity == ControlTowerEventSeverity.critical)
      .length;

  int get automaticEscalatedTicketCountLastHour => _controlTowerTickets.where(
        (ticket) =>
            DateTime.now().difference(ticket.createdAt).inMinutes < 60 &&
            ticket.escalationLevel == ControlTowerTicketEscalationLevel.level3,
      ).length;
  Future<void> loadPersistedSettings() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs?.getBool(_prefDarkMode) ?? _isDarkMode;
    _notificationsEnabled =
        _prefs?.getBool(_prefNotificationsEnabled) ?? _notificationsEnabled;
    _languageCode = _prefs?.getString(_prefLanguageCode) ?? _languageCode;
    _viewerType = _viewerTypeFromRaw(_prefs?.getString(_prefViewerType));
    _userRole = _userRoleFromRaw(_prefs?.getString(_prefUserRole));
    _autoEscalationFirstStepMinutes =
        _prefs?.getInt(_prefAutoEscFirstMinutes) ?? _autoEscalationFirstStepMinutes;
    _autoEscalationSecondStepMinutes =
        _prefs?.getInt(_prefAutoEscSecondMinutes) ?? _autoEscalationSecondStepMinutes;
    _controlTowerEventStatusFilter =
        _prefs?.getString(_prefControlTowerEventStatusFilter) ?? _controlTowerEventStatusFilter;
    _controlTowerEventSeverityFilter =
        _prefs?.getString(_prefControlTowerEventSeverityFilter) ?? _controlTowerEventSeverityFilter;
    _controlTowerEventTimeFilter =
        _prefs?.getString(_prefControlTowerEventTimeFilter) ?? _controlTowerEventTimeFilter;
    _controlTowerEventVisibleCount =
        _prefs?.getInt(_prefControlTowerEventVisibleCount) ?? _controlTowerEventVisibleCount;
    _controlTowerAuditVisibleCount =
        _prefs?.getInt(_prefControlTowerAuditVisibleCount) ?? _controlTowerAuditVisibleCount;
    _viewerHeatmapZoneTypeFilter =
        _prefs?.getString(_prefViewerHeatmapZoneTypeFilter) ?? _viewerHeatmapZoneTypeFilter;
    _viewerHeatmapSeverityFilter =
        _prefs?.getString(_prefViewerHeatmapSeverityFilter) ?? _viewerHeatmapSeverityFilter;
    _viewerHeatmapLiveModeEnabled =
        _prefs?.getBool(_prefViewerHeatmapLiveModeEnabled) ?? _viewerHeatmapLiveModeEnabled;
    _viewerHeatmapAutoFocusEnabled =
        _prefs?.getBool(_prefViewerHeatmapAutoFocusEnabled) ?? _viewerHeatmapAutoFocusEnabled;
    _storageFilterQuery =
        _prefs?.getString(_prefStorageFilterQuery) ?? _storageFilterQuery;
    _storageSortByAbc =
        _prefs?.getBool(_prefStorageSortByAbc) ?? _storageSortByAbc;
    _storageVisibleSampleCount =
        _prefs?.getInt(_prefStorageVisibleCount) ?? _storageVisibleSampleCount;
    final lastSavedRaw = _prefs?.getString(_prefSettingsLastSavedAt);
    if (lastSavedRaw != null) {
      _settingsLastSavedAt = DateTime.tryParse(lastSavedRaw);
    }
    _hasLoadedPersistedSettings = true;
    notifyListeners();
  }

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

  Future<void> syncWarehouses() async {
    if (_isWarehousesSyncing) {
      return;
    }
    _isWarehousesSyncing = true;
    _warehouseApiError = null;
    notifyListeners();

    List<Warehouse> next = <Warehouse>[];
    var loaded = false;
    var loadedFromCsv = false;

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
      final csvWarehouses = await _warehouseCsvService.loadWarehousesFromDisk();
      if (csvWarehouses.isNotEmpty) {
        next = csvWarehouses;
        loaded = true;
        loadedFromCsv = true;
      }
    }

    if (!loaded) {
      next = kDummyWarehouses.toList(growable: false);
    }

    _warehouseOfflineMode = loadedFromCsv ? true : _warehouseOfflineMode;
    _warehouses
      ..clear()
      ..addAll(next);
    if (loadedFromCsv && next.isNotEmpty) {
      final samples = await _warehouseCsvService.loadStorageLocationsFromDisk(limit: 120);
      _warehouseStorageLocations
        ..clear()
        ..[next.first.id] = samples;
    } else {
      _warehouseStorageLocations.clear();
    }
    _syncWarehouseSelections();
    _lastWarehouseSyncAt = DateTime.now();
    _isWarehousesSyncing = false;
    notifyListeners();
  }

  Future<void> syncWarehousesFromCsv() async {
    final csvWarehouses = await _warehouseCsvService.loadWarehousesFromDisk();
    if (csvWarehouses.isEmpty) {
      return;
    }
    _warehouses
      ..clear()
      ..addAll(csvWarehouses);
    final samples = await _warehouseCsvService.loadStorageLocationsFromDisk(limit: 120);
    _warehouseStorageLocations
      ..clear()
      ..[csvWarehouses.first.id] = samples;
    _warehouseOfflineMode = true;
    _syncWarehouseSelections();
    _lastWarehouseSyncAt = DateTime.now();
    notifyListeners();
  }

  Future<void> syncWarehousesFromApi() async {
    _warehouseOfflineMode = false;
    await syncWarehouses();
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
        final updated = await _warehouseApiService.generateModel(warehouseId);
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
  Warehouse? getWarehouseById(String warehouseId) {
    for (final warehouse in _warehouses) {
      if (warehouse.id == warehouseId) {
        return warehouse;
      }
    }
    return null;
  }

  TransportTour? getTourById(String tourId) {
    for (final tour in _tours) {
      if (tour.id == tourId) {
        return tour;
      }
    }
    return null;
  }

  List<TransportTour> getToursByWarehouse(String warehouseId) {
    return _tours
        .where((tour) => tour.warehouseId == warehouseId)
        .toList(growable: false);
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

  void selectWarehouse(Warehouse warehouse) {
    _selectedWarehouse = warehouse;
    _lastOpenedWarehouse = warehouse;
    _rebuildHeatmapData(warehouse);
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

  void setTourSearchQuery(String value) {
    _tourSearchQuery = value;
    notifyListeners();
  }

  void setTourStatusFilter(TourStatus? status) {
    _tourStatusFilter = status;
    notifyListeners();
  }

  void clearTourFilters() {
    _tourSearchQuery = '';
    _tourStatusFilter = null;
    notifyListeners();
  }
  void setDarkMode(bool value) {
    _isDarkMode = value;
    _prefs?.setBool(_prefDarkMode, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _prefs?.setBool(_prefNotificationsEnabled, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setLanguageCode(String value) {
    _languageCode = value;
    _prefs?.setString(_prefLanguageCode, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setViewerType(ViewerType value) {
    _viewerType = value;
    _prefs?.setString(_prefViewerType, value.name);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setUserRole(UserRole value) {
    _userRole = value;
    _prefs?.setString(_prefUserRole, value.name);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setAutoEscalationPreset(AutoEscalationPreset preset) {
    switch (preset) {
      case AutoEscalationPreset.conservative:
        _autoEscalationFirstStepMinutes = 15;
        _autoEscalationSecondStepMinutes = 60;
      case AutoEscalationPreset.standard:
        _autoEscalationFirstStepMinutes = 0;
        _autoEscalationSecondStepMinutes = 30;
      case AutoEscalationPreset.aggressive:
        _autoEscalationFirstStepMinutes = 0;
        _autoEscalationSecondStepMinutes = 10;
      case AutoEscalationPreset.custom:
        return;
    }
    _persistAutoEscalation();
  }

  void resetAutoEscalationRules() {
    _autoEscalationFirstStepMinutes = 0;
    _autoEscalationSecondStepMinutes = 30;
    _persistAutoEscalation();
  }

  void setAutoEscalationFirstStepMinutes(int value) {
    _autoEscalationFirstStepMinutes = value.clamp(0, 120).toInt();
    _persistAutoEscalation();
  }

  void setAutoEscalationSecondStepMinutes(int value) {
    _autoEscalationSecondStepMinutes = value.clamp(0, 240).toInt();
    _persistAutoEscalation();
  }

  void _persistAutoEscalation() {
    _prefs?.setInt(_prefAutoEscFirstMinutes, _autoEscalationFirstStepMinutes);
    _prefs?.setInt(_prefAutoEscSecondMinutes, _autoEscalationSecondStepMinutes);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setViewerZonesVisible(bool value) {
    _viewerZonesVisible = value;
    notifyListeners();
  }

  void setViewerTourRunning(bool value) {
    _viewerTourRunning = value;
    notifyListeners();
  }

  void setViewerHeatmapVisible(bool value) {
    _viewerHeatmapVisible = value;
    notifyListeners();
  }

  void setViewerHeatmapMetric(ViewerHeatmapMetric metric) {
    _viewerHeatmapMetric = metric;
    notifyListeners();
  }

  void setViewerHeatmapZoneTypeFilter(String value) {
    _viewerHeatmapZoneTypeFilter = value;
    _prefs?.setString(_prefViewerHeatmapZoneTypeFilter, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setViewerHeatmapSeverityFilter(String value) {
    _viewerHeatmapSeverityFilter = value;
    _prefs?.setString(_prefViewerHeatmapSeverityFilter, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setViewerHeatmapLiveModeEnabled(bool value) {
    _viewerHeatmapLiveModeEnabled = value;
    _prefs?.setBool(_prefViewerHeatmapLiveModeEnabled, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setViewerHeatmapAutoFocusEnabled(bool value) {
    _viewerHeatmapAutoFocusEnabled = value;
    _prefs?.setBool(_prefViewerHeatmapAutoFocusEnabled, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setStorageFilterQuery(String value) {
    _storageFilterQuery = value;
    _prefs?.setString(_prefStorageFilterQuery, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setStorageSortByAbc(bool value) {
    _storageSortByAbc = value;
    _prefs?.setBool(_prefStorageSortByAbc, value);
    _touchSettingsSaved();
    notifyListeners();
  }

  void setStorageVisibleSampleCount(int value) {
    _storageVisibleSampleCount = value.clamp(6, 300).toInt();
    _prefs?.setInt(_prefStorageVisibleCount, _storageVisibleSampleCount);
    _touchSettingsSaved();
    notifyListeners();
  }

  void requestViewerZoneFocus(String zoneName) {
    _viewerFocusZoneName = zoneName;
    _viewerFocusRequestId += 1;
    notifyListeners();
  }

  void requestViewerStorageFocus({
    required int rack,
    required int level,
    required int slot,
  }) {
    _viewerFocusRackNumber = rack.clamp(1, 999).toInt();
    _viewerFocusLevelNumber = level.clamp(1, 99).toInt();
    _viewerFocusSlotNumber = slot.clamp(1, 9999).toInt();
    _viewerFocusLocationRequestId += 1;
    notifyListeners();
  }

  void setSelectedStorageLocation(WarehouseStorageLocation? location) {
    _selectedStorageLocation = location;
    notifyListeners();
  }

  void resetViewerState() {
    _viewerZonesVisible = false;
    _viewerHeatmapVisible = false;
    _viewerTourRunning = false;
    _viewerFocusZoneName = null;
    _viewerFocusRackNumber = 1;
    _viewerFocusLevelNumber = 1;
    _viewerFocusSlotNumber = 1;
    _viewerFocusLocationRequestId += 1;
    _selectedStorageLocation = null;
    _viewerResetCount += 1;
    notifyListeners();
  }

  void setControlTowerUiState({
    required String eventStatusFilter,
    required String eventSeverityFilter,
    required String eventTimeFilter,
    required int eventVisibleCount,
    required int auditVisibleCount,
  }) {
    _controlTowerEventStatusFilter = eventStatusFilter;
    _controlTowerEventSeverityFilter = eventSeverityFilter;
    _controlTowerEventTimeFilter = eventTimeFilter;
    _controlTowerEventVisibleCount = eventVisibleCount;
    _controlTowerAuditVisibleCount = auditVisibleCount;
    _prefs?.setString(_prefControlTowerEventStatusFilter, eventStatusFilter);
    _prefs?.setString(_prefControlTowerEventSeverityFilter, eventSeverityFilter);
    _prefs?.setString(_prefControlTowerEventTimeFilter, eventTimeFilter);
    _prefs?.setInt(_prefControlTowerEventVisibleCount, eventVisibleCount);
    _prefs?.setInt(_prefControlTowerAuditVisibleCount, auditVisibleCount);
    _touchSettingsSaved();
    notifyListeners();
  }

  bool isControlTowerEventAcknowledged(String eventId) {
    return _acknowledgedControlTowerEventIds.contains(eventId);
  }

  bool isControlTowerEventEscalated(String eventId) {
    return _escalatedControlTowerEventIds.contains(eventId);
  }

  bool acknowledgeControlTowerEvent(String eventId) {
    if (!canAcknowledgeControlTowerEvents) {
      return false;
    }
    _acknowledgedControlTowerEventIds.add(eventId);
    _controlTowerAuditLog.insert(
      0,
      ControlTowerAuditEntry(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        action: ControlTowerAuditAction.acknowledged,
        actorName: _userName,
        createdAt: DateTime.now(),
        eventId: eventId,
      ),
    );
    notifyListeners();
    return true;
  }

  int acknowledgeAllControlTowerEvents() {
    if (!canAcknowledgeControlTowerEvents) {
      return 0;
    }
    final count = _controlTowerEvents.length;
    _acknowledgedControlTowerEventIds
      ..clear()
      ..addAll(_controlTowerEvents.map((event) => event.id));
    _controlTowerAuditLog.insert(
      0,
      ControlTowerAuditEntry(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        action: ControlTowerAuditAction.acknowledgedAll,
        actorName: _userName,
        createdAt: DateTime.now(),
        count: count,
      ),
    );
    notifyListeners();
    return count;
  }

  bool escalateControlTowerEvent(String eventId) {
    if (!canEscalateControlTowerEvents) {
      return false;
    }
    _escalatedControlTowerEventIds.add(eventId);
    _controlTowerAuditLog.insert(
      0,
      ControlTowerAuditEntry(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        action: ControlTowerAuditAction.escalated,
        actorName: _userName,
        createdAt: DateTime.now(),
        eventId: eventId,
      ),
    );
    notifyListeners();
    return true;
  }

  void acknowledgeAutoEscalationAlert() {
    _autoEscalationAlertAcknowledgedAt = DateTime.now();
    notifyListeners();
  }

  ControlTowerTicket? findControlTowerTicketById(String ticketId) {
    for (final ticket in _controlTowerTickets) {
      if (ticket.id == ticketId) {
        return ticket;
      }
    }
    return null;
  }

  List<ControlTowerTicketActivity> getControlTowerTicketActivities(
    String ticketId,
  ) {
    return List<ControlTowerTicketActivity>.unmodifiable(
      _controlTowerTicketActivities[ticketId] ?? const <ControlTowerTicketActivity>[],
    );
  }

  bool updateControlTowerTicketStatus({
    required String ticketId,
    required ControlTowerTicketStatus status,
  }) {
    final ticket = findControlTowerTicketById(ticketId);
    if (ticket == null) {
      return false;
    }
    if (ticket.status == status) {
      return true;
    }
    _logTicketActivity(
      ticketId: ticketId,
      type: ControlTowerTicketActivityType.statusChanged,
      messageKey: 'ticketActivityStatusChanged',
      messageParams: <String, Object>{
        'old': ticket.status.labelKey,
        'new': status.labelKey,
      },
    );
    _replaceControlTowerTicket(ticket.copyWith(status: status));
    return true;
  }

  bool updateControlTowerTicketEscalationLevel({
    required String ticketId,
    required ControlTowerTicketEscalationLevel escalationLevel,
  }) {
    final ticket = findControlTowerTicketById(ticketId);
    if (ticket == null) {
      return false;
    }
    if (ticket.escalationLevel == escalationLevel) {
      return true;
    }
    _logTicketActivity(
      ticketId: ticketId,
      type: ControlTowerTicketActivityType.escalationChanged,
      messageKey: 'ticketActivityEscalationChanged',
      messageParams: <String, Object>{
        'old': ticket.escalationLevel.labelKey,
        'new': escalationLevel.labelKey,
      },
    );
    _replaceControlTowerTicket(ticket.copyWith(escalationLevel: escalationLevel));
    return true;
  }

  bool assignControlTowerTicket({
    required String ticketId,
    required String? assignee,
  }) {
    final ticket = findControlTowerTicketById(ticketId);
    if (ticket == null) {
      return false;
    }
    if (ticket.assignee == assignee) {
      return true;
    }
    _logTicketActivity(
      ticketId: ticketId,
      type: ControlTowerTicketActivityType.assigned,
      messageKey: 'ticketActivityAssigned',
      messageParams: <String, Object>{
        'assignee': assignee ?? '—',
      },
    );
    _replaceControlTowerTicket(
      ticket.copyWith(assignee: assignee, clearAssignee: assignee == null),
    );
    return true;
  }

  bool addControlTowerTicketComment({
    required String ticketId,
    required String comment,
  }) {
    if (comment.trim().isEmpty) {
      return false;
    }
    final activities = _controlTowerTicketActivities.putIfAbsent(
      ticketId,
      () => <ControlTowerTicketActivity>[],
    );
    activities.insert(
      0,
      ControlTowerTicketActivity(
        id: 'activity-${DateTime.now().millisecondsSinceEpoch}',
        ticketId: ticketId,
        type: ControlTowerTicketActivityType.commented,
        messageKey: 'ticketActivityCommented',
        messageParams: <String, Object>{'comment': comment.trim()},
        actorName: _userName,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    return true;
  }

  void _logTicketActivity({
    required String ticketId,
    required ControlTowerTicketActivityType type,
    required String messageKey,
    Map<String, Object> messageParams = const <String, Object>{},
  }) {
    final activities = _controlTowerTicketActivities.putIfAbsent(
      ticketId,
      () => <ControlTowerTicketActivity>[],
    );
    activities.insert(
      0,
      ControlTowerTicketActivity(
        id: 'activity-${DateTime.now().millisecondsSinceEpoch}',
        ticketId: ticketId,
        type: type,
        messageKey: messageKey,
        messageParams: messageParams,
        actorName: _userName,
        createdAt: DateTime.now(),
      ),
    );
  }

  void markNotificationAsRead(String notificationId) {
    final index =
        _notifications.indexWhere((item) => item.id == notificationId);
    if (index == -1) {
      return;
    }
    final current = _notifications[index];
    _notifications[index] = current.copyWith(isRead: true);
    notifyListeners();
  }

  void markAllNotificationsAsRead() {
    for (var i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    notifyListeners();
  }

  void dismissNotification(String notificationId) {
    _notifications.removeWhere((item) => item.id == notificationId);
    notifyListeners();
  }

  String exportSettingsAsJson() {
    final payload = <String, Object?>{
      'dark_mode': _isDarkMode,
      'notifications': _notificationsEnabled,
      'language': _languageCode,
      'viewer_type': _viewerType.name,
      'user_role': _userRole.name,
      'auto_escalation_first': _autoEscalationFirstStepMinutes,
      'auto_escalation_second': _autoEscalationSecondStepMinutes,
      'heatmap_zone_filter': _viewerHeatmapZoneTypeFilter,
      'heatmap_severity_filter': _viewerHeatmapSeverityFilter,
      'heatmap_live_mode': _viewerHeatmapLiveModeEnabled,
      'heatmap_auto_focus': _viewerHeatmapAutoFocusEnabled,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  bool importSettingsFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return false;
      }
      final payload = Map<String, Object?>.from(decoded.cast<Object?, Object?>());
      _isDarkMode = payload['dark_mode'] is bool ? payload['dark_mode'] as bool : _isDarkMode;
      _notificationsEnabled = payload['notifications'] is bool
          ? payload['notifications'] as bool
          : _notificationsEnabled;
      _languageCode = payload['language']?.toString() ?? _languageCode;
      _viewerType = _viewerTypeFromRaw(payload['viewer_type']?.toString());
      _userRole = _userRoleFromRaw(payload['user_role']?.toString());
      _autoEscalationFirstStepMinutes =
          _toInt(payload['auto_escalation_first'], _autoEscalationFirstStepMinutes);
      _autoEscalationSecondStepMinutes =
          _toInt(payload['auto_escalation_second'], _autoEscalationSecondStepMinutes);
      _viewerHeatmapZoneTypeFilter =
          payload['heatmap_zone_filter']?.toString() ?? _viewerHeatmapZoneTypeFilter;
      _viewerHeatmapSeverityFilter =
          payload['heatmap_severity_filter']?.toString() ?? _viewerHeatmapSeverityFilter;
      _viewerHeatmapLiveModeEnabled = payload['heatmap_live_mode'] is bool
          ? payload['heatmap_live_mode'] as bool
          : _viewerHeatmapLiveModeEnabled;
      _viewerHeatmapAutoFocusEnabled = payload['heatmap_auto_focus'] is bool
          ? payload['heatmap_auto_focus'] as bool
          : _viewerHeatmapAutoFocusEnabled;
      _touchSettingsSaved();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _touchSettingsSaved() {
    _settingsLastSavedAt = DateTime.now();
    _prefs?.setString(_prefSettingsLastSavedAt, _settingsLastSavedAt!.toIso8601String());
  }
  ViewerType _viewerTypeFromRaw(String? raw) {
    if (raw == null) {
      return _viewerType;
    }
    return ViewerType.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ViewerType.nativePlaceholder,
    );
  }

  UserRole _userRoleFromRaw(String? raw) {
    if (raw == null) {
      return _userRole;
    }
    return UserRole.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => UserRole.operator,
    );
  }

  void _syncWarehouseSelections() {
    if (_warehouses.isEmpty) {
      _selectedWarehouse = null;
      _lastOpenedWarehouse = null;
      _viewerHeatmapData.clear();
      return;
    }
    if (_selectedWarehouse == null) {
      _selectedWarehouse = _warehouses.first;
    }
    if (_lastOpenedWarehouse == null) {
      _lastOpenedWarehouse = _selectedWarehouse;
    }
    _rebuildHeatmapData(_selectedWarehouse!);
  }

  void _rebuildHeatmapData(Warehouse warehouse) {
    _viewerHeatmapData
      ..clear()
      ..addAll(warehouse.zones.map((zone) {
        final utilization = zone.utilizationRatio;
        final pickRate = (zone.pickRatePerHour / 400).clamp(0.0, 1.0);
        final congestion = (zone.inboundPerDay / 500).clamp(0.0, 1.0);
        final abcA = zone.abcAnalysis.aRatio;
        return ViewerHeatmapEntry(
          zoneId: zone.id,
          zoneName: zone.name,
          utilization: utilization,
          pickRate: pickRate,
          congestion: congestion,
          abcA: abcA,
        );
      }));
  }

  void _replaceWarehouse(Warehouse warehouse) {
    final index = _warehouses.indexWhere((item) => item.id == warehouse.id);
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
    _rebuildHeatmapData(warehouse);
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
    final normalizedZoneNames = zoneNames.where((name) => name.trim().isNotEmpty).toList();
    final zoneCount = normalizedZoneNames.isEmpty ? 1 : normalizedZoneNames.length;
    final totalSlots = (rackRowCount * rackLevels * 120).clamp(400, 40000);
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

  WarehouseOperationsProfile _buildFallbackOperationsProfile(Warehouse warehouse) {
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
    final zoneCount = warehouse.zones.isEmpty ? 1 : warehouse.zones.length;
    final zoneWidth = width / zoneCount;
    for (var i = 0; i < zoneCount; i++) {
      final zone = warehouse.zones.isEmpty
          ? WarehouseZone(
              id: 'zone-1',
              name: 'Zone 1',
              totalStorageSlots: 1000,
              occupiedStorageSlots: 700,
              articleCount: 2200,
              abcAnalysis: const AbcAnalysis(aCount: 440, bCount: 660, cCount: 1100),
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

  int _toInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse('$value') ?? fallback;
  }

  void _seedControlTowerData() {
    final now = DateTime.now();
    _controlTowerEvents
      ..clear()
      ..addAll(<ControlTowerEvent>[
        ControlTowerEvent(
          id: 'evt-001',
          type: ControlTowerEventType.warehouse,
          severity: ControlTowerEventSeverity.critical,
          titleKey: 'controlTowerEventCapacityTitle',
          messageKey: 'controlTowerEventCapacityMsg',
          createdAt: now.subtract(const Duration(minutes: 20)),
          messageParams: const <String, Object>{'zone': 'Zone A4'},
          warehouseId: 'wh-001',
        ),
        ControlTowerEvent(
          id: 'evt-002',
          type: ControlTowerEventType.inventory,
          severity: ControlTowerEventSeverity.warning,
          titleKey: 'controlTowerEventInventoryTitle',
          messageKey: 'controlTowerEventInventoryMsg',
          createdAt: now.subtract(const Duration(hours: 1, minutes: 12)),
          messageParams: const <String, Object>{'count': 42},
          warehouseId: 'wh-002',
        ),
        ControlTowerEvent(
          id: 'evt-003',
          type: ControlTowerEventType.tour,
          severity: ControlTowerEventSeverity.info,
          titleKey: 'controlTowerEventTourTitle',
          messageKey: 'controlTowerEventTourMsg',
          createdAt: now.subtract(const Duration(hours: 2, minutes: 30)),
          messageParams: const <String, Object>{'tour': 'TR-24032'},
          tourId: 'tour-002',
        ),
      ]);

    _controlTowerTickets
      ..clear()
      ..addAll(<ControlTowerTicket>[
        ControlTowerTicket(
          id: 'ticket-001',
          eventId: 'evt-001',
          titleKey: 'controlTowerTicketCapacityTitle',
          messageKey: 'controlTowerTicketCapacityMsg',
          messageParams: const <String, Object>{'zone': 'Zone A4'},
          severity: ControlTowerEventSeverity.critical,
          escalationLevel: ControlTowerTicketEscalationLevel.level3,
          createdAt: now.subtract(const Duration(minutes: 25)),
          createdBy: 'System',
          status: ControlTowerTicketStatus.open,
          warehouseId: 'wh-001',
        ),
        ControlTowerTicket(
          id: 'ticket-002',
          eventId: 'evt-002',
          titleKey: 'controlTowerTicketInventoryTitle',
          messageKey: 'controlTowerTicketInventoryMsg',
          messageParams: const <String, Object>{'count': 42},
          severity: ControlTowerEventSeverity.warning,
          escalationLevel: ControlTowerTicketEscalationLevel.level2,
          createdAt: now.subtract(const Duration(hours: 1, minutes: 10)),
          createdBy: 'System',
          status: ControlTowerTicketStatus.inProgress,
          warehouseId: 'wh-002',
        ),
      ]);

    _controlTowerAuditLog
      ..clear()
      ..add(
        ControlTowerAuditEntry(
          id: 'audit-001',
          action: ControlTowerAuditAction.acknowledged,
          actorName: _userName,
          createdAt: now.subtract(const Duration(hours: 2, minutes: 15)),
          eventTitleKey: 'controlTowerEventTourTitle',
        ),
      );

    _lastControlTowerHeartbeat = now;
    _controlTowerFeedActive = true;
  }

  void _replaceControlTowerTicket(ControlTowerTicket ticket) {
    final index = _controlTowerTickets.indexWhere((item) => item.id == ticket.id);
    if (index == -1) {
      return;
    }
    _controlTowerTickets[index] = ticket;
    notifyListeners();
  }

  List<AppNotificationItem> _defaultNotifications() {
    final now = DateTime.now();
    return <AppNotificationItem>[
      AppNotificationItem(
        id: 'notif-001',
        title: 'Heatmap aktualisiert',
        message: 'Live-Analyse für Zone A4 ist verfügbar.',
        createdAt: now.subtract(const Duration(minutes: 12)),
        severity: NotificationSeverity.info,
      ),
      AppNotificationItem(
        id: 'notif-002',
        title: 'Kapazität kritisch',
        message: 'Auslastung über 92% in Hochregallager Nord.',
        createdAt: now.subtract(const Duration(hours: 3)),
        severity: NotificationSeverity.warning,
      ),
    ];
  }
}
