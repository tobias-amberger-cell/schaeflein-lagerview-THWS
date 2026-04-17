import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/page_section_header.dart';
import '../widgets/create_warehouse_dialog.dart';
import '../widgets/warehouse_card.dart';

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _didSetInitialSearch = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didSetInitialSearch) {
      return;
    }
    _searchController.text = context.read<AppState>().warehouseSearchQuery;
    _didSetInitialSearch = true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final warehouses = appState.warehouses;
    final filteredWarehouses = appState.filteredWarehouses;
    final selectedWarehouse = appState.selectedWarehouse;
    final selectedWarehouseId = appState.selectedWarehouse?.id;
    final hasFilters = appState.hasWarehouseFilters;
    final apiError = appState.warehouseApiError;
    final isSyncing = appState.isWarehousesSyncing;
    final onlineCount = filteredWarehouses
        .where((item) => item.status == WarehouseStatus.online)
        .length;
    final needsAttentionCount = filteredWarehouses
        .where((item) =>
            item.status == WarehouseStatus.limited ||
            item.status == WarehouseStatus.maintenance)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= AppBreakpoints.desktop
            ? 3
            : constraints.maxWidth >= AppBreakpoints.tablet
                ? 2
                : 1;
        final childAspectRatio = switch (columns) {
          1 => 0.96,
          2 => 0.78,
          _ => 0.74,
        };
        final isWebWide = kIsWeb && constraints.maxWidth >= 1100;

        if (isWebWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageSectionHeader(
                eyebrow: 'Standorte',
                title: context.tr('warehouseTitle'),
                subtitle: context.tr(
                  'warehousesCount',
                  <String, Object>{
                    'shown': filteredWarehouses.length,
                    'all': warehouses.length,
                  },
                ),
                badges: <Widget>[
                  _HeaderBadge(
                    icon: Icons.warehouse_outlined,
                    label: '${filteredWarehouses.length}/${warehouses.length}',
                  ),
                  _HeaderBadge(
                    icon: Icons.check_circle_outline,
                    label: '${context.tr('statusOnline')}: $onlineCount',
                  ),
                  _HeaderBadge(
                    icon: Icons.priority_high_rounded,
                    label: '${context.tr('badgeAttention')}: $needsAttentionCount',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _WarehousesHeroPanel(
                shownCount: filteredWarehouses.length,
                allCount: warehouses.length,
                onlineCount: onlineCount,
                needsAttentionCount: needsAttentionCount,
                isSyncing: isSyncing,
                onCreate: () => _openCreateWarehouseDialog(context),
                onSync: isSyncing
                    ? null
                    : () => context.read<AppState>().syncWarehouses(),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 320,
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const _SectionHeader(
                                title: 'Filter',
                                subtitle: 'Suche und Status filtern',
                                kicker: 'Steuerung',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      TextField(
                                        controller: _searchController,
                                        onChanged: (value) =>
                                            appState.setWarehouseSearchQuery(value.trim()),
                                        decoration: InputDecoration(
                                          hintText: context.tr('searchHint'),
                                          prefixIcon: const Icon(Icons.search),
                                          suffixIcon: appState.warehouseSearchQuery.isEmpty
                                              ? null
                                              : IconButton(
                                                  onPressed: () {
                                                    _searchController.clear();
                                                    appState.setWarehouseSearchQuery('');
                                                  },
                                                  icon: const Icon(Icons.clear),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      Wrap(
                                        spacing: AppSpacing.sm,
                                        runSpacing: AppSpacing.sm,
                                        children: <Widget>[
                                          ChoiceChip(
                                            label: Text(context.tr('all')),
                                            selected: appState.warehouseStatusFilter == null,
                                            onSelected: (_) {
                                              appState.setWarehouseStatusFilter(null);
                                            },
                                          ),
                                          ...WarehouseStatus.values.map(
                                            (status) => ChoiceChip(
                                              label: Text(context.tr(status.labelKey)),
                                              selected: appState.warehouseStatusFilter == status,
                                              onSelected: (_) {
                                                appState.setWarehouseStatusFilter(status);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      _FilterSummary(
                                        query: appState.warehouseSearchQuery,
                                        status: appState.warehouseStatusFilter,
                                      ),
                                      if (hasFilters) ...<Widget>[
                                        const SizedBox(height: AppSpacing.xs),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: _clearFilters,
                                            icon: const Icon(Icons.filter_alt_off_outlined),
                                            label: Text(context.tr('filtersReset')),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (apiError != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.sm),
                                Card(
                                  color: Theme.of(context).colorScheme.errorContainer,
                                  child: Padding(
                                    padding: const EdgeInsets.all(AppSpacing.sm),
                                    child: Text(
                                      context.tr(
                                        'warehousesSyncError',
                                        <String, Object>{'error': apiError},
                                      ),
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.onErrorContainer,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              const _SectionHeader(
                                title: 'Status',
                                subtitle: 'Online und Aufmerksamkeit',
                                kicker: 'Live',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      _StatusLine(
                                        label: context.tr('statusOnline'),
                                        value: '$onlineCount',
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      _StatusLine(
                                        label: context.tr('badgeAttention'),
                                        value: '$needsAttentionCount',
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      FilledButton.icon(
                                        onPressed: () => _openCreateWarehouseDialog(context),
                                        icon: const Icon(Icons.add_business_outlined),
                                        label: Text(context.tr('createWarehouse')),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (selectedWarehouse != null) ...<Widget>[
                                _SelectedWarehouseBanner(
                                  warehouse: selectedWarehouse,
                                  onOpenViewer: () => _openWarehouse(context, selectedWarehouse),
                                  onOpenDetails: () =>
                                      _openWarehouseDetails(context, selectedWarehouse),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              _SectionHeader(
                                title: 'Ergebnisse',
                                subtitle: context.tr(
                                  'warehousesCount',
                                  <String, Object>{
                                    'shown': filteredWarehouses.length,
                                    'all': warehouses.length,
                                  },
                                ),
                                kicker: 'Standorte',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              if (filteredWarehouses.isEmpty)
                                EmptyState(
                                  icon: Icons.search_off,
                                  title: context.tr('noWarehousesFound'),
                                  message: hasFilters
                                      ? context.tr('adjustFilters')
                                      : context.tr('noWarehouseData'),
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, resultConstraints) {
                                    final webColumns = resultConstraints.maxWidth >= 1380
                                        ? 4
                                        : resultConstraints.maxWidth >= 1050
                                            ? 3
                                            : resultConstraints.maxWidth >= 660
                                                ? 2
                                                : 1;
                                    final webCardRatio = switch (webColumns) {
                                      1 => 0.98,
                                      2 => 0.83,
                                      3 => 0.77,
                                      _ => 0.72,
                                    };
                                    return GridView.builder(
                                      itemCount: filteredWarehouses.length,
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: webColumns,
                                        mainAxisSpacing: AppSpacing.md,
                                        crossAxisSpacing: AppSpacing.md,
                                        childAspectRatio: webCardRatio,
                                      ),
                                      itemBuilder: (context, index) {
                                        final warehouse = filteredWarehouses[index];
                                        final isFavorite =
                                            appState.isFavoriteWarehouse(warehouse.id);
                                        return WarehouseCard(
                                          warehouse: warehouse,
                                          isSelected: selectedWarehouseId == warehouse.id,
                                          isFavorite: isFavorite,
                                          onTap: () => _openWarehouseDetails(context, warehouse),
                                          onSelect: () => _selectWarehouse(context, warehouse),
                                          onOpenViewer: () => _openWarehouse(context, warehouse),
                                          onToggleFavorite: () => _toggleFavorite(
                                            context: context,
                                            warehouse: warehouse,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return ListView(
          children: <Widget>[
            PageSectionHeader(
              eyebrow: 'Standorte',
              title: context.tr('warehouseTitle'),
              subtitle: context.tr(
                'warehousesCount',
                <String, Object>{
                  'shown': filteredWarehouses.length,
                  'all': warehouses.length,
                },
              ),
              badges: <Widget>[
                _HeaderBadge(
                  icon: Icons.warehouse_outlined,
                  label: '${filteredWarehouses.length}/${warehouses.length}',
                ),
                _HeaderBadge(
                  icon: Icons.check_circle_outline,
                  label: '${context.tr('statusOnline')}: $onlineCount',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const _SectionHeader(
              title: '\u00DCbersicht',
              subtitle: 'Status, Sync und neue Lager schnell im Blick',
              kicker: 'Cockpit',
            ),
            const SizedBox(height: AppSpacing.sm),
            _WarehousesHeroPanel(
              shownCount: filteredWarehouses.length,
              allCount: warehouses.length,
              onlineCount: onlineCount,
              needsAttentionCount: needsAttentionCount,
              isSyncing: isSyncing,
              onCreate: () => _openCreateWarehouseDialog(context),
              onSync: isSyncing
                  ? null
                  : () => context.read<AppState>().syncWarehouses(),
            ),
            if (apiError != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    context.tr(
                      'warehousesSyncError',
                      <String, Object>{'error': apiError},
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const _SectionHeader(
              title: 'Filter & Suche',
              subtitle: 'Standorte nach Status und Name eingrenzen',
              kicker: 'Filter',
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          appState.setWarehouseSearchQuery(value.trim()),
                      decoration: InputDecoration(
                        hintText: context.tr('searchHint'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: appState.warehouseSearchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  appState.setWarehouseSearchQuery('');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        ChoiceChip(
                          label: Text(context.tr('all')),
                          selected: appState.warehouseStatusFilter == null,
                          onSelected: (_) {
                            appState.setWarehouseStatusFilter(null);
                          },
                        ),
                        ...WarehouseStatus.values.map(
                          (status) => ChoiceChip(
                            label: Text(context.tr(status.labelKey)),
                            selected: appState.warehouseStatusFilter == status,
                            onSelected: (_) {
                              appState.setWarehouseStatusFilter(status);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _FilterSummary(
                      query: appState.warehouseSearchQuery,
                      status: appState.warehouseStatusFilter,
                    ),
                    if (hasFilters) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: Text(context.tr('filtersReset')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SectionHeader(
              title: 'Ergebnisse',
              subtitle: context.tr(
                'warehousesCount',
                <String, Object>{
                  'shown': filteredWarehouses.length,
                  'all': warehouses.length,
                },
              ),
              kicker: 'Standorte',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (selectedWarehouse != null) ...<Widget>[
              _SelectedWarehouseBanner(
                warehouse: selectedWarehouse,
                onOpenViewer: () => _openWarehouse(context, selectedWarehouse),
                onOpenDetails: () => _openWarehouseDetails(context, selectedWarehouse),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (filteredWarehouses.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                title: context.tr('noWarehousesFound'),
                message: hasFilters
                    ? context.tr('adjustFilters')
                    : context.tr('noWarehouseData'),
              )
            else
              GridView.builder(
                itemCount: filteredWarehouses.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: childAspectRatio,
                ),
                itemBuilder: (context, index) {
                  final warehouse = filteredWarehouses[index];
                  final isFavorite =
                      appState.isFavoriteWarehouse(warehouse.id);
                  return WarehouseCard(
                    warehouse: warehouse,
                    isSelected: selectedWarehouseId == warehouse.id,
                    isFavorite: isFavorite,
                    onTap: () => _openWarehouseDetails(context, warehouse),
                    onSelect: () => _selectWarehouse(context, warehouse),
                    onOpenViewer: () => _openWarehouse(context, warehouse),
                    onToggleFavorite: () => _toggleFavorite(
                      context: context,
                      warehouse: warehouse,
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  void _clearFilters() {
    _searchController.clear();
    context.read<AppState>().clearWarehouseFilters();
  }

  Future<void> _openCreateWarehouseDialog(BuildContext context) async {
    final appState = context.read<AppState>();
    if (!appState.canManageWarehouses) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('warehouseCreateNoPermission')),
        ),
      );
      return;
    }
    final input = await showCreateWarehouseDialog(context);
    if (!context.mounted || input == null) {
      return;
    }
    final created = await appState.createWarehouse(
      name: input.name,
      location: input.location,
      status: input.status,
      description: input.description,
      lengthM: input.lengthM,
      widthM: input.widthM,
      heightM: input.heightM,
      rackRowCount: input.rackRowCount,
      rackLengthM: input.rackLengthM,
      rackWidthM: input.rackWidthM,
      rackLevels: input.rackLevels,
      aisleWidthM: input.aisleWidthM,
      zoneNames: input.zoneNames,
    );
    if (!context.mounted) {
      return;
    }
    if (!created) {
      final apiError = appState.warehouseApiError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(apiError ?? context.tr('warehouseCreateFailed')),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'warehouseCreatedMsg',
            <String, Object>{'name': input.name},
          ),
        ),
      ),
    );
    context.go('/viewer');
  }

  void _openWarehouse(BuildContext context, Warehouse warehouse) {
    context.read<AppState>().selectWarehouse(warehouse);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('selectedWarehouseMsg', <String, Object>{'name': warehouse.name}),
        ),
      ),
    );
    context.go('/viewer');
  }

  void _openWarehouseDetails(BuildContext context, Warehouse warehouse) {
    context.go('/warehouses/${warehouse.id}');
  }

  void _selectWarehouse(BuildContext context, Warehouse warehouse) {
    context.read<AppState>().selectWarehouse(warehouse);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('selectedWarehouseMsg', <String, Object>{'name': warehouse.name}),
        ),
      ),
    );
  }

  void _toggleFavorite({
    required BuildContext context,
    required Warehouse warehouse,
    bool showFeedback = true,
  }) {
    final appState = context.read<AppState>();
    if (!appState.canToggleFavorites) {
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('viewerRoleNoFavorites')),
          ),
        );
      }
      return;
    }
    final wasFavorite = appState.isFavoriteWarehouse(warehouse.id);
    final changed = appState.toggleFavoriteWarehouse(warehouse.id);
    if (!changed) {
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('viewerRoleNoFavorites')),
          ),
        );
      }
      return;
    }
    if (!showFeedback) {
      return;
    }
    final message = wasFavorite
        ? context.tr('favoriteRemovedMsg', <String, Object>{'name': warehouse.name})
        : context.tr('favoriteAddedMsg', <String, Object>{'name': warehouse.name});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.kicker,
  });

  final String title;
  final String? subtitle;
  final String? kicker;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (kicker != null) ...<Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                kicker!.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _FilterSummary extends StatelessWidget {
  const _FilterSummary({
    required this.query,
    required this.status,
  });

  final String query;
  final WarehouseStatus? status;

  @override
  Widget build(BuildContext context) {
    String label;
    final statusValue = status;
    if (query.isNotEmpty && statusValue != null) {
      label = context.tr(
        'searchFilterSummaryBoth',
        <String, Object>{
          'query': query,
          'status': context.tr(statusValue.labelKey),
        },
      );
    } else if (query.isNotEmpty) {
      label = context.tr(
        'searchFilterSummaryQuery',
        <String, Object>{'query': query},
      );
    } else if (statusValue != null) {
      label = context.tr(
        'searchFilterSummaryStatus',
        <String, Object>{'status': context.tr(statusValue.labelKey)},
      );
    } else {
      label = context.tr('noFiltersActive');
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _WarehousesHeroPanel extends StatelessWidget {
  const _WarehousesHeroPanel({
    required this.shownCount,
    required this.allCount,
    required this.onlineCount,
    required this.needsAttentionCount,
    required this.isSyncing,
    required this.onCreate,
    required this.onSync,
  });

  final int shownCount;
  final int allCount;
  final int onlineCount;
  final int needsAttentionCount;
  final bool isSyncing;
  final VoidCallback onCreate;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primaryContainer.withValues(alpha: 0.5),
            colorScheme.secondaryContainer.withValues(alpha: 0.2),
            colorScheme.surfaceContainerLowest,
          ],
        ),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Lagersteuerung',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Standorte verwalten, filtern und direkt in 3D \u00F6ffnen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add_business_outlined),
                      label: Text(context.tr('createWarehouse')),
                    ),
                    OutlinedButton.icon(
                      onPressed: onSync,
                      icon: Icon(isSyncing ? Icons.sync : Icons.sync_outlined),
                      label: Text(context.tr('warehousesSyncAction')),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _HeroKpiChip(
                  icon: Icons.warehouse_outlined,
                  label: context.tr('warehouses'),
                  value: '$shownCount/$allCount',
                ),
                _HeroKpiChip(
                  icon: Icons.check_circle_outline,
                  label: context.tr('statusOnline'),
                  value: '$onlineCount',
                ),
                _HeroKpiChip(
                  icon: Icons.priority_high_rounded,
                  label: context.tr('badgeAttention'),
                  value: '$needsAttentionCount',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroKpiChip extends StatelessWidget {
  const _HeroKpiChip({
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.85),
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
            Column(
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
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedWarehouseBanner extends StatelessWidget {
  const _SelectedWarehouseBanner({
    required this.warehouse,
    required this.onOpenViewer,
    required this.onOpenDetails,
  });

  final Warehouse warehouse;
  final VoidCallback onOpenViewer;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;
        final actions = Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.end,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: onOpenDetails,
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Details'),
            ),
            FilledButton.icon(
              onPressed: onOpenViewer,
              icon: const Icon(Icons.view_in_ar_outlined, size: 16),
              label: const Text('3D'),
            ),
          ],
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.check_circle_outline,
                              color: colorScheme.primary, size: 18),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Aktives Lager',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  warehouse.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      actions,
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Icon(Icons.check_circle_outline,
                          color: colorScheme.primary, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Aktives Lager',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              warehouse.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  Theme.of(context).textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      actions,
                    ],
                  ),
          ),
        );
      },
    );
  }
}
