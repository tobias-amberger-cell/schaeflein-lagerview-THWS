import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/control_tower_audit_entry.dart';
import '../../../../models/control_tower_event.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/page_section_header.dart';

class ControlTowerScreen extends StatefulWidget {
  const ControlTowerScreen({super.key});

  @override
  State<ControlTowerScreen> createState() => _ControlTowerScreenState();
}

class _ControlTowerScreenState extends State<ControlTowerScreen> {
  static const int _eventPageSize = 10;
  static const int _auditPageSize = 8;
  static const _EventStatusFilter _defaultStatusFilter = _EventStatusFilter.open;
  static const _EventSeverityFilter _defaultSeverityFilter = _EventSeverityFilter.all;
  static const _EventTimeFilter _defaultTimeFilter = _EventTimeFilter.last24Hours;

  _EventStatusFilter _statusFilter = _defaultStatusFilter;
  _EventSeverityFilter _severityFilter = _defaultSeverityFilter;
  _EventTimeFilter _timeFilter = _defaultTimeFilter;
  int _eventVisibleCount = _eventPageSize;
  int _auditVisibleCount = _auditPageSize;
  bool _didRestoreUiState = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppState>();
    if (_didRestoreUiState || !appState.hasLoadedPersistedSettings) {
      return;
    }
    _statusFilter = _statusFilterFromRaw(appState.controlTowerEventStatusFilter);
    _severityFilter = _severityFilterFromRaw(appState.controlTowerEventSeverityFilter);
    _timeFilter = _timeFilterFromRaw(appState.controlTowerEventTimeFilter);
    _eventVisibleCount = appState.controlTowerEventVisibleCount.clamp(1, 200).toInt();
    _auditVisibleCount = appState.controlTowerAuditVisibleCount.clamp(1, 200).toInt();
    _didRestoreUiState = true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final warehouses = appState.warehouses;
    final events = _sortEvents(_filterEvents(appState.controlTowerEvents, appState), appState);
    final openCount = appState.controlTowerEvents
        .where((event) => !appState.isControlTowerEventAcknowledged(event.id))
        .length;
    final escalatedCount = appState.escalatedControlTowerEventCount;
    final overdueTicketCount = appState.overdueControlTowerTicketCount;
    final autoEscalationCount = appState.automaticEscalatedTicketCountLastHour;
    final recentAutoEscalationCount = appState.pendingAutoEscalationAlertCount;
    final auditEntries = appState.controlTowerAuditLog;

    final maintenanceCount =
        warehouses.where((item) => item.status == WarehouseStatus.maintenance).length;
    final totalSlots = warehouses.fold<int>(0, (sum, item) => sum + item.totalStorageSlots);
    final occupiedSlots =
        warehouses.fold<int>(0, (sum, item) => sum + item.occupiedStorageSlots);
    final utilizationPercent = totalSlots == 0 ? 0 : ((occupiedSlots / totalSlots) * 100).round();

    final lastHeartbeat = appState.lastControlTowerHeartbeat ?? DateTime.now();
    final prioritized = <Warehouse>[...warehouses]
      ..sort((a, b) => b.utilizationRatio.compareTo(a.utilizationRatio));

    return ListView(
      children: <Widget>[
        PageSectionHeader(
          title: context.tr('controlTowerTitle'),
          subtitle: context.tr('controlTowerSubtitle'),
        ),
        const SizedBox(height: AppSpacing.md),
        _ControlTowerHeroPanel(
          utilizationPercent: utilizationPercent,
          openEvents: openCount,
          escalatedEvents: escalatedCount,
          delayedTours: appState.delayedToursCount,
          onOpenTickets: () => context.go('/control-tower/tickets?status=open'),
          onOpenTours: () => context.go('/tours'),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: (maintenanceCount > 0 || appState.delayedToursCount > 0)
                  ? Colors.red.withValues(alpha: 0.15)
                  : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.15),
              child: Icon(
                (maintenanceCount > 0 || appState.delayedToursCount > 0)
                    ? Icons.warning_amber_rounded
                    : Icons.hub_rounded,
              ),
            ),
            title: Text(context.tr('controlTowerSystemStatus')),
            subtitle: Text(
              (maintenanceCount > 0 || appState.delayedToursCount > 0)
                  ? context.tr('controlTowerStatusAttention')
                  : context.tr('controlTowerStatusStable'),
            ),
            trailing: Text(
              context.tr(
                appState.isControlTowerFeedActive
                    ? 'controlTowerLiveAt'
                    : 'controlTowerUpdatedAt',
                <String, Object>{'time': _formatTime(lastHeartbeat)},
              ),
            ),
          ),
        ),
        if (recentAutoEscalationCount > 0) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Card(
            color: Colors.deepOrange.withValues(alpha: 0.1),
            child: ListTile(
              leading: const Icon(Icons.notification_important_outlined),
              title: Text(
                context.tr(
                  'controlTowerAutoEscalationAlert',
                  <String, Object>{'count': recentAutoEscalationCount},
                ),
              ),
              subtitle: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  TextButton(
                    onPressed: () =>
                        context.go('/control-tower/tickets?status=open&level=l3'),
                    child: Text(context.tr('controlTowerOpenCriticalTickets')),
                  ),
                  TextButton(
                    onPressed: () {
                      appState.acknowledgeAutoEscalationAlert();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('controlTowerAlertAcknowledged')),
                        ),
                      );
                    },
                    child: Text(context.tr('controlTowerAcknowledgeAlert')),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= AppBreakpoints.desktop
                ? 3
                : constraints.maxWidth >= AppBreakpoints.tablet
                    ? 2
                    : 1;
            final tileWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - (AppSpacing.sm * (columns - 1))) / columns;

            Widget tile(Widget child) => SizedBox(width: tileWidth, child: child);

            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                tile(_kpi(
                  context,
                  context.tr('warehouses'),
                  '${warehouses.length}',
                  Icons.warehouse_outlined,
                )),
                tile(_kpi(
                  context,
                  context.tr('kpiUtilization'),
                  '$utilizationPercent%',
                  Icons.pie_chart_outline_rounded,
                )),
                tile(_kpi(
                  context,
                  context.tr('tourKpiActive'),
                  '${appState.activeToursCount}',
                  Icons.local_shipping_outlined,
                )),
                tile(_kpi(
                  context,
                  context.tr('tourKpiDelayed'),
                  '${appState.delayedToursCount}',
                  Icons.warning_amber_outlined,
                )),
                tile(_kpi(
                  context,
                  context.tr('controlTowerOverdueTickets'),
                  '$overdueTicketCount',
                  Icons.timer_off_outlined,
                  accentColor: overdueTicketCount > 0 ? Colors.red.shade700 : null,
                  onTap: () => context.go('/control-tower/tickets?overdue=true&status=open'),
                )),
                tile(_kpi(
                  context,
                  context.tr('controlTowerAutoEscalations'),
                  '$autoEscalationCount',
                  Icons.trending_up_outlined,
                  accentColor: autoEscalationCount > 0 ? Colors.deepOrange.shade700 : null,
                  onTap: () => context.go('/control-tower/tickets?status=open&level=l3'),
                )),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= AppBreakpoints.tablet;
            final priorities = _PrioritiesCard(warehouses: prioritized.take(4).toList(growable: false));
            final feed = _EventFeedCard(
              events: events,
              openCount: openCount,
              escalatedCount: escalatedCount,
              canAcknowledge: appState.canAcknowledgeControlTowerEvents,
              canEscalate: appState.canEscalateControlTowerEvents,
              statusFilter: _statusFilter,
              severityFilter: _severityFilter,
              timeFilter: _timeFilter,
              isAcknowledged: appState.isControlTowerEventAcknowledged,
              isEscalated: appState.isControlTowerEventEscalated,
              visibleCount: _eventVisibleCount,
              onAcknowledge: (event) => _ack(context, appState, event),
              onEscalate: (event) => _escalate(context, appState, event),
              onAckAll: () => _ackAll(context, appState),
              onLoadMore: () => _loadMoreEvents(events.length),
              onStatusFilterChanged: _updateStatusFilter,
              onSeverityFilterChanged: _updateSeverityFilter,
              onTimeFilterChanged: _updateTimeFilter,
              canResetFilters: _statusFilter != _defaultStatusFilter ||
                  _severityFilter != _defaultSeverityFilter ||
                  _timeFilter != _defaultTimeFilter,
              onResetFilters: _resetEventFilters,
            );

            if (!wide) {
              return Column(
                children: <Widget>[
                  priorities,
                  const SizedBox(height: AppSpacing.md),
                  feed,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: priorities),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: feed),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _ActionsCard(
          canOpenViewer: appState.canUseViewerControls,
          canOpenWarehouses: appState.canManageWarehouses,
          openTicketCount: appState.openControlTowerTicketCount,
          onOpenWarehouses: () => context.go('/warehouses'),
          onOpenViewer: () {
            final selected = appState.selectedWarehouse;
            context.go(selected == null ? '/warehouses' : '/viewer');
          },
          onOpenTickets: () => context.go('/control-tower/tickets'),
          onOpenTours: () => context.go('/tours'),
          onOpenNotifications: () => context.push('/notifications'),
        ),
        const SizedBox(height: AppSpacing.md),
        _AuditLogCard(
          entries: auditEntries,
          visibleCount: _auditVisibleCount,
          onLoadMore: () => _loadMoreAuditEntries(auditEntries.length),
        ),
      ],
    );
  }

  Widget _kpi(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? accentColor,
    VoidCallback? onTap,
  }) {
    final valueStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: accentColor,
          fontWeight: FontWeight.w800,
        );
    final iconColor = accentColor ?? Theme.of(context).colorScheme.primary;

    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (accentColor ?? colorScheme.outlineVariant).withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(value, style: valueStyle),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ControlTowerEvent> _filterEvents(List<ControlTowerEvent> all, AppState appState) {
    final now = DateTime.now();
    return all.where((event) {
      final acknowledged = appState.isControlTowerEventAcknowledged(event.id);
      final escalated = appState.isControlTowerEventEscalated(event.id);
      final matchesStatus = switch (_statusFilter) {
        _EventStatusFilter.open => !acknowledged,
        _EventStatusFilter.acknowledged => acknowledged,
        _EventStatusFilter.escalated => escalated,
        _EventStatusFilter.all => true,
      };
      if (!matchesStatus) {
        return false;
      }
      final matchesSeverity = switch (_severityFilter) {
        _EventSeverityFilter.all => true,
        _EventSeverityFilter.critical => event.severity == ControlTowerEventSeverity.critical,
        _EventSeverityFilter.warning => event.severity == ControlTowerEventSeverity.warning,
        _EventSeverityFilter.info => event.severity == ControlTowerEventSeverity.info,
      };
      if (!matchesSeverity) {
        return false;
      }
      return _matchesTimeWindow(event.createdAt, now);
    }).toList(growable: false);
  }

  bool _matchesTimeWindow(DateTime createdAt, DateTime now) {
    final age = now.difference(createdAt);
    switch (_timeFilter) {
      case _EventTimeFilter.lastHour:
        return age <= const Duration(hours: 1);
      case _EventTimeFilter.last24Hours:
        return age <= const Duration(hours: 24);
      case _EventTimeFilter.last7Days:
        return age <= const Duration(days: 7);
      case _EventTimeFilter.all:
        return true;
    }
  }

  List<ControlTowerEvent> _sortEvents(List<ControlTowerEvent> input, AppState appState) {
    final events = <ControlTowerEvent>[...input];
    events.sort((a, b) {
      final escalatedA = appState.isControlTowerEventEscalated(a.id);
      final escalatedB = appState.isControlTowerEventEscalated(b.id);
      if (escalatedA != escalatedB) {
        return escalatedA ? -1 : 1;
      }
      final severityA = _severityWeight(a.severity);
      final severityB = _severityWeight(b.severity);
      if (severityA != severityB) {
        return severityB.compareTo(severityA);
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return events;
  }

  void _ack(BuildContext context, AppState appState, ControlTowerEvent event) {
    final ok = appState.acknowledgeControlTowerEvent(event.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.tr(
                  'controlTowerEventAcknowledgedMsg',
                  <String, Object>{'title': context.tr(event.titleKey)},
                )
              : context.tr('controlTowerAcknowledgeNoPermission'),
        ),
      ),
    );
  }

  void _ackAll(BuildContext context, AppState appState) {
    final count = appState.acknowledgeAllControlTowerEvents();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? context.tr('controlTowerAllAcknowledgedMsg', <String, Object>{'count': count})
              : context.tr('controlTowerAcknowledgeNoPermission'),
        ),
      ),
    );
  }

  void _escalate(BuildContext context, AppState appState, ControlTowerEvent event) {
    final ok = appState.escalateControlTowerEvent(event.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.tr(
                  'controlTowerEventEscalatedMsg',
                  <String, Object>{'title': context.tr(event.titleKey)},
                )
              : context.tr('controlTowerEscalateNoPermission'),
        ),
      ),
    );
  }

  int _severityWeight(ControlTowerEventSeverity severity) {
    switch (severity) {
      case ControlTowerEventSeverity.info:
        return 1;
      case ControlTowerEventSeverity.warning:
        return 2;
      case ControlTowerEventSeverity.critical:
        return 3;
    }
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _updateStatusFilter(_EventStatusFilter value) {
    if (_statusFilter == value) {
      return;
    }
    setState(() {
      _statusFilter = value;
      _eventVisibleCount = _eventPageSize;
    });
    _persistControlTowerUiState();
  }

  void _updateSeverityFilter(_EventSeverityFilter value) {
    if (_severityFilter == value) {
      return;
    }
    setState(() {
      _severityFilter = value;
      _eventVisibleCount = _eventPageSize;
    });
    _persistControlTowerUiState();
  }

  void _updateTimeFilter(_EventTimeFilter value) {
    if (_timeFilter == value) {
      return;
    }
    setState(() {
      _timeFilter = value;
      _eventVisibleCount = _eventPageSize;
    });
    _persistControlTowerUiState();
  }

  void _loadMoreEvents(int totalCount) {
    if (_eventVisibleCount >= totalCount) {
      return;
    }
    setState(() {
      _eventVisibleCount = (_eventVisibleCount + _eventPageSize).clamp(0, totalCount);
    });
    _persistControlTowerUiState();
  }

  void _resetEventFilters() {
    if (_statusFilter == _defaultStatusFilter &&
        _severityFilter == _defaultSeverityFilter &&
        _timeFilter == _defaultTimeFilter &&
        _eventVisibleCount == _eventPageSize) {
      return;
    }
    setState(() {
      _statusFilter = _defaultStatusFilter;
      _severityFilter = _defaultSeverityFilter;
      _timeFilter = _defaultTimeFilter;
      _eventVisibleCount = _eventPageSize;
    });
    _persistControlTowerUiState();
  }

  void _loadMoreAuditEntries(int totalCount) {
    if (_auditVisibleCount >= totalCount) {
      return;
    }
    setState(() {
      _auditVisibleCount = (_auditVisibleCount + _auditPageSize).clamp(0, totalCount);
    });
    _persistControlTowerUiState();
  }

  void _persistControlTowerUiState() {
    context.read<AppState>().setControlTowerUiState(
          eventStatusFilter: _statusFilterRaw(_statusFilter),
          eventSeverityFilter: _severityFilterRaw(_severityFilter),
          eventTimeFilter: _timeFilterRaw(_timeFilter),
          eventVisibleCount: _eventVisibleCount,
          auditVisibleCount: _auditVisibleCount,
        );
  }

  _EventStatusFilter _statusFilterFromRaw(String raw) {
    switch (raw) {
      case 'open':
        return _EventStatusFilter.open;
      case 'acknowledged':
        return _EventStatusFilter.acknowledged;
      case 'escalated':
        return _EventStatusFilter.escalated;
      case 'all':
        return _EventStatusFilter.all;
      default:
        return _defaultStatusFilter;
    }
  }

  _EventSeverityFilter _severityFilterFromRaw(String raw) {
    switch (raw) {
      case 'critical':
        return _EventSeverityFilter.critical;
      case 'warning':
        return _EventSeverityFilter.warning;
      case 'info':
        return _EventSeverityFilter.info;
      case 'all':
        return _EventSeverityFilter.all;
      default:
        return _defaultSeverityFilter;
    }
  }

  _EventTimeFilter _timeFilterFromRaw(String raw) {
    switch (raw) {
      case 'lastHour':
        return _EventTimeFilter.lastHour;
      case 'last24Hours':
        return _EventTimeFilter.last24Hours;
      case 'last7Days':
        return _EventTimeFilter.last7Days;
      case 'all':
        return _EventTimeFilter.all;
      default:
        return _defaultTimeFilter;
    }
  }

  String _statusFilterRaw(_EventStatusFilter value) {
    switch (value) {
      case _EventStatusFilter.open:
        return 'open';
      case _EventStatusFilter.acknowledged:
        return 'acknowledged';
      case _EventStatusFilter.escalated:
        return 'escalated';
      case _EventStatusFilter.all:
        return 'all';
    }
  }

  String _severityFilterRaw(_EventSeverityFilter value) {
    switch (value) {
      case _EventSeverityFilter.all:
        return 'all';
      case _EventSeverityFilter.critical:
        return 'critical';
      case _EventSeverityFilter.warning:
        return 'warning';
      case _EventSeverityFilter.info:
        return 'info';
    }
  }

  String _timeFilterRaw(_EventTimeFilter value) {
    switch (value) {
      case _EventTimeFilter.lastHour:
        return 'lastHour';
      case _EventTimeFilter.last24Hours:
        return 'last24Hours';
      case _EventTimeFilter.last7Days:
        return 'last7Days';
      case _EventTimeFilter.all:
        return 'all';
    }
  }
}

class _PrioritiesCard extends StatelessWidget {
  const _PrioritiesCard({required this.warehouses});

  final List<Warehouse> warehouses;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.tr('controlTowerPriorityTitle'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            if (warehouses.isEmpty)
              Text(context.tr('noWarehouseData'))
            else
              ...warehouses.map(
                (warehouse) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(warehouse.name),
                  subtitle: Text(warehouse.location),
                  trailing: Text('${warehouse.utilizationPercent}%'),
                  onTap: () => context.go('/warehouses/${warehouse.id}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventFeedCard extends StatelessWidget {
  const _EventFeedCard({
    required this.events,
    required this.openCount,
    required this.escalatedCount,
    required this.canAcknowledge,
    required this.canEscalate,
    required this.statusFilter,
    required this.severityFilter,
    required this.timeFilter,
    required this.isAcknowledged,
    required this.isEscalated,
    required this.visibleCount,
    required this.onAcknowledge,
    required this.onEscalate,
    required this.onAckAll,
    required this.onLoadMore,
    required this.onStatusFilterChanged,
    required this.onSeverityFilterChanged,
    required this.onTimeFilterChanged,
    required this.canResetFilters,
    required this.onResetFilters,
  });

  final List<ControlTowerEvent> events;
  final int openCount;
  final int escalatedCount;
  final bool canAcknowledge;
  final bool canEscalate;
  final _EventStatusFilter statusFilter;
  final _EventSeverityFilter severityFilter;
  final _EventTimeFilter timeFilter;
  final bool Function(String eventId) isAcknowledged;
  final bool Function(String eventId) isEscalated;
  final int visibleCount;
  final ValueChanged<ControlTowerEvent> onAcknowledge;
  final ValueChanged<ControlTowerEvent> onEscalate;
  final VoidCallback onAckAll;
  final VoidCallback onLoadMore;
  final ValueChanged<_EventStatusFilter> onStatusFilterChanged;
  final ValueChanged<_EventSeverityFilter> onSeverityFilterChanged;
  final ValueChanged<_EventTimeFilter> onTimeFilterChanged;
  final bool canResetFilters;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    final safeVisibleCount = visibleCount < 1 ? 1 : visibleCount;
    final visibleEvents = events.take(safeVisibleCount).toList(growable: false);
    final hasMore = visibleEvents.length < events.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    context.tr('controlTowerEventsTitle'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    TextButton(
                      onPressed: canAcknowledge && openCount > 0 ? onAckAll : null,
                      child: Text(context.tr('controlTowerAcknowledgeAll')),
                    ),
                    TextButton.icon(
                      onPressed: canResetFilters ? onResetFilters : null,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: Text(context.tr('filtersReset')),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              context.tr(
                'controlTowerEventsOpenEscalatedCount',
                <String, Object>{
                  'open': openCount,
                  'escalated': escalatedCount,
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Filter',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('Status', style: Theme.of(context).textTheme.labelSmall),
                ChoiceChip(label: Text(context.tr('eventFilterOpen')), selected: statusFilter == _EventStatusFilter.open, onSelected: (_) => onStatusFilterChanged(_EventStatusFilter.open)),
                ChoiceChip(label: Text(context.tr('eventFilterAcknowledged')), selected: statusFilter == _EventStatusFilter.acknowledged, onSelected: (_) => onStatusFilterChanged(_EventStatusFilter.acknowledged)),
                ChoiceChip(label: Text(context.tr('eventFilterEscalated')), selected: statusFilter == _EventStatusFilter.escalated, onSelected: (_) => onStatusFilterChanged(_EventStatusFilter.escalated)),
                ChoiceChip(label: Text(context.tr('eventFilterAll')), selected: statusFilter == _EventStatusFilter.all, onSelected: (_) => onStatusFilterChanged(_EventStatusFilter.all)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('Priorität', style: Theme.of(context).textTheme.labelSmall),
                ChoiceChip(label: Text(context.tr('all')), selected: severityFilter == _EventSeverityFilter.all, onSelected: (_) => onSeverityFilterChanged(_EventSeverityFilter.all)),
                ChoiceChip(label: Text(context.tr('severityCritical')), selected: severityFilter == _EventSeverityFilter.critical, onSelected: (_) => onSeverityFilterChanged(_EventSeverityFilter.critical)),
                ChoiceChip(label: Text(context.tr('severityWarning')), selected: severityFilter == _EventSeverityFilter.warning, onSelected: (_) => onSeverityFilterChanged(_EventSeverityFilter.warning)),
                ChoiceChip(label: Text(context.tr('severityInfo')), selected: severityFilter == _EventSeverityFilter.info, onSelected: (_) => onSeverityFilterChanged(_EventSeverityFilter.info)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('Zeitraum', style: Theme.of(context).textTheme.labelSmall),
                ChoiceChip(label: const Text('1h'), selected: timeFilter == _EventTimeFilter.lastHour, onSelected: (_) => onTimeFilterChanged(_EventTimeFilter.lastHour)),
                ChoiceChip(label: const Text('24h'), selected: timeFilter == _EventTimeFilter.last24Hours, onSelected: (_) => onTimeFilterChanged(_EventTimeFilter.last24Hours)),
                ChoiceChip(label: const Text('7 Tage'), selected: timeFilter == _EventTimeFilter.last7Days, onSelected: (_) => onTimeFilterChanged(_EventTimeFilter.last7Days)),
                ChoiceChip(label: const Text('Alle Zeiträume'), selected: timeFilter == _EventTimeFilter.all, onSelected: (_) => onTimeFilterChanged(_EventTimeFilter.all)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (events.isEmpty)
              Text(context.tr('controlTowerNoFilteredEvents'))
            else
              ...visibleEvents.map(
                (event) => _EventListTile(
                  event: event,
                  isAcknowledged: isAcknowledged(event.id),
                  isEscalated: isEscalated(event.id),
                  canAcknowledge: canAcknowledge,
                  canEscalate: canEscalate,
                  onStatusFilterRequested: onStatusFilterChanged,
                  onSeverityFilterRequested: onSeverityFilterChanged,
                  onAcknowledge: () => onAcknowledge(event),
                  onEscalate: () => onEscalate(event),
                ),
              ),
            if (hasMore) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text('Mehr laden (${visibleEvents.length}/${events.length})'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}

class _EventListTile extends StatelessWidget {
  const _EventListTile({
    required this.event,
    required this.isAcknowledged,
    required this.isEscalated,
    required this.canAcknowledge,
    required this.canEscalate,
    required this.onStatusFilterRequested,
    required this.onSeverityFilterRequested,
    required this.onAcknowledge,
    required this.onEscalate,
  });

  final ControlTowerEvent event;
  final bool isAcknowledged;
  final bool isEscalated;
  final bool canAcknowledge;
  final bool canEscalate;
  final ValueChanged<_EventStatusFilter> onStatusFilterRequested;
  final ValueChanged<_EventSeverityFilter> onSeverityFilterRequested;
  final VoidCallback onAcknowledge;
  final VoidCallback onEscalate;

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(event.severity);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: severityColor.withValues(alpha: 0.14),
        child: Icon(_iconFor(event.type), color: severityColor, size: 18),
      ),
      title: Text(context.tr(event.titleKey)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.tr(event.messageKey, event.messageParams)),
          const SizedBox(height: 4),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _InlineBadge(
                label: _severityLabel(context, event.severity),
                background: severityColor.withValues(alpha: 0.14),
                foreground: severityColor,
                onTap: () => onSeverityFilterRequested(_severityFilterValue(event.severity)),
              ),
              _SlaBadge(event: event),
              if (isEscalated)
                _InlineBadge(
                  label: context.tr('eventEscalated'),
                  background: Colors.red.withValues(alpha: 0.14),
                  foreground: Colors.red.shade800,
                  onTap: () => onStatusFilterRequested(_EventStatusFilter.escalated),
                ),
              if (!isAcknowledged && !isEscalated)
                _InlineBadge(
                  label: context.tr('eventFilterOpen'),
                  background: Colors.orange.withValues(alpha: 0.14),
                  foreground: Colors.orange.shade800,
                  onTap: () => onStatusFilterRequested(_EventStatusFilter.open),
                ),
              if (isAcknowledged)
                _InlineBadge(
                  label: context.tr('eventAcknowledged'),
                  background: Colors.green.withValues(alpha: 0.14),
                  foreground: Colors.green.shade800,
                  onTap: () => onStatusFilterRequested(_EventStatusFilter.acknowledged),
                ),
              _InlineBadge(
                label: _relativeTime(event.createdAt),
                background: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.8),
                foreground: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
      trailing: Wrap(
        children: <Widget>[
          PopupMenuButton<_EventAction>(
            enabled: (!isEscalated && canEscalate) || (!isAcknowledged && canAcknowledge),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == _EventAction.escalate) {
                onEscalate();
              } else if (value == _EventAction.acknowledge) {
                onAcknowledge();
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<_EventAction>>[
              if (!isEscalated)
                PopupMenuItem<_EventAction>(
                  value: _EventAction.escalate,
                  child: Text(context.tr('eventEscalate')),
                ),
              if (!isAcknowledged)
                PopupMenuItem<_EventAction>(
                  value: _EventAction.acknowledge,
                  child: Text(context.tr('eventAcknowledge')),
                ),
            ],
          ),
        ],
      ),
      onTap: () => _openRelatedPage(context),
    );
  }

  Color _severityColor(ControlTowerEventSeverity severity) {
    switch (severity) {
      case ControlTowerEventSeverity.critical:
        return Colors.red.shade800;
      case ControlTowerEventSeverity.warning:
        return Colors.orange.shade800;
      case ControlTowerEventSeverity.info:
        return Colors.blue.shade800;
    }
  }

  String _severityLabel(BuildContext context, ControlTowerEventSeverity severity) {
    switch (severity) {
      case ControlTowerEventSeverity.critical:
        return context.tr('severityCritical');
      case ControlTowerEventSeverity.warning:
        return context.tr('severityWarning');
      case ControlTowerEventSeverity.info:
        return context.tr('severityInfo');
    }
  }

  _EventSeverityFilter _severityFilterValue(ControlTowerEventSeverity severity) {
    switch (severity) {
      case ControlTowerEventSeverity.critical:
        return _EventSeverityFilter.critical;
      case ControlTowerEventSeverity.warning:
        return _EventSeverityFilter.warning;
      case ControlTowerEventSeverity.info:
        return _EventSeverityFilter.info;
    }
  }

  String _relativeTime(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) {
      return 'gerade eben';
    }
    if (diff.inMinutes < 60) {
      return 'vor ${diff.inMinutes} Min';
    }
    if (diff.inHours < 24) {
      return 'vor ${diff.inHours} Std';
    }
    return 'vor ${diff.inDays} T';
  }

  IconData _iconFor(ControlTowerEventType type) {
    switch (type) {
      case ControlTowerEventType.warehouse:
        return Icons.warehouse_outlined;
      case ControlTowerEventType.tour:
        return Icons.local_shipping_outlined;
      case ControlTowerEventType.ramp:
        return Icons.alt_route_outlined;
      case ControlTowerEventType.inventory:
        return Icons.inventory_2_outlined;
    }
  }

  void _openRelatedPage(BuildContext context) {
    if (event.type == ControlTowerEventType.tour || event.type == ControlTowerEventType.ramp) {
      context.go('/tours');
      return;
    }
    if (event.warehouseId != null) {
      context.go('/warehouses/${event.warehouseId}');
      return;
    }
    context.push('/notifications');
  }
}

class _SlaBadge extends StatelessWidget {
  const _SlaBadge({required this.event});

  final ControlTowerEvent event;

  @override
  Widget build(BuildContext context) {
    final deadline = _deadlineFor(event);
    final diff = deadline.difference(DateTime.now());
    final isBreached = diff.isNegative;

    final text = isBreached
        ? context.tr(
            'eventSlaBreached',
            <String, Object>{'minutes': diff.inMinutes.abs()},
          )
        : context.tr(
            'eventSlaDueIn',
            <String, Object>{'minutes': diff.inMinutes},
          );
    final background = isBreached
        ? Colors.red.withValues(alpha: 0.14)
        : Colors.orange.withValues(alpha: 0.14);
    final foreground = isBreached ? Colors.red.shade800 : Colors.orange.shade800;

    return _InlineBadge(
      label: text,
      background: background,
      foreground: foreground,
    );
  }

  DateTime _deadlineFor(ControlTowerEvent event) {
    final minutes = switch (event.severity) {
      ControlTowerEventSeverity.critical => 15,
      ControlTowerEventSeverity.warning => 45,
      ControlTowerEventSeverity.info => 120,
    };
    return event.createdAt.add(Duration(minutes: minutes));
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({
    required this.label,
    required this.background,
    required this.foreground,
    this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );

    if (onTap == null) {
      return badge;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: badge,
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.onOpenWarehouses,
    required this.onOpenViewer,
    required this.onOpenTickets,
    required this.onOpenNotifications,
    required this.onOpenTours,
    required this.canOpenWarehouses,
    required this.canOpenViewer,
    required this.openTicketCount,
  });

  final VoidCallback onOpenWarehouses;
  final VoidCallback onOpenViewer;
  final VoidCallback onOpenTickets;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenTours;
  final bool canOpenWarehouses;
  final bool canOpenViewer;
  final int openTicketCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('controlTowerActionsTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: canOpenWarehouses ? onOpenWarehouses : null,
                  icon: const Icon(Icons.warehouse_outlined),
                  label: Text(context.tr('controlTowerOpenWarehouses')),
                ),
                FilledButton.tonalIcon(
                  onPressed: canOpenViewer ? onOpenViewer : null,
                  icon: const Icon(Icons.view_in_ar_outlined),
                  label: Text(context.tr('controlTowerOpenViewer')),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenTickets,
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: Text(
                    context.tr(
                      'controlTowerOpenTickets',
                      <String, Object>{'count': openTicketCount},
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenTours,
                  icon: const Icon(Icons.route_outlined),
                  label: Text(context.tr('controlTowerOpenTours')),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenNotifications,
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(context.tr('controlTowerOpenNotifications')),
                ),
              ],
            ),
            if (!canOpenWarehouses || !canOpenViewer) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.tr('controlTowerActionPermissionHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({
    required this.entries,
    required this.visibleCount,
    required this.onLoadMore,
  });

  final List<ControlTowerAuditEntry> entries;
  final int visibleCount;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final safeVisibleCount = visibleCount < 1 ? 1 : visibleCount;
    final visibleEntries = entries.take(safeVisibleCount).toList(growable: false);
    final hasMore = visibleEntries.length < entries.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('controlTowerAuditTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('controlTowerAuditSubtitle'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (entries.isEmpty)
              Text(context.tr('controlTowerAuditEmpty'))
            else
              ...visibleEntries.map(
                (entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_iconFor(entry.action), size: 18),
                  title: Text(_titleFor(context, entry)),
                  subtitle: Text(
                    context.tr(
                      'controlTowerAuditLine',
                      <String, Object>{
                        'action': context.tr(entry.action.labelKey),
                        'user': entry.actorName,
                        'time': _relativeTime(context, entry.createdAt),
                      },
                    ),
                  ),
                ),
              ),
            if (hasMore)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    'Mehr Protokoll laden (${visibleEntries.length}/${entries.length})',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _titleFor(BuildContext context, ControlTowerAuditEntry entry) {
    if (entry.action == ControlTowerAuditAction.acknowledgedAll) {
      return context.tr(
        'controlTowerAuditBulkAcknowledgeTitle',
        <String, Object>{'count': entry.count ?? 0},
      );
    }
    if (entry.eventTitleKey != null) {
      return context.tr(entry.eventTitleKey!);
    }
    return context.tr('controlTowerEventsTitle');
  }

  IconData _iconFor(ControlTowerAuditAction action) {
    switch (action) {
      case ControlTowerAuditAction.acknowledged:
        return Icons.check_circle_outline;
      case ControlTowerAuditAction.escalated:
        return Icons.priority_high;
      case ControlTowerAuditAction.acknowledgedAll:
        return Icons.done_all_outlined;
    }
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

enum _EventStatusFilter { open, acknowledged, escalated, all }

enum _EventSeverityFilter { all, critical, warning, info }

enum _EventTimeFilter { lastHour, last24Hours, last7Days, all }

enum _EventAction { escalate, acknowledge }

class _ControlTowerHeroPanel extends StatelessWidget {
  const _ControlTowerHeroPanel({
    required this.utilizationPercent,
    required this.openEvents,
    required this.escalatedEvents,
    required this.delayedTours,
    required this.onOpenTickets,
    required this.onOpenTours,
  });

  final int utilizationPercent;
  final int openEvents;
  final int escalatedEvents;
  final int delayedTours;
  final VoidCallback onOpenTickets;
  final VoidCallback onOpenTours;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primary.withValues(alpha: 0.16),
            colorScheme.tertiary.withValues(alpha: 0.12),
            colorScheme.surface,
          ],
        ),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _ControlTowerHeroChip(
                  icon: Icons.pie_chart_outline_rounded,
                  label: context.tr('kpiUtilization'),
                  value: '$utilizationPercent%',
                ),
                _ControlTowerHeroChip(
                  icon: Icons.notifications_active_outlined,
                  label: context.tr('eventFilterOpen'),
                  value: '$openEvents',
                ),
                _ControlTowerHeroChip(
                  icon: Icons.priority_high_rounded,
                  label: context.tr('eventEscalated'),
                  value: '$escalatedEvents',
                ),
                _ControlTowerHeroChip(
                  icon: Icons.route_outlined,
                  label: context.tr('tourStatusDelayed'),
                  value: '$delayedTours',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: onOpenTickets,
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: Text(context.tr('controlTowerTicketsTitle')),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenTours,
                  icon: const Icon(Icons.route_outlined),
                  label: Text(context.tr('controlTowerOpenTours')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlTowerHeroChip extends StatelessWidget {
  const _ControlTowerHeroChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 124, maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      value,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
