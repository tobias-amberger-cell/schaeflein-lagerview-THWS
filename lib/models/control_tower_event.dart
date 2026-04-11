enum ControlTowerEventSeverity {
  info,
  warning,
  critical,
}

extension ControlTowerEventSeverityLabel on ControlTowerEventSeverity {
  String get labelKey {
    switch (this) {
      case ControlTowerEventSeverity.info:
        return 'severityInfo';
      case ControlTowerEventSeverity.warning:
        return 'severityWarning';
      case ControlTowerEventSeverity.critical:
        return 'severityCritical';
    }
  }
}

enum ControlTowerEventType {
  warehouse,
  tour,
  ramp,
  inventory,
}

extension ControlTowerEventTypeLabel on ControlTowerEventType {
  String get labelKey {
    switch (this) {
      case ControlTowerEventType.warehouse:
        return 'eventTypeWarehouse';
      case ControlTowerEventType.tour:
        return 'eventTypeTour';
      case ControlTowerEventType.ramp:
        return 'eventTypeRamp';
      case ControlTowerEventType.inventory:
        return 'eventTypeInventory';
    }
  }
}

class ControlTowerEvent {
  const ControlTowerEvent({
    required this.id,
    required this.type,
    required this.severity,
    required this.titleKey,
    required this.messageKey,
    required this.createdAt,
    this.messageParams = const <String, Object>{},
    this.warehouseId,
    this.tourId,
  });

  final String id;
  final ControlTowerEventType type;
  final ControlTowerEventSeverity severity;
  final String titleKey;
  final String messageKey;
  final Map<String, Object> messageParams;
  final DateTime createdAt;
  final String? warehouseId;
  final String? tourId;
}
