enum ControlTowerAuditAction {
  acknowledged,
  escalated,
  acknowledgedAll,
}

extension ControlTowerAuditActionLabel on ControlTowerAuditAction {
  String get labelKey {
    switch (this) {
      case ControlTowerAuditAction.acknowledged:
        return 'auditActionAcknowledged';
      case ControlTowerAuditAction.escalated:
        return 'auditActionEscalated';
      case ControlTowerAuditAction.acknowledgedAll:
        return 'auditActionAcknowledgedAll';
    }
  }
}

class ControlTowerAuditEntry {
  const ControlTowerAuditEntry({
    required this.id,
    required this.action,
    required this.actorName,
    required this.createdAt,
    this.eventId,
    this.eventTitleKey,
    this.count,
  });

  final String id;
  final ControlTowerAuditAction action;
  final String actorName;
  final DateTime createdAt;
  final String? eventId;
  final String? eventTitleKey;
  final int? count;
}
