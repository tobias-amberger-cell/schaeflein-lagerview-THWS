enum ViewerHeatmapMetric {
  utilization,
  pickRate,
  congestion,
  abcA,
}

extension ViewerHeatmapMetricLabel on ViewerHeatmapMetric {
  String get labelKey {
    switch (this) {
      case ViewerHeatmapMetric.utilization:
        return 'heatmapMetricUtilization';
      case ViewerHeatmapMetric.pickRate:
        return 'heatmapMetricPickRate';
      case ViewerHeatmapMetric.congestion:
        return 'heatmapMetricCongestion';
      case ViewerHeatmapMetric.abcA:
        return 'heatmapMetricAbcA';
    }
  }
}

class ViewerHeatmapEntry {
  const ViewerHeatmapEntry({
    required this.zoneId,
    required this.zoneName,
    required this.utilization,
    required this.pickRate,
    required this.congestion,
    required this.abcA,
  });

  final String zoneId;
  final String zoneName;
  final double utilization;
  final double pickRate;
  final double congestion;
  final double abcA;

  double valueFor(ViewerHeatmapMetric metric) {
    switch (metric) {
      case ViewerHeatmapMetric.utilization:
        return utilization;
      case ViewerHeatmapMetric.pickRate:
        return pickRate;
      case ViewerHeatmapMetric.congestion:
        return congestion;
      case ViewerHeatmapMetric.abcA:
        return abcA;
    }
  }
}
