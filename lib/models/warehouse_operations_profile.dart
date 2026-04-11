class WarehouseOperationsProfile {
  const WarehouseOperationsProfile({
    required this.warehouseId,
    required this.dockCount,
    required this.activeDocks,
    required this.blockedSlots,
    required this.reservedSlots,
    required this.slaTargetPercent,
    required this.slaCurrentPercent,
    required this.avgDwellMinutes,
    required this.coldZoneCount,
    required this.ambientZoneCount,
    required this.hazardousZoneCount,
    required this.highBaySlots,
    required this.blockStorageSlots,
    required this.shuttleSlots,
    required this.floorStorageSlots,
    required this.safetyIncidentsMonth,
    required this.qualityHolds,
  });

  final String warehouseId;
  final int dockCount;
  final int activeDocks;
  final int blockedSlots;
  final int reservedSlots;
  final int slaTargetPercent;
  final int slaCurrentPercent;
  final int avgDwellMinutes;
  final int coldZoneCount;
  final int ambientZoneCount;
  final int hazardousZoneCount;
  final int highBaySlots;
  final int blockStorageSlots;
  final int shuttleSlots;
  final int floorStorageSlots;
  final int safetyIncidentsMonth;
  final int qualityHolds;

  int get totalZoneTypes => coldZoneCount + ambientZoneCount + hazardousZoneCount;

  int get totalSlotMix =>
      highBaySlots + blockStorageSlots + shuttleSlots + floorStorageSlots;

  int get inactiveDocks => (dockCount - activeDocks).clamp(0, dockCount).toInt();

  double get dockUtilizationRatio {
    if (dockCount <= 0) {
      return 0;
    }
    return (activeDocks / dockCount).clamp(0, 1).toDouble();
  }

  double get slaGap => (slaTargetPercent - slaCurrentPercent).toDouble();
}
