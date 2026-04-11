import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/control_tower_ticket.dart';
import '../../../../models/control_tower_ticket_activity.dart';
import '../../../../shared/widgets/empty_state.dart';

class ControlTowerTicketDetailScreen extends StatefulWidget {
  const ControlTowerTicketDetailScreen({
    required this.ticketId,
    super.key,
  });

  final String ticketId;

  @override
  State<ControlTowerTicketDetailScreen> createState() =>
      _ControlTowerTicketDetailScreenState();
}

class _ControlTowerTicketDetailScreenState
    extends State<ControlTowerTicketDetailScreen> {
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final ticket = appState.findControlTowerTicketById(widget.ticketId);

    if (ticket == null) {
      return ListView(
        children: <Widget>[
          Text(
            context.tr('ticketDetailsTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          EmptyState(
            icon: Icons.confirmation_number_outlined,
            title: context.tr('ticketDetailsNotFoundTitle'),
            message: context.tr('ticketDetailsNotFoundMessage'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => context.go('/control-tower/tickets'),
              icon: const Icon(Icons.arrow_back),
              label: Text(context.tr('controlTowerTicketsTitle')),
            ),
          ),
        ],
      );
    }

    final activities = appState.getControlTowerTicketActivities(ticket.id);
    final canEdit = appState.canEscalateControlTowerEvents;
    final assignees = <String>[
      appState.userName,
      'Leitstand Team',
      'Operative Steuerung',
      'Technik Bereitschaft',
    ];

    return ListView(
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => context.go('/control-tower/tickets'),
              icon: const Icon(Icons.arrow_back),
              label: Text(context.tr('controlTowerTicketsTitle')),
            ),
            Text(
              context.tr('ticketDetailsTitle'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.tr(ticket.titleKey),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _TicketStatusBadge(status: ticket.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(context.tr(ticket.messageKey, ticket.messageParams)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    _TicketSlaBadge(ticket: ticket),
                    _InfoChip(
                      label: context.tr('severity'),
                      value: context.tr(ticket.severityLabelKey),
                    ),
                    _EscalationBadge(level: ticket.escalationLevel),
                    _InfoChip(
                      label: context.tr('ticketAssignee'),
                      value: ticket.assignee ?? context.tr('ticketUnassigned'),
                    ),
                    _InfoChip(
                      label: context.tr('ticketCreatedBy'),
                      value: ticket.createdBy,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    DropdownButtonHideUnderline(
                      child: DropdownButton<ControlTowerTicketStatus>(
                        value: ticket.status,
                        items: ControlTowerTicketStatus.values
                            .map(
                              (status) =>
                                  DropdownMenuItem<ControlTowerTicketStatus>(
                                value: status,
                                child: Text(context.tr(status.labelKey)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: canEdit
                            ? (value) {
                                if (value == null) {
                                  return;
                                }
                                final updated =
                                    appState.updateControlTowerTicketStatus(
                                  ticketId: ticket.id,
                                  status: value,
                                );
                                if (!updated) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.tr(
                                          'controlTowerTicketUpdateFailed',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<ControlTowerTicketEscalationLevel>(
                        value: ticket.escalationLevel,
                        items: ControlTowerTicketEscalationLevel.values
                            .map(
                              (level) =>
                                  DropdownMenuItem<ControlTowerTicketEscalationLevel>(
                                value: level,
                                child: Text(context.tr(level.labelKey)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: canEdit
                            ? (value) {
                                if (value == null) {
                                  return;
                                }
                                final updated =
                                    appState.updateControlTowerTicketEscalationLevel(
                                  ticketId: ticket.id,
                                  escalationLevel: value,
                                );
                                if (!updated) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.tr(
                                          'controlTowerTicketUpdateFailed',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        hint: Text(context.tr('ticketAssignAction')),
                        value: ticket.assignee,
                        items: assignees
                            .map(
                              (name) => DropdownMenuItem<String>(
                                value: name,
                                child: Text(name),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: canEdit
                            ? (value) {
                                if (value == null) {
                                  return;
                                }
                                final updated = appState.assignControlTowerTicket(
                                  ticketId: ticket.id,
                                  assignee: value,
                                );
                                if (!updated) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.tr(
                                          'controlTowerTicketUpdateFailed',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                    if (ticket.warehouseId != null)
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/warehouses/${ticket.warehouseId}'),
                        icon: const Icon(Icons.warehouse_outlined),
                        label: Text(context.tr('warehouseAction')),
                      ),
                    if (ticket.tourId != null)
                      OutlinedButton.icon(
                        onPressed: () => context.go('/tours'),
                        icon: const Icon(Icons.route_outlined),
                        label: Text(context.tr('tourStopsAction')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('ticketTimelineTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (activities.isEmpty)
                  Text(context.tr('ticketNoTimeline'))
                else
                  ...activities.map(
                    (activity) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_iconForActivity(activity.type), size: 18),
                      title: Text(
                        context.tr(
                          activity.messageKey,
                          _localizedActivityParams(context, activity),
                        ),
                      ),
                      subtitle: Text(
                        context.tr(
                          'ticketUpdatedBy',
                          <String, Object>{
                            'user': activity.actorName,
                            'time': _relativeTime(context, activity.createdAt),
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    maxLines: 2,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: context.tr('ticketCommentHint'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: canEdit ? () => _submitComment(context, ticket.id) : null,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(context.tr('ticketAddComment')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _submitComment(BuildContext context, String ticketId) {
    final appState = context.read<AppState>();
    final success = appState.addControlTowerTicketComment(
      ticketId: ticketId,
      comment: _commentController.text,
    );
    if (success) {
      _commentController.clear();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(success ? 'ticketCommentAdded' : 'ticketCommentFailed'),
        ),
      ),
    );
  }

  IconData _iconForActivity(ControlTowerTicketActivityType type) {
    switch (type) {
      case ControlTowerTicketActivityType.created:
        return Icons.add_circle_outline;
      case ControlTowerTicketActivityType.statusChanged:
        return Icons.sync_alt_outlined;
      case ControlTowerTicketActivityType.escalationChanged:
        return Icons.vertical_align_top_outlined;
      case ControlTowerTicketActivityType.assigned:
        return Icons.person_add_alt_1_outlined;
      case ControlTowerTicketActivityType.commented:
        return Icons.chat_bubble_outline;
    }
  }

  Map<String, Object> _localizedActivityParams(
    BuildContext context,
    ControlTowerTicketActivity activity,
  ) {
    final params = Map<String, Object>.from(activity.messageParams);
    final oldValue = params['old'];
    final newValue = params['new'];
    if (oldValue is String) {
      params['old'] = context.tr(oldValue);
    }
    if (newValue is String) {
      params['new'] = context.tr(newValue);
    }
    return params;
  }

  String _relativeTime(BuildContext context, DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return context.tr('justNow');
    }
    if (diff.inMinutes < 60) {
      return context.tr('minutesAgo', <String, Object>{'count': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return context.tr('hoursAgo', <String, Object>{'count': diff.inHours});
    }
    return context.tr('daysAgo', <String, Object>{'count': diff.inDays});
  }
}

class _TicketStatusBadge extends StatelessWidget {
  const _TicketStatusBadge({required this.status});

  final ControlTowerTicketStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ControlTowerTicketStatus.open => Colors.orange.shade800,
      ControlTowerTicketStatus.inProgress => Colors.blue.shade800,
      ControlTowerTicketStatus.resolved => Colors.green.shade800,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        child: Text(
          context.tr(status.labelKey),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _TicketSlaBadge extends StatelessWidget {
  const _TicketSlaBadge({required this.ticket});

  final ControlTowerTicket ticket;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final deltaMinutes = ticket.slaDeltaMinutesAt(now);

    late final String label;
    late final Color background;
    late final Color foreground;

    if (ticket.isResolved) {
      label = context.tr('ticketSlaResolved');
      background = Colors.green.withValues(alpha: 0.14);
      foreground = Colors.green.shade800;
    } else if (deltaMinutes < 0) {
      label = context.tr(
        'ticketSlaBreached',
        <String, Object>{'minutes': deltaMinutes.abs()},
      );
      background = Colors.red.withValues(alpha: 0.14);
      foreground = Colors.red.shade800;
    } else {
      label = context.tr(
        'ticketSlaDueIn',
        <String, Object>{'minutes': deltaMinutes},
      );
      background = Colors.orange.withValues(alpha: 0.14);
      foreground = Colors.orange.shade800;
    }

    return _InlineBadge(
      label: label,
      background: background,
      foreground: foreground,
    );
  }
}

class _EscalationBadge extends StatelessWidget {
  const _EscalationBadge({required this.level});

  final ControlTowerTicketEscalationLevel level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      ControlTowerTicketEscalationLevel.level1 => Colors.blue.shade700,
      ControlTowerTicketEscalationLevel.level2 => Colors.orange.shade700,
      ControlTowerTicketEscalationLevel.level3 => Colors.red.shade700,
    };
    return _InlineBadge(
      label: context.tr(level.labelKey),
      background: color.withValues(alpha: 0.14),
      foreground: color,
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Text('$label: $value'),
      ),
    );
  }
}
