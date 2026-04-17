import 'package:flutter/widgets.dart';

import '../../models/viewer_heatmap.dart';
import '../../models/warehouse.dart';

mixin ViewerStateMixin on ChangeNotifier {
  bool viewerZonesVisibleValue = false;
  bool viewerTourRunningValue = false;
  bool viewerHeatmapVisibleValue = false;
  String? viewerFocusZoneNameValue;
  int viewerFocusRequestIdValue = 0;
  int viewerFocusRackNumberValue = 1;
  int viewerFocusLevelNumberValue = 1;
  int viewerFocusSlotNumberValue = 1;
  int viewerFocusLocationRequestIdValue = 0;
  int viewerResetCountValue = 0;
  ViewerHeatmapMetric viewerHeatmapMetricValue =
      ViewerHeatmapMetric.utilization;
  final List<ViewerHeatmapEntry> viewerHeatmapItems = <ViewerHeatmapEntry>[];
  final Map<String, List<WarehouseStorageLocation>>
      warehouseStorageLocationMap =
      <String, List<WarehouseStorageLocation>>{};
  WarehouseStorageLocation? selectedStorageLocationValue;

  bool get viewerZonesVisible => viewerZonesVisibleValue;
  bool get viewerTourRunning => viewerTourRunningValue;
  bool get viewerHeatmapVisible => viewerHeatmapVisibleValue;
  String? get viewerFocusZoneName => viewerFocusZoneNameValue;
  int get viewerFocusRequestId => viewerFocusRequestIdValue;
  int get viewerFocusRackNumber => viewerFocusRackNumberValue;
  int get viewerFocusLevelNumber => viewerFocusLevelNumberValue;
  int get viewerFocusSlotNumber => viewerFocusSlotNumberValue;
  int get viewerFocusLocationRequestId => viewerFocusLocationRequestIdValue;
  int get viewerResetCount => viewerResetCountValue;
  ViewerHeatmapMetric get viewerHeatmapMetric => viewerHeatmapMetricValue;
  WarehouseStorageLocation? get selectedStorageLocation =>
      selectedStorageLocationValue;

  List<ViewerHeatmapEntry> get viewerHeatmapData =>
      List<ViewerHeatmapEntry>.unmodifiable(viewerHeatmapItems);

  List<WarehouseStorageLocation> getStorageLocationsForWarehouse(
      String warehouseId) {
    return warehouseStorageLocationMap[warehouseId] ??
        const <WarehouseStorageLocation>[];
  }

  String? get topRiskZoneName {
    if (viewerHeatmapItems.isEmpty) {
      return null;
    }
    final sorted = List<ViewerHeatmapEntry>.from(viewerHeatmapItems)
      ..sort((a, b) => b.utilization.compareTo(a.utilization));
    return sorted.first.zoneName;
  }

  double get topRiskScore {
    if (viewerHeatmapItems.isEmpty) {
      return 0.0;
    }
    var maxValue = 0.0;
    for (final entry in viewerHeatmapItems) {
      final value = entry.valueFor(viewerHeatmapMetricValue);
      if (value > maxValue) {
        maxValue = value;
      }
    }
    return maxValue.clamp(0.0, 1.0);
  }

  bool get hasCriticalTopRisk => topRiskScore >= 0.85;

  void setViewerZonesVisible(bool value) {
    viewerZonesVisibleValue = value;
    notifyListeners();
  }

  void setViewerTourRunning(bool value) {
    viewerTourRunningValue = value;
    notifyListeners();
  }

  void setViewerHeatmapVisible(bool value) {
    viewerHeatmapVisibleValue = value;
    notifyListeners();
  }

  void setViewerHeatmapMetric(ViewerHeatmapMetric metric) {
    viewerHeatmapMetricValue = metric;
    notifyListeners();
  }

  void requestViewerZoneFocus(String zoneName) {
    viewerFocusZoneNameValue = zoneName;
    viewerFocusRequestIdValue += 1;
    notifyListeners();
  }

  void requestViewerStorageFocus({
    required int rack,
    required int level,
    required int slot,
  }) {
    viewerFocusRackNumberValue = rack.clamp(1, 999).toInt();
    viewerFocusLevelNumberValue = level.clamp(1, 99).toInt();
    viewerFocusSlotNumberValue = slot.clamp(1, 9999).toInt();
    viewerFocusLocationRequestIdValue += 1;
    notifyListeners();
  }

  void setSelectedStorageLocation(WarehouseStorageLocation? location) {
    selectedStorageLocationValue = location;
    notifyListeners();
  }

  void resetViewerState() {
    viewerZonesVisibleValue = false;
    viewerHeatmapVisibleValue = false;
    viewerTourRunningValue = false;
    viewerFocusZoneNameValue = null;
    viewerFocusRackNumberValue = 1;
    viewerFocusLevelNumberValue = 1;
    viewerFocusSlotNumberValue = 1;
    viewerFocusLocationRequestIdValue += 1;
    selectedStorageLocationValue = null;
    viewerResetCountValue += 1;
    notifyListeners();
  }

  void rebuildHeatmapData(Warehouse warehouse) {
    viewerHeatmapItems
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
}
