import 'control_tower_event.dart';

enum ControlTowerTicketStatus {
  open,
  inProgress,
  resolved,
}

extension ControlTowerTicketStatusLabel on ControlTowerTicketStatus {
  String get labelKey {
    switch (this) {
      case ControlTowerTicketStatus.open:
        return 'ticketStatusOpen';
      case ControlTowerTicketStatus.inProgress:
        return 'ticketStatusInProgress';
      case ControlTowerTicketStatus.resolved:
        return 'ticketStatusResolved';
    }
  }
}

enum ControlTowerTicketEscalationLevel {
  level1,
  level2,
  level3,
}

extension ControlTowerTicketEscalationLevelLabel
    on ControlTowerTicketEscalationLevel {
  String get labelKey {
    switch (this) {
      case ControlTowerTicketEscalationLevel.level1:
        return 'ticketLevelL1';
      case ControlTowerTicketEscalationLevel.level2:
        return 'ticketLevelL2';
      case ControlTowerTicketEscalationLevel.level3:
        return 'ticketLevelL3';
    }
  }
}

class ControlTowerTicket {
  const ControlTowerTicket({
    required this.id,
    required this.eventId,
    required this.titleKey,
    required this.messageKey,
    required this.messageParams,
    required this.severity,
    required this.escalationLevel,
    required this.createdAt,
    required this.createdBy,
    required this.status,
    this.assignee,
    this.warehouseId,
    this.tourId,
  });

  final String id;
  final String eventId;
  final String titleKey;
  final String messageKey;
  final Map<String, Object> messageParams;
  final ControlTowerEventSeverity severity;
  final ControlTowerTicketEscalationLevel escalationLevel;
  final DateTime createdAt;
  final String createdBy;
  final ControlTowerTicketStatus status;
  final String? assignee;
  final String? warehouseId;
  final String? tourId;

  String get severityLabelKey => severity.labelKey;

  Duration get slaDuration {
    switch (severity) {
      case ControlTowerEventSeverity.critical:
        return const Duration(minutes: 20);
      case ControlTowerEventSeverity.warning:
        return const Duration(minutes: 60);
      case ControlTowerEventSeverity.info:
        return const Duration(minutes: 180);
    }
  }

  DateTime get slaDeadline => createdAt.add(slaDuration);

  bool get isResolved => status == ControlTowerTicketStatus.resolved;

  bool isSlaBreachedAt(DateTime timestamp) {
    if (isResolved) {
      return false;
    }
    return timestamp.isAfter(slaDeadline);
  }

  int slaDeltaMinutesAt(DateTime timestamp) {
    return slaDeadline.difference(timestamp).inMinutes;
  }

  ControlTowerTicket copyWith({
    ControlTowerTicketStatus? status,
    ControlTowerEventSeverity? severity,
    ControlTowerTicketEscalationLevel? escalationLevel,
    String? assignee,
    bool clearAssignee = false,
  }) {
    return ControlTowerTicket(
      id: id,
      eventId: eventId,
      titleKey: titleKey,
      messageKey: messageKey,
      messageParams: messageParams,
      severity: severity ?? this.severity,
      escalationLevel: escalationLevel ?? this.escalationLevel,
      createdAt: createdAt,
      createdBy: createdBy,
      status: status ?? this.status,
      assignee: clearAssignee ? null : (assignee ?? this.assignee),
      warehouseId: warehouseId,
      tourId: tourId,
    );
  }

  static ControlTowerTicketEscalationLevel defaultEscalationLevelForSeverity(
    ControlTowerEventSeverity severity,
  ) {
    switch (severity) {
      case ControlTowerEventSeverity.info:
        return ControlTowerTicketEscalationLevel.level1;
      case ControlTowerEventSeverity.warning:
        return ControlTowerTicketEscalationLevel.level2;
      case ControlTowerEventSeverity.critical:
        return ControlTowerTicketEscalationLevel.level3;
    }
  }
}
