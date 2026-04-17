import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../models/control_tower_ticket.dart';
import 'dashboard_helpers.dart';

class TicketsCard extends StatelessWidget {
  const TicketsCard({
    super.key,
    required this.tickets,
  });

  final List<ControlTowerTicket> tickets;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visibleTickets = tickets.take(3).toList(growable: false);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.task_alt_outlined, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Störungen',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Offene Vorgänge mit Priorität.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (visibleTickets.isEmpty)
              Text(
                'Keine offenen Vorgänge.',
                style: textTheme.bodySmall,
              )
            else
              Column(
                children: visibleTickets
                    .map((ticket) => _TicketRow(ticket: ticket))
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket});

  final ControlTowerTicket ticket;

  @override
  Widget build(BuildContext context) {
    final color = ticketSeverityColor(ticket.severity);
    final textTheme = Theme.of(context).textTheme;
    final label = ticketStatusLabel(ticket.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.report_outlined, color: color, size: 16),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ticketTitle(ticket),
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text('Status: $label', style: textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              formatRelativeTime(ticket.createdAt),
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
