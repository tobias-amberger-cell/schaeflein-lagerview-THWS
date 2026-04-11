enum ControlTowerTicketActivityType {
  created,
  statusChanged,
  escalationChanged,
  assigned,
  commented,
}

class ControlTowerTicketActivity {
  const ControlTowerTicketActivity({
    required this.id,
    required this.ticketId,
    required this.type,
    required this.messageKey,
    required this.messageParams,
    required this.actorName,
    required this.createdAt,
  });

  final String id;
  final String ticketId;
  final ControlTowerTicketActivityType type;
  final String messageKey;
  final Map<String, Object> messageParams;
  final String actorName;
  final DateTime createdAt;
}
