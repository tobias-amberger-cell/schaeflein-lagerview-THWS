class WarehouseHeatmapLayerEntry {
  const WarehouseHeatmapLayerEntry({
    required this.platzId,
    required this.regal,
    required this.fach,
    required this.ebene,
    required this.utilization,
    required this.heatmapColor,
  });

  final String platzId;
  final int regal;
  final int fach;
  final int ebene;
  final double utilization;
  final String heatmapColor;

  double get utilizationUnit => (utilization / 100).clamp(0, 1).toDouble();
}

