import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/control_tower_event.dart';
import '../../../../models/control_tower_ticket.dart';
import '../../../../shared/widgets/empty_state.dart';

class ControlTowerTicketsScreen extends StatefulWidget {
  const ControlTowerTicketsScreen({super.key});

  @override
  State<ControlTowerTicketsScreen> createState() => _ControlTowerTicketsScreenState();
}

enum _TicketSortMode {
  sla,
  escalation,
  newest,
}

extension on _TicketSortMode {
  String get labelKey {
    switch (this) {
      case _TicketSortMode.sla:
        return 'ticketSortSla';
      case _TicketSortMode.escalation:
        return 'ticketSortEscalation';
      case _TicketSortMode.newest:
        return 'ticketSortNewest';
    }
  }

  String get queryValue {
    switch (this) {
      case _TicketSortMode.sla:
        return 'sla';
      case _TicketSortMode.escalation:
        return 'escalation';
      case _TicketSortMode.newest:
        return 'newest';
    }
  }
}

class _ControlTowerTicketsScreenState extends State<ControlTowerTicketsScreen> {
  static const String _ticketsPath = '/control-tower/tickets';

  final TextEditingController _searchController = TextEditingController();
  ControlTowerTicketStatus? _statusFilter;
  ControlTowerTicketEscalationLevel? _escalationLevelFilter;
  bool _overdueOnly = false;
  bool _escalatedOnly = false;
  bool _criticalOnly = false;
  String? _warehouseIdFilter;
  _TicketSortMode _sortMode = _TicketSortMode.sla;
  String? _lastAppliedQuerySignature;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    final signature = uri.query;
    if (_lastAppliedQuerySignature == signature) {
      return;
    }
    _lastAppliedQuerySignature = signature;
    _applyQueryFilters(uri.queryParameters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tickets = _filteredTickets(appState);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= AppBreakpoints.tablet;
        final useWideToolbar = isTablet && constraints.maxWidth >= 980;
        final activeFilters = _activeFilterLabels(
          context,
          compact: !isTablet,
        );

        return ListView(
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                Text(
                  context.tr('controlTowerTicketsTitle'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.go('/control-tower'),
                  icon: const Icon(Icons.hub_outlined),
                  label: Text(context.tr('controlTower')),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr(
                'controlTowerTicketsCount',
                <String, Object>{
                  'open': appState.openControlTowerTicketCount,
                  'all': appState.controlTowerTickets.length,
                  'overdue': appState.overdueControlTowerTicketCount,
                },
              ),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            if (useWideToolbar)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: _buildSearchField(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 4,
                    child: _buildFilters(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 220,
                    child: _buildSortSelector(context, compact: false),
                  ),
                ],
              )
            else ...<Widget>[
              _buildSearchField(context),
              const SizedBox(height: AppSpacing.sm),
              _buildSortSelector(context, compact: true),
              const SizedBox(height: AppSpacing.sm),
              _buildFilters(context),
            ],
            if (activeFilters.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: activeFilters
                              .map((label) => Chip(label: Text(label)))
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      if (!isTablet)
                        IconButton(
                          onPressed: _resetAllFilters,
                          tooltip: context.tr('filtersReset'),
                          icon: const Icon(Icons.filter_alt_off_outlined),
                        )
                      else
                        TextButton.icon(
                          onPressed: _resetAllFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: Text(context.tr('filtersReset')),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (tickets.isEmpty)
              EmptyState(
                icon: Icons.support_agent_outlined,
                title: context.tr('controlTowerTicketsEmptyTitle'),
                message: context.tr('controlTowerTicketsEmptyMessage'),
              )
            else
              ...tickets.map((ticket) => _TicketCard(ticket: ticket)),
          ],
        );
      },
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: context.tr('controlTowerTicketsSearchHint'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
                icon: const Icon(Icons.clear),
              ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        ChoiceChip(
          label: Text(context.tr('all')),
          selected: _statusFilter == null,
          onSelected: (_) => _setStatusFilter(null),
        ),
        ...ControlTowerTicketStatus.values.map(
          (status) => ChoiceChip(
            label: Text(context.tr(status.labelKey)),
            selected: _statusFilter == status,
            onSelected: (_) => _setStatusFilter(status),
          ),
        ),
        ChoiceChip(
          label: Text(context.tr('ticketEscalationAll')),
          selected: _escalationLevelFilter == null,
          onSelected: (_) => _setEscalationLevelFilter(null),
        ),
        ...ControlTowerTicketEscalationLevel.values.map(
          (level) => ChoiceChip(
            label: Text(context.tr(level.labelKey)),
            selected: _escalationLevelFilter == level,
            onSelected: (_) => _setEscalationLevelFilter(level),
          ),
        ),
        FilterChip(
          label: Text(context.tr('ticketOverdueOnly')),
          selected: _overdueOnly,
          onSelected: _setOverdueOnly,
        ),
        FilterChip(
          label: Text(context.tr('eventEscalated')),
          selected: _escalatedOnly,
          onSelected: _setEscalatedOnly,
        ),
        FilterChip(
          label: Text(context.tr('ticketCriticalOnly')),
          selected: _criticalOnly,
          onSelected: _setCriticalOnly,
        ),
      ],
    );
  }

  Widget _buildSortSelector(
    BuildContext context, {
    required bool compact,
  }) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('ticketSortLabel'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<_TicketSortMode>(
            showSelectedIcon: false,
            segments: <ButtonSegment<_TicketSortMode>>[
              ButtonSegment<_TicketSortMode>(
                value: _TicketSortMode.sla,
                label: Text(context.tr('ticketSortSlaShort')),
                icon: const Icon(Icons.schedule_outlined, size: 16),
              ),
              ButtonSegment<_TicketSortMode>(
                value: _TicketSortMode.escalation,
                label: Text(context.tr('ticketSortEscalationShort')),
                icon: const Icon(Icons.trending_up_rounded, size: 16),
              ),
              ButtonSegment<_TicketSortMode>(
                value: _TicketSortMode.newest,
                label: Text(context.tr('ticketSortNewestShort')),
                icon: const Icon(Icons.fiber_new_rounded, size: 16),
              ),
            ],
            selected: <_TicketSortMode>{_sortMode},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) {
                return;
              }
              _setSortMode(selection.first);
            },
          ),
        ],
      );
    }

    return DropdownButtonFormField<_TicketSortMode>(
      initialValue: _sortMode,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.tr('ticketSortLabel'),
        prefixIcon: const Icon(Icons.swap_vert_rounded),
      ),
      items: _TicketSortMode.values
          .map(
            (mode) => DropdownMenuItem<_TicketSortMode>(
              value: mode,
              child: Text(context.tr(mode.labelKey)),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        _setSortMode(value);
      },
    );
  }

  List<ControlTowerTicket> _filteredTickets(AppState appState) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final filtered = appState.controlTowerTickets.where((ticket) {
      final matchesStatus = _statusFilter == null || ticket.status == _statusFilter;
      if (!matchesStatus) {
        return false;
      }
      final matchesEscalation =
          _escalationLevelFilter == null ||
          ticket.escalationLevel == _escalationLevelFilter;
      if (!matchesEscalation) {
        return false;
      }

      if (_overdueOnly && !ticket.isSlaBreachedAt(now)) {
        return false;
      }
      if (_escalatedOnly &&
          ticket.escalationLevel == ControlTowerTicketEscalationLevel.level1) {
        return false;
      }
      if (_criticalOnly && !_isCriticalTicket(ticket, now)) {
        return false;
      }
      if (_warehouseIdFilter != null && ticket.warehouseId != _warehouseIdFilter) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }
      final title = ticket.titleKey.toLowerCase();
      final assignee = (ticket.assignee ?? '').toLowerCase();
      final message = ticket.messageParams.values.join(' ').toLowerCase();
      return title.contains(query) || assignee.contains(query) || message.contains(query);
    }).toList(growable: false);

    filtered.sort((a, b) {
      final statusCompare = _statusRank(a.status).compareTo(_statusRank(b.status));
      if (statusCompare != 0) {
        return statusCompare;
      }
      switch (_sortMode) {
        case _TicketSortMode.sla:
          return _compareBySla(a, b, now);
        case _TicketSortMode.escalation:
          return _compareByEscalation(a, b, now);
        case _TicketSortMode.newest:
          return _compareByNewest(a, b, now);
      }
    });
    return filtered;
  }

  int _compareBySla(
    ControlTowerTicket a,
    ControlTowerTicket b,
    DateTime now,
  ) {
    final breachedA = a.isSlaBreachedAt(now);
    final breachedB = b.isSlaBreachedAt(now);
    if (breachedA != breachedB) {
      return breachedA ? -1 : 1;
    }
    final deltaA = a.slaDeltaMinutesAt(now);
    final deltaB = b.slaDeltaMinutesAt(now);
    if (deltaA != deltaB) {
      return deltaA.compareTo(deltaB);
    }
    final escalationA = _escalationWeight(a.escalationLevel);
    final escalationB = _escalationWeight(b.escalationLevel);
    if (escalationA != escalationB) {
      return escalationB.compareTo(escalationA);
    }
    final severityA = _severityWeight(a.severity);
    final severityB = _severityWeight(b.severity);
    if (severityA != severityB) {
      return severityB.compareTo(severityA);
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  int _compareByEscalation(
    ControlTowerTicket a,
    ControlTowerTicket b,
    DateTime now,
  ) {
    final escalationA = _escalationWeight(a.escalationLevel);
    final escalationB = _escalationWeight(b.escalationLevel);
    if (escalationA != escalationB) {
      return escalationB.compareTo(escalationA);
    }
    final severityA = _severityWeight(a.severity);
    final severityB = _severityWeight(b.severity);
    if (severityA != severityB) {
      return severityB.compareTo(severityA);
    }
    final breachedA = a.isSlaBreachedAt(now);
    final breachedB = b.isSlaBreachedAt(now);
    if (breachedA != breachedB) {
      return breachedA ? -1 : 1;
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  int _compareByNewest(
    ControlTowerTicket a,
    ControlTowerTicket b,
    DateTime now,
  ) {
    final newestCompare = b.createdAt.compareTo(a.createdAt);
    if (newestCompare != 0) {
      return newestCompare;
    }
    final breachedA = a.isSlaBreachedAt(now);
    final breachedB = b.isSlaBreachedAt(now);
    if (breachedA != breachedB) {
      return breachedA ? -1 : 1;
    }
    return _severityWeight(b.severity).compareTo(_severityWeight(a.severity));
  }

  int _statusRank(ControlTowerTicketStatus status) {
    switch (status) {
      case ControlTowerTicketStatus.open:
        return 0;
      case ControlTowerTicketStatus.inProgress:
        return 1;
      case ControlTowerTicketStatus.resolved:
        return 2;
    }
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

  int _escalationWeight(ControlTowerTicketEscalationLevel level) {
    switch (level) {
      case ControlTowerTicketEscalationLevel.level1:
        return 1;
      case ControlTowerTicketEscalationLevel.level2:
        return 2;
      case ControlTowerTicketEscalationLevel.level3:
        return 3;
    }
  }

  void _applyQueryFilters(Map<String, String> params) {
    _overdueOnly = _parseBool(params['overdue']) ?? false;
    _escalatedOnly = _parseBool(params['escalated']) ?? false;
    _criticalOnly = _parseBool(params['critical']) ?? false;
    _statusFilter = _parseStatus(params['status']);
    _escalationLevelFilter = _parseEscalationLevel(params['level']);
    _warehouseIdFilter = _parseWarehouseId(params['warehouse']);
    _sortMode = _parseSortMode(params['sort']);
    final queryText = (params['q'] ?? '').trim();
    _searchController.value = TextEditingValue(
      text: queryText,
      selection: TextSelection.collapsed(offset: queryText.length),
    );
  }

  bool? _parseBool(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return null;
  }

  ControlTowerTicketStatus? _parseStatus(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    switch (value.trim().toLowerCase()) {
      case 'open':
        return ControlTowerTicketStatus.open;
      case 'inprogress':
      case 'in_progress':
        return ControlTowerTicketStatus.inProgress;
      case 'resolved':
        return ControlTowerTicketStatus.resolved;
      default:
        return null;
    }
  }

  ControlTowerTicketEscalationLevel? _parseEscalationLevel(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    switch (value.trim().toLowerCase()) {
      case 'l1':
      case 'level1':
        return ControlTowerTicketEscalationLevel.level1;
      case 'l2':
      case 'level2':
        return ControlTowerTicketEscalationLevel.level2;
      case 'l3':
      case 'level3':
        return ControlTowerTicketEscalationLevel.level3;
      default:
        return null;
    }
  }

  String? _parseWarehouseId(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  _TicketSortMode _parseSortMode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _TicketSortMode.sla;
    }
    switch (value.trim().toLowerCase()) {
      case 'escalation':
      case 'level':
        return _TicketSortMode.escalation;
      case 'newest':
      case 'latest':
        return _TicketSortMode.newest;
      case 'sla':
      default:
        return _TicketSortMode.sla;
    }
  }

  List<String> _activeFilterLabels(
    BuildContext context, {
    required bool compact,
  }) {
    final labels = <String>[];
    if (_statusFilter != null) {
      labels.add(context.tr(_statusFilter!.labelKey));
    }
    if (_escalationLevelFilter != null) {
      labels.add(context.tr(_escalationLevelFilter!.labelKey));
    }
    if (_overdueOnly) {
      labels.add(compact ? 'SLA+' : context.tr('ticketOverdueOnly'));
    }
    if (_escalatedOnly) {
      labels.add(context.tr('eventEscalated'));
    }
    if (_criticalOnly) {
      labels.add(context.tr('ticketCriticalOnly'));
    }
    if (_warehouseIdFilter != null) {
      labels.add(compact
          ? 'W: $_warehouseIdFilter'
          : '${context.tr('warehouseAction')}: $_warehouseIdFilter');
    }
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      labels.add(compact ? 'Q: $query' : '"$query"');
    }
    if (_sortMode != _TicketSortMode.sla) {
      labels.add(context.tr(_sortMode.labelKey));
    }
    return labels;
  }

  void _resetAllFilters() {
    setState(() {
      _statusFilter = null;
      _escalationLevelFilter = null;
      _overdueOnly = false;
      _escalatedOnly = false;
      _criticalOnly = false;
      _warehouseIdFilter = null;
      _sortMode = _TicketSortMode.sla;
      _searchController.clear();
    });
    _syncQueryToUrl();
  }

  void _setStatusFilter(ControlTowerTicketStatus? value) {
    setState(() => _statusFilter = value);
    _syncQueryToUrl();
  }

  void _setEscalationLevelFilter(ControlTowerTicketEscalationLevel? value) {
    setState(() => _escalationLevelFilter = value);
    _syncQueryToUrl();
  }

  void _setOverdueOnly(bool value) {
    setState(() => _overdueOnly = value);
    _syncQueryToUrl();
  }

  void _setEscalatedOnly(bool value) {
    setState(() => _escalatedOnly = value);
    _syncQueryToUrl();
  }

  void _setCriticalOnly(bool value) {
    setState(() => _criticalOnly = value);
    _syncQueryToUrl();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _syncQueryToUrl();
  }

  void _setSortMode(_TicketSortMode value) {
    setState(() => _sortMode = value);
    _syncQueryToUrl();
  }

  void _syncQueryToUrl() {
    if (!mounted) {
      return;
    }
    final query = _buildQueryParameters();
    final uri = Uri(path: _ticketsPath, queryParameters: query.isEmpty ? null : query);
    final targetLocation = uri.toString();
    final currentLocation = GoRouterState.of(context).uri.toString();
    if (targetLocation == currentLocation) {
      return;
    }
    context.replace(targetLocation);
  }

  Map<String, String> _buildQueryParameters() {
    final query = <String, String>{};
    if (_statusFilter != null) {
      query['status'] = switch (_statusFilter!) {
        ControlTowerTicketStatus.open => 'open',
        ControlTowerTicketStatus.inProgress => 'in_progress',
        ControlTowerTicketStatus.resolved => 'resolved',
      };
    }
    if (_escalationLevelFilter != null) {
      query['level'] = switch (_escalationLevelFilter!) {
        ControlTowerTicketEscalationLevel.level1 => 'l1',
        ControlTowerTicketEscalationLevel.level2 => 'l2',
        ControlTowerTicketEscalationLevel.level3 => 'l3',
      };
    }
    if (_overdueOnly) {
      query['overdue'] = 'true';
    }
    if (_escalatedOnly) {
      query['escalated'] = 'true';
    }
    if (_criticalOnly) {
      query['critical'] = 'true';
    }
    if (_warehouseIdFilter != null) {
      query['warehouse'] = _warehouseIdFilter!;
    }
    if (_sortMode != _TicketSortMode.sla) {
      query['sort'] = _sortMode.queryValue;
    }
    final search = _searchController.text.trim();
    if (search.isNotEmpty) {
      query['q'] = search;
    }
    return query;
  }

  bool _isCriticalTicket(ControlTowerTicket ticket, DateTime now) {
    return ticket.isSlaBreachedAt(now) ||
        ticket.escalationLevel == ControlTowerTicketEscalationLevel.level3 ||
        ticket.severity == ControlTowerEventSeverity.critical;
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});

  final ControlTowerTicket ticket;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canEdit = appState.canEscalateControlTowerEvents;
    final now = DateTime.now();
    final slaDeltaMinutes = ticket.slaDeltaMinutesAt(now);
    final isOverdue = !ticket.isResolved && slaDeltaMinutes < 0;
    final isCritical = ticket.status != ControlTowerTicketStatus.resolved &&
        (ticket.isSlaBreachedAt(now) ||
            ticket.escalationLevel == ControlTowerTicketEscalationLevel.level3 ||
            ticket.severity == ControlTowerEventSeverity.critical);
    final criticalColor = Theme.of(context).colorScheme.error;
    final priorityColor = isCritical
        ? Colors.red.shade700
        : ticket.escalationLevel == ControlTowerTicketEscalationLevel.level2
            ? Colors.orange.shade700
            : Colors.blueGrey.shade500;
    final assignees = <String>[
      appState.userName,
      'Leitstand Team',
      'Operative Steuerung',
      'Technik Bereitschaft',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: isCritical ? criticalColor.withValues(alpha: 0.06) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isCritical ? criticalColor.withValues(alpha: 0.35) : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: priorityColor),
              ),
            ),
            Expanded(
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
                        _StatusBadge(status: ticket.status),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(context.tr(ticket.messageKey, ticket.messageParams)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      isOverdue
                          ? context.tr(
                              'ticketSlaBreachedShort',
                              <String, Object>{'minutes': slaDeltaMinutes.abs()},
                            )
                          : context.tr(
                              'ticketSlaDueIn',
                              <String, Object>{'minutes': slaDeltaMinutes},
                            ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isOverdue ? Colors.red.shade700 : null,
                            fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        if (isCritical)
                          _InlineBadge(
                            label: context.tr('ticketCriticalBadge'),
                            background: Colors.red.withValues(alpha: 0.14),
                            foreground: Colors.red.shade800,
                          ),
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
                        OutlinedButton.icon(
                          onPressed: () => context.go('/control-tower/tickets/${ticket.id}'),
                          icon: const Icon(Icons.open_in_new_outlined),
                          label: Text(context.tr('ticketOpenDetails')),
                        ),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<ControlTowerTicketStatus>(
                            value: ticket.status,
                            items: ControlTowerTicketStatus.values
                                .map(
                                  (status) => DropdownMenuItem<ControlTowerTicketStatus>(
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
                                    final updated = appState.updateControlTowerTicketStatus(
                                      ticketId: ticket.id,
                                      status: value,
                                    );
                                    if (!updated) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            context.tr('controlTowerTicketUpdateFailed'),
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
                                            context.tr('controlTowerTicketUpdateFailed'),
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
                                            context.tr('controlTowerTicketUpdateFailed'),
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
                            onPressed: () => context.go('/warehouses/${ticket.warehouseId}'),
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
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

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
