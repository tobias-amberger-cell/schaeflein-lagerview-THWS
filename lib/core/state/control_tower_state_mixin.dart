import 'package:flutter/widgets.dart';

import '../../models/control_tower_audit_entry.dart';
import '../../models/control_tower_event.dart';
import '../../models/control_tower_ticket.dart';
import '../../models/control_tower_ticket_activity.dart';

mixin ControlTowerStateMixin on ChangeNotifier {
  final List<ControlTowerEvent> controlTowerEventItems = <ControlTowerEvent>[];
  final List<ControlTowerTicket> controlTowerTicketItems =
      <ControlTowerTicket>[];
  final Map<String, List<ControlTowerTicketActivity>>
      controlTowerTicketActivityMap =
      <String, List<ControlTowerTicketActivity>>{};
  final List<ControlTowerAuditEntry> controlTowerAuditLogItems =
      <ControlTowerAuditEntry>[];
  final Set<String> acknowledgedControlTowerEventIds = <String>{};
  final Set<String> escalatedControlTowerEventIds = <String>{};
  DateTime? lastControlTowerHeartbeatValue;
  bool controlTowerFeedActiveValue = true;
  DateTime? autoEscalationAlertAcknowledgedAt;

  /// Must be provided by the host class.
  String get userName;
  bool get canAcknowledgeControlTowerEvents;
  bool get canEscalateControlTowerEvents;

  List<ControlTowerEvent> get controlTowerEvents =>
      List<ControlTowerEvent>.unmodifiable(controlTowerEventItems);

  List<ControlTowerTicket> get controlTowerTickets =>
      List<ControlTowerTicket>.unmodifiable(controlTowerTicketItems);

  List<ControlTowerAuditEntry> get controlTowerAuditLog =>
      List<ControlTowerAuditEntry>.unmodifiable(controlTowerAuditLogItems);

  bool get isControlTowerFeedActive => controlTowerFeedActiveValue;
  DateTime? get lastControlTowerHeartbeat => lastControlTowerHeartbeatValue;

  int get openControlTowerTicketCount => controlTowerTicketItems
      .where((ticket) => ticket.status == ControlTowerTicketStatus.open)
      .length;

  int get overdueControlTowerTicketCount {
    final now = DateTime.now();
    return controlTowerTicketItems
        .where((ticket) => ticket.isSlaBreachedAt(now))
        .length;
  }

  int get escalatedControlTowerEventCount =>
      escalatedControlTowerEventIds.length;

  int get criticalControlTowerTicketCount => controlTowerTicketItems
      .where((ticket) =>
          ticket.severity == ControlTowerEventSeverity.critical &&
          !ticket.isResolved)
      .length;

  int get pendingAutoEscalationAlertCount => controlTowerTicketItems
      .where(
          (ticket) => ticket.severity == ControlTowerEventSeverity.critical)
      .length;

  int get automaticEscalatedTicketCountLastHour =>
      controlTowerTicketItems.where(
        (ticket) =>
            DateTime.now().difference(ticket.createdAt).inMinutes < 60 &&
            ticket.escalationLevel == ControlTowerTicketEscalationLevel.level3,
      ).length;

  bool isControlTowerEventAcknowledged(String eventId) {
    return acknowledgedControlTowerEventIds.contains(eventId);
  }

  bool isControlTowerEventEscalated(String eventId) {
    return escalatedControlTowerEventIds.contains(eventId);
  }

  bool acknowledgeControlTowerEvent(String eventId) {
    if (!canAcknowledgeControlTowerEvents) {
      return false;
    }
    acknowledgedControlTowerEventIds.add(eventId);
    controlTowerAuditLogItems.insert(
      0,
      ControlTowerAuditEntry(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        action: ControlTowerAuditAction.acknowledged,
        actorName: userName,
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
    final count = controlTowerEventItems.length;
    acknowledgedControlTowerEventIds
      ..clear()
      ..addAll(controlTowerEventItems.map((event) => event.id));
    controlTowerAuditLogItems.insert(
      0,
      ControlTowerAuditEntry(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        action: ControlTowerAuditAction.acknowledgedAll,
        actorName: userName,
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
    escalatedControlTowerEventIds.add(eventId);
    controlTowerAuditLogItems.insert(
      0,
      ControlTowerAuditEntry(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        action: ControlTowerAuditAction.escalated,
        actorName: userName,
        createdAt: DateTime.now(),
        eventId: eventId,
      ),
    );
    notifyListeners();
    return true;
  }

  void acknowledgeAutoEscalationAlert() {
    autoEscalationAlertAcknowledgedAt = DateTime.now();
    notifyListeners();
  }

  ControlTowerTicket? findControlTowerTicketById(String ticketId) {
    for (final ticket in controlTowerTicketItems) {
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
      controlTowerTicketActivityMap[ticketId] ??
          const <ControlTowerTicketActivity>[],
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
    _replaceControlTowerTicket(
        ticket.copyWith(escalationLevel: escalationLevel));
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
    final activities = controlTowerTicketActivityMap.putIfAbsent(
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
        actorName: userName,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    return true;
  }

  void seedControlTowerData() {
    final now = DateTime.now();
    controlTowerEventItems
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

    controlTowerTicketItems
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

    controlTowerAuditLogItems
      ..clear()
      ..add(
        ControlTowerAuditEntry(
          id: 'audit-001',
          action: ControlTowerAuditAction.acknowledged,
          actorName: userName,
          createdAt: now.subtract(const Duration(hours: 2, minutes: 15)),
          eventTitleKey: 'controlTowerEventTourTitle',
        ),
      );

    lastControlTowerHeartbeatValue = now;
    controlTowerFeedActiveValue = true;
  }

  void _logTicketActivity({
    required String ticketId,
    required ControlTowerTicketActivityType type,
    required String messageKey,
    Map<String, Object> messageParams = const <String, Object>{},
  }) {
    final activities = controlTowerTicketActivityMap.putIfAbsent(
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
        actorName: userName,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _replaceControlTowerTicket(ControlTowerTicket ticket) {
    final index =
        controlTowerTicketItems.indexWhere((item) => item.id == ticket.id);
    if (index == -1) {
      return;
    }
    controlTowerTicketItems[index] = ticket;
    notifyListeners();
  }
}
