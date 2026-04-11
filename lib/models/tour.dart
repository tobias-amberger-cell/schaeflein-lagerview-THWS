enum TourStatus {
  planned,
  loading,
  inTransit,
  delayed,
  completed,
}

extension TourStatusLabel on TourStatus {
  String get labelKey {
    switch (this) {
      case TourStatus.planned:
        return 'tourStatusPlanned';
      case TourStatus.loading:
        return 'tourStatusLoading';
      case TourStatus.inTransit:
        return 'tourStatusInTransit';
      case TourStatus.delayed:
        return 'tourStatusDelayed';
      case TourStatus.completed:
        return 'tourStatusCompleted';
    }
  }
}

enum TourStopStatus {
  pending,
  arrived,
  unloaded,
}

extension TourStopStatusLabel on TourStopStatus {
  String get labelKey {
    switch (this) {
      case TourStopStatus.pending:
        return 'tourStopPending';
      case TourStopStatus.arrived:
        return 'tourStopArrived';
      case TourStopStatus.unloaded:
        return 'tourStopUnloaded';
    }
  }
}

class TourStop {
  const TourStop({
    required this.id,
    required this.name,
    required this.address,
    required this.plannedArrival,
    required this.status,
    this.actualArrival,
  });

  final String id;
  final String name;
  final String address;
  final DateTime plannedArrival;
  final DateTime? actualArrival;
  final TourStopStatus status;
}

class TransportTour {
  const TransportTour({
    required this.id,
    required this.code,
    required this.warehouseId,
    required this.vehicleCode,
    required this.driverName,
    required this.status,
    required this.plannedDeparture,
    required this.estimatedArrival,
    required this.loadFactorPercent,
    required this.temperatureControlled,
    required this.stops,
  });

  final String id;
  final String code;
  final String warehouseId;
  final String vehicleCode;
  final String driverName;
  final TourStatus status;
  final DateTime plannedDeparture;
  final DateTime estimatedArrival;
  final int loadFactorPercent;
  final bool temperatureControlled;
  final List<TourStop> stops;

  int get stopCount => stops.length;

  int get completedStops => stops
      .where((stop) => stop.status == TourStopStatus.unloaded)
      .length;

  double get progressRatio {
    if (stops.isEmpty) {
      return 0;
    }
    return (completedStops / stops.length).clamp(0, 1).toDouble();
  }

  int get progressPercent => (progressRatio * 100).round();
}
