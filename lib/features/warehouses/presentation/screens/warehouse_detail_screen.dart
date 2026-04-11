import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/tour.dart';
import '../../../../models/warehouse.dart';
import '../../../../models/warehouse_operations_profile.dart';
import '../../../../shared/widgets/abc_analysis_bar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../widgets/create_warehouse_dialog.dart';
import '../widgets/warehouse_card.dart';

class WarehouseDetailScreen extends StatelessWidget {
  const WarehouseDetailScreen({
    super.key,
    required this.warehouseId,
  });

  final String warehouseId;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;
    final warehouse = appState.getWarehouseById(warehouseId);
    if (warehouse == null) {
      return EmptyState(
        icon: Icons.warehouse_outlined,
        title: context.tr('warehouseNotFound'),
        message: context.tr('warehouseNotFoundMessage'),
        actionLabel: context.tr('toWarehouseList'),
        onAction: () => context.go('/warehouses'),
      );
    }

    final isFavorite = appState.isFavoriteWarehouse(warehouse.id);
    final canToggleFavorites = appState.canToggleFavorites;
    final canManageWarehouses = appState.canManageWarehouses;
    final operations = appState.getOperationsProfile(warehouse.id);
    final warehouseTours = appState.getToursByWarehouse(warehouse.id);
    final storageSamples = appState.getStorageLocationsForWarehouse(warehouse.id);
    final zones = <WarehouseZone>[...warehouse.zones]
      ..sort((a, b) => b.utilizationRatio.compareTo(a.utilizationRatio));

    return DefaultTabController(
      length: 7,
      child: Column(
        children: <Widget>[
          _WarehouseHeaderCard(
            warehouse: warehouse,
            isFavorite: isFavorite,
            canToggleFavorites: canToggleFavorites,
            canManageWarehouses: canManageWarehouses,
            onToggleFavorite: () => _toggleFavorite(context, appState, warehouse),
            onStatusChanged: (status) =>
                _changeStatus(context, appState, warehouse, status),
            onEditWarehouse: () => _editWarehouse(context, appState, warehouse),
            onDeleteWarehouse: () =>
                _deleteWarehouse(context, appState, warehouse),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorPadding: EdgeInsets.zero,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: colorScheme.primary.withValues(alpha: 0.14),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.22),
                ),
              ),
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              tabs: <Tab>[
                Tab(text: context.tr('tabOverview')),
                Tab(text: context.tr('tabZones')),
                Tab(text: context.tr('tabPerformance')),
                Tab(text: context.tr('tabOperations')),
                Tab(text: context.tr('tabAbc')),
                Tab(text: context.tr('tabTours')),
                Tab(text: context.tr('tabHistory')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _OverviewTab(
                  warehouse: warehouse,
                  storageSamples: storageSamples,
                ),
                _ZonesTab(zones: zones),
                ListView(
                  children: <Widget>[
                    _WarehouseKpiSection(warehouse: warehouse),
                  ],
                ),
                _OperationsTab(operations: operations),
                _AbcTab(
                  warehouse: warehouse,
                  zones: zones,
                ),
                _WarehouseToursTab(tours: warehouseTours),
                _HistoryTab(warehouse: warehouse),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFavorite(
    BuildContext context,
    AppState appState,
    Warehouse warehouse,
  ) {
    final wasFavorite = appState.isFavoriteWarehouse(warehouse.id);
    appState.toggleFavoriteWarehouse(warehouse.id);
    final message = wasFavorite
        ? context.tr('favoriteRemovedMsg', <String, Object>{'name': warehouse.name})
        : context.tr('favoriteAddedMsg', <String, Object>{'name': warehouse.name});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeStatus(
    BuildContext context,
    AppState appState,
    Warehouse warehouse,
    WarehouseStatus status,
  ) async {
    final updated = await appState.updateWarehouseStatus(
      warehouseId: warehouse.id,
      status: status,
    );
    if (!context.mounted) {
      return;
    }
    if (!updated) {
      final message = appState.warehouseApiError ??
          context.tr('warehouseEditNoPermission');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'warehouseStatusUpdatedMsg',
            <String, Object>{
              'name': warehouse.name,
              'status': context.tr(status.labelKey),
            },
          ),
        ),
      ),
    );
  }

  Future<void> _editWarehouse(
    BuildContext context,
    AppState appState,
    Warehouse warehouse,
  ) async {
    if (!appState.canManageWarehouses) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('warehouseEditNoPermission'))),
      );
      return;
    }

    final input = await showEditWarehouseDialog(context, warehouse);
    if (!context.mounted || input == null) {
      return;
    }

    final updated = await appState.updateWarehouse(
      warehouseId: warehouse.id,
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
    if (!updated) {
      final message = appState.warehouseApiError ??
          context.tr('warehouseEditNoPermission');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'warehouseUpdatedMsg',
            <String, Object>{'name': input.name},
          ),
        ),
      ),
    );
  }

  Future<void> _deleteWarehouse(
    BuildContext context,
    AppState appState,
    Warehouse warehouse,
  ) async {
    if (!appState.canManageWarehouses) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('warehouseDeleteNoPermission'))),
      );
      return;
    }

    final shouldDelete = await _showDeleteWarehouseDialog(context, warehouse.name);
    if (!context.mounted || !shouldDelete) {
      return;
    }

    final success = await appState.deleteWarehouse(warehouse.id);
    if (!context.mounted) {
      return;
    }
    if (!success) {
      final message = appState.warehouseApiError ??
          context.tr('warehouseDeleteFailed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'warehouseDeletedMsg',
            <String, Object>{'name': warehouse.name},
          ),
        ),
      ),
    );
    context.go('/warehouses');
  }

  Future<bool> _showDeleteWarehouseDialog(BuildContext context, String warehouseName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.tr('deleteWarehouseTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.tr(
                  'deleteWarehousePrompt',
                  <String, Object>{'name': warehouseName},
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.tr('deleteWarehouseWarning'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: Text(context.tr('confirmDelete')),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

class _WarehouseHeaderCard extends StatelessWidget {
  const _WarehouseHeaderCard({
    required this.warehouse,
    required this.isFavorite,
    required this.canToggleFavorites,
    required this.canManageWarehouses,
    required this.onToggleFavorite,
    required this.onStatusChanged,
    required this.onEditWarehouse,
    required this.onDeleteWarehouse,
  });

  final Warehouse warehouse;
  final bool isFavorite;
  final bool canToggleFavorites;
  final bool canManageWarehouses;
  final VoidCallback onToggleFavorite;
  final Future<void> Function(WarehouseStatus) onStatusChanged;
  final VoidCallback onEditWarehouse;
  final VoidCallback onDeleteWarehouse;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colorScheme.primary.withValues(alpha: 0.12),
              colorScheme.tertiary.withValues(alpha: 0.1),
              colorScheme.surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.apartment_rounded),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          warehouse.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          warehouse.location,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusChip(status: warehouse.status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  _ValueChip(label: context.tr('warehouseIdLabel'), value: warehouse.id),
                  _ValueChip(label: context.tr('zones'), value: '${warehouse.zoneCount}'),
                  _ValueChip(
                    label: context.tr('articlesTotal'),
                    value: '${warehouse.articleCount}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () {
                      appState.selectWarehouse(warehouse);
                      context.go('/viewer');
                    },
                    icon: const Icon(Icons.view_in_ar_outlined),
                    label: Text(context.tr('open3dView')),
                  ),
                  OutlinedButton.icon(
                    onPressed: canToggleFavorites ? onToggleFavorite : null,
                    icon: Icon(
                      isFavorite ? Icons.star : Icons.star_border_rounded,
                      color: isFavorite ? Colors.amber.shade700 : null,
                    ),
                    label: Text(
                      isFavorite
                          ? context.tr('removeFavoriteShort')
                          : context.tr('saveFavorite'),
                    ),
                  ),
                  PopupMenuButton<WarehouseStatus>(
                    onSelected: canToggleFavorites
                        ? (status) => unawaited(onStatusChanged(status))
                        : null,
                    tooltip: context.tr('changeWarehouseStatus'),
                    itemBuilder: (context) => WarehouseStatus.values
                        .map(
                          (status) => PopupMenuItem<WarehouseStatus>(
                            value: status,
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  status == WarehouseStatus.online
                                      ? Icons.check_circle_outline
                                      : status == WarehouseStatus.limited
                                          ? Icons.warning_amber_outlined
                                          : Icons.build_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(context.tr(status.labelKey)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.swap_horiz_rounded),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              context.tr('changeWarehouseStatus'),
                              style: TextStyle(
                                color: canToggleFavorites
                                    ? null
                                    : Theme.of(context).disabledColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: canManageWarehouses ? onEditWarehouse : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(context.tr('editWarehouse')),
                  ),
                  OutlinedButton.icon(
                    onPressed: canManageWarehouses ? onDeleteWarehouse : null,
                    icon: const Icon(Icons.delete_outline),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                    label: Text(context.tr('deleteWarehouse')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.warehouse,
    required this.storageSamples,
  });

  final Warehouse warehouse;
  final List<WarehouseStorageLocation> storageSamples;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CardSectionHeader(
                  title: context.tr('warehouseKpiTitle'),
                  subtitle: context.tr('warehouseKpiSubtitle'),
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 12,
                    value: warehouse.utilizationRatio,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    _ValueChip(
                      label: context.tr('kpiUtilization'),
                      value: '${warehouse.utilizationPercent}%',
                    ),
                    _ValueChip(
                      label: context.tr('kpiOccupiedSlots'),
                      value: '${warehouse.occupiedStorageSlots}',
                    ),
                    _ValueChip(
                      label: context.tr('kpiFreeSlots'),
                      value: '${warehouse.freeStorageSlots}',
                    ),
                    _ValueChip(
                      label: context.tr('kpiTotalSlots'),
                      value: '${warehouse.totalStorageSlots}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _WarehouseAbcSection(warehouse: warehouse),
        const SizedBox(height: AppSpacing.md),
        _StorageLocationSamplesCard(
          warehouse: warehouse,
          samples: storageSamples,
        ),
      ],
    );
  }
}

class _ZonesTab extends StatelessWidget {
  const _ZonesTab({required this.zones});

  final List<WarehouseZone> zones;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CardSectionHeader(
                  title: context.tr('zoneAnalysisTitle'),
                  subtitle: context.tr('zoneAnalysisSubtitle'),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...zones.map((zone) => _ZoneAnalyticsCard(zone: zone)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StorageLocationSamplesCard extends StatelessWidget {
  const _StorageLocationSamplesCard({
    required this.warehouse,
    required this.samples,
  });

  final Warehouse warehouse;
  final List<WarehouseStorageLocation> samples;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visibleSamples = samples.take(12).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardSectionHeader(
              title: context.tr('storageLocationSamplesTitle'),
              subtitle: context.tr('storageLocationSamplesSubtitle'),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (visibleSamples.isEmpty)
              Text(
                context.tr('storageLocationSamplesEmpty'),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              Column(
                children: visibleSamples.map((sample) {
                  final abc = sample.abcClass.trim().toUpperCase();
                  final chipColors = _abcChipColors(abc, colorScheme);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: chipColors.$1,
                      foregroundColor: chipColors.$2,
                      child: Text(abc.isEmpty ? '?' : abc),
                    ),
                    title: Text(sample.displayCode),
                    subtitle: Text(
                      [
                        if (sample.area.isNotEmpty)
                          '${context.tr('warehouseAreaLabel')}: ${sample.area}',
                        if (sample.status.isNotEmpty)
                          '${context.tr('warehouseStatusShort')}: ${sample.status}',
                      ].join(' · '),
                    ),
                    trailing: TextButton.icon(
                      onPressed: () {
                        appState.selectWarehouse(warehouse);
                        appState.setSelectedStorageLocation(sample);
                        appState.requestViewerStorageFocus(
                          rack: sample.rackNumber,
                          level: sample.levelNumber,
                          slot: sample.slotNumber,
                        );
                        context.go('/viewer');
                      },
                      icon: const Icon(Icons.center_focus_strong),
                      label: Text(context.tr('storageLocationViewInViewer')),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  (Color, Color) _abcChipColors(String abc, ColorScheme scheme) {
    switch (abc) {
      case 'A':
        return (scheme.errorContainer, scheme.onErrorContainer);
      case 'B':
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer);
      case 'C':
        return (scheme.secondaryContainer, scheme.onSecondaryContainer);
      default:
        return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    }
  }
}

class _AbcTab extends StatelessWidget {
  const _AbcTab({
    required this.warehouse,
    required this.zones,
  });

  final Warehouse warehouse;
  final List<WarehouseZone> zones;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        _WarehouseAbcSection(warehouse: warehouse),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CardSectionHeader(
                  title: context.tr('zoneAnalysisTitle'),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...zones.map(
                  (zone) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          zone.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AbcAnalysisBar(
                          aCount: zone.abcAnalysis.aCount,
                          bCount: zone.abcAnalysis.bCount,
                          cCount: zone.abcAnalysis.cCount,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WarehouseKpiSection extends StatelessWidget {
  const _WarehouseKpiSection({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardSectionHeader(
              title: context.tr('warehouseKpiTitle'),
              subtitle: context.tr('warehouseKpiSubtitle'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 12,
                value: warehouse.utilizationRatio,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _ValueChip(
                  label: context.tr('kpiUtilization'),
                  value: '${warehouse.utilizationPercent}%',
                ),
                _ValueChip(
                  label: context.tr('kpiOccupiedSlots'),
                  value: '${warehouse.occupiedStorageSlots}',
                ),
                _ValueChip(
                  label: context.tr('kpiFreeSlots'),
                  value: '${warehouse.freeStorageSlots}',
                ),
                _ValueChip(
                  label: context.tr('kpiTotalSlots'),
                  value: '${warehouse.totalStorageSlots}',
                ),
                _ValueChip(
                  label: context.tr('kpiInboundPerDay'),
                  value: '${warehouse.inboundPerDay}',
                ),
                _ValueChip(
                  label: context.tr('kpiThroughputPerDay'),
                  value: '${warehouse.throughputPerDay}',
                ),
                _ValueChip(
                  label: context.tr('kpiPickRatePerHour'),
                  value: '${warehouse.pickRatePerHour}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationsTab extends StatelessWidget {
  const _OperationsTab({required this.operations});

  final WarehouseOperationsProfile operations;

  @override
  Widget build(BuildContext context) {
    final dockUtilPercent = (operations.dockUtilizationRatio * 100).round();
    final totalSlotMix = operations.totalSlotMix == 0 ? 1 : operations.totalSlotMix;

    return ListView(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CardSectionHeader(
                  title: context.tr('warehouseOperationsTitle'),
                  subtitle: context.tr('warehouseOperationsSubtitle'),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    _ValueChip(
                      label: context.tr('opsDockActive'),
                      value: '${operations.activeDocks}/${operations.dockCount}',
                    ),
                    _ValueChip(
                      label: context.tr('opsDockUtilization'),
                      value: '$dockUtilPercent%',
                    ),
                    _ValueChip(
                      label: context.tr('opsBlockedSlots'),
                      value: '${operations.blockedSlots}',
                    ),
                    _ValueChip(
                      label: context.tr('opsReservedSlots'),
                      value: '${operations.reservedSlots}',
                    ),
                    _ValueChip(
                      label: context.tr('opsAvgDwell'),
                      value: '${operations.avgDwellMinutes} min',
                    ),
                    _ValueChip(
                      label: context.tr('opsSlaCurrent'),
                      value: '${operations.slaCurrentPercent}%',
                    ),
                    _ValueChip(
                      label: context.tr('opsSlaTarget'),
                      value: '${operations.slaTargetPercent}%',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: operations.dockUtilizationRatio.clamp(0, 1).toDouble(),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('opsSlotMixTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                _SlotMixRow(
                  label: context.tr('opsHighBaySlots'),
                  value: operations.highBaySlots,
                  ratio: operations.highBaySlots / totalSlotMix,
                ),
                _SlotMixRow(
                  label: context.tr('opsBlockStorageSlots'),
                  value: operations.blockStorageSlots,
                  ratio: operations.blockStorageSlots / totalSlotMix,
                ),
                _SlotMixRow(
                  label: context.tr('opsShuttleSlots'),
                  value: operations.shuttleSlots,
                  ratio: operations.shuttleSlots / totalSlotMix,
                ),
                _SlotMixRow(
                  label: context.tr('opsFloorStorageSlots'),
                  value: operations.floorStorageSlots,
                  ratio: operations.floorStorageSlots / totalSlotMix,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _ValueChip(
                  label: context.tr('opsColdZones'),
                  value: '${operations.coldZoneCount}',
                ),
                _ValueChip(
                  label: context.tr('opsAmbientZones'),
                  value: '${operations.ambientZoneCount}',
                ),
                _ValueChip(
                  label: context.tr('opsHazardousZones'),
                  value: '${operations.hazardousZoneCount}',
                ),
                _ValueChip(
                  label: context.tr('opsSafetyIncidents'),
                  value: '${operations.safetyIncidentsMonth}',
                ),
                _ValueChip(
                  label: context.tr('opsQualityHolds'),
                  value: '${operations.qualityHolds}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SlotMixRow extends StatelessWidget {
  const _SlotMixRow({
    required this.label,
    required this.value,
    required this.ratio,
  });

  final String label;
  final int value;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final safeRatio = ratio.clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$value',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: safeRatio,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseToursTab extends StatelessWidget {
  const _WarehouseToursTab({required this.tours});

  final List<TransportTour> tours;

  @override
  Widget build(BuildContext context) {
    if (tours.isEmpty) {
      return ListView(
        children: <Widget>[
          EmptyState(
            icon: Icons.route_outlined,
            title: context.tr('noToursFound'),
            message: context.tr('warehouseToursEmpty'),
            actionLabel: context.tr('openTours'),
            onAction: () => context.go('/tours'),
          ),
        ],
      );
    }

    return ListView(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CardSectionHeader(
                  title: context.tr('warehouseToursTitle'),
                  subtitle: context.tr(
                    'warehouseToursSubtitle',
                    <String, Object>{'count': tours.length},
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...tours.map(
                  (tour) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text('${tour.code} | ${tour.vehicleCode}'),
                        subtitle: Text(
                          context.tr(
                            'warehouseTourLine',
                            <String, Object>{
                              'driver': tour.driverName,
                              'status': context.tr(tour.status.labelKey),
                              'stops': tour.stopCount,
                              'load': tour.loadFactorPercent,
                            },
                          ),
                        ),
                        trailing: Text('${tour.progressPercent}%'),
                        onTap: () => context.go('/tours'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatefulWidget {
  const _HistoryTab({required this.warehouse});

  final Warehouse warehouse;

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final TextEditingController _searchController = TextEditingController();
  _HistoryType? _selectedType;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = _buildHistoryEntries(widget.warehouse);
    final query = _searchController.text.trim().toLowerCase();
    final entries = allEntries.where((entry) {
      final matchesType = _selectedType == null || entry.type == _selectedType;
      if (!matchesType) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final title = context.tr(entry.titleKey).toLowerCase();
      final message =
          context.tr(entry.messageKey, entry.messageParams).toLowerCase();
      return title.contains(query) || message.contains(query);
    }).toList(growable: false);

    return ListView(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CardSectionHeader(
                  title: context.tr('historyTitle'),
                  subtitle: context.tr('historySubtitle'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: context.tr('historySearchHint'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    ChoiceChip(
                      label: Text(context.tr('historyFilterAll')),
                      selected: _selectedType == null,
                      onSelected: (_) => setState(() => _selectedType = null),
                    ),
                    ..._HistoryType.values.map(
                      (type) => ChoiceChip(
                        label: Text(context.tr(type.labelKey)),
                        selected: _selectedType == type,
                        onSelected: (_) => setState(() => _selectedType = type),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (entries.isEmpty)
                  Text(context.tr('historyNoResults'))
                else
                  ...entries.map((entry) => _HistoryItem(entry: entry)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_WarehouseHistoryEntry> _buildHistoryEntries(Warehouse warehouse) {
    final now = DateTime.now();
    return <_WarehouseHistoryEntry>[
      _WarehouseHistoryEntry(
        titleKey: 'historyAlertTitle',
        messageKey: warehouse.status == WarehouseStatus.maintenance
            ? 'historyAlertMaintenanceMsg'
            : 'historyAlertHealthyMsg',
        messageParams: <String, Object>{'name': warehouse.name},
        createdAt: now.subtract(const Duration(minutes: 12)),
        severity: _HistorySeverity.warning,
        type: _HistoryType.alert,
      ),
      _WarehouseHistoryEntry(
        titleKey: 'historyInventoryTitle',
        messageKey: 'historyInventoryMsg',
        messageParams: <String, Object>{'count': warehouse.articleCount},
        createdAt: now.subtract(const Duration(hours: 2, minutes: 8)),
        severity: _HistorySeverity.info,
        type: _HistoryType.inventory,
      ),
      _WarehouseHistoryEntry(
        titleKey: 'historyPerformanceTitle',
        messageKey: 'historyPerformanceMsg',
        messageParams: <String, Object>{
          'throughput': warehouse.throughputPerDay,
          'pick': warehouse.pickRatePerHour,
        },
        createdAt: now.subtract(const Duration(hours: 5, minutes: 26)),
        severity: _HistorySeverity.info,
        type: _HistoryType.performance,
      ),
      _WarehouseHistoryEntry(
        titleKey: 'historyMaintenanceTitle',
        messageKey: 'historyMaintenanceMsg',
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        severity: _HistorySeverity.critical,
        type: _HistoryType.maintenance,
      ),
    ];
  }
}

class _WarehouseAbcSection extends StatelessWidget {
  const _WarehouseAbcSection({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context) {
    final analysis = warehouse.abcAnalysis;
    final total = analysis.total;
    final aPercent = total == 0 ? 0 : (analysis.aRatio * 100).round();
    final bPercent = total == 0 ? 0 : (analysis.bRatio * 100).round();
    final cPercent = total == 0 ? 0 : (analysis.cRatio * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardSectionHeader(
              title: context.tr('warehouseAbcTitle'),
              subtitle: context.tr(
                'warehouseAbcSubtitle',
                <String, Object>{'count': total},
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AbcAnalysisBar(
              aCount: analysis.aCount,
              bCount: analysis.bCount,
              cCount: analysis.cCount,
              height: 14,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _ValueChip(label: context.tr('kpiAShare'), value: '$aPercent%'),
                _ValueChip(label: context.tr('kpiBShare'), value: '$bPercent%'),
                _ValueChip(label: context.tr('kpiCShare'), value: '$cPercent%'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.entry});

  final _WarehouseHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.severity) {
      _HistorySeverity.info => Colors.blue.shade700,
      _HistorySeverity.warning => Colors.orange.shade700,
      _HistorySeverity.critical => Colors.red.shade700,
    };
    final icon = switch (entry.severity) {
      _HistorySeverity.info => Icons.info_outline,
      _HistorySeverity.warning => Icons.warning_amber_rounded,
      _HistorySeverity.critical => Icons.error_outline,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.tr(entry.titleKey),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(entry.messageKey, entry.messageParams),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _formatTime(context, entry.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
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

  String _formatTime(BuildContext context, DateTime time) {
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

class _CardSectionHeader extends StatelessWidget {
  const _CardSectionHeader({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (subtitleText != null && subtitleText.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitleText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

class _WarehouseHistoryEntry {
  const _WarehouseHistoryEntry({
    required this.titleKey,
    required this.messageKey,
    this.messageParams = const <String, Object>{},
    required this.createdAt,
    required this.severity,
    required this.type,
  });

  final String titleKey;
  final String messageKey;
  final Map<String, Object> messageParams;
  final DateTime createdAt;
  final _HistorySeverity severity;
  final _HistoryType type;
}

enum _HistorySeverity {
  info,
  warning,
  critical,
}

enum _HistoryType {
  alert,
  inventory,
  performance,
  maintenance,
}

extension _HistoryTypeLabelKey on _HistoryType {
  String get labelKey {
    switch (this) {
      case _HistoryType.alert:
        return 'historyFilterAlert';
      case _HistoryType.inventory:
        return 'historyFilterInventory';
      case _HistoryType.performance:
        return 'historyFilterPerformance';
      case _HistoryType.maintenance:
        return 'historyFilterMaintenance';
    }
  }
}

class _ZoneAnalyticsCard extends StatelessWidget {
  const _ZoneAnalyticsCard({required this.zone});

  final WarehouseZone zone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      zone.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${zone.utilizationPercent}%',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: zone.utilizationRatio,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr(
                  'zoneSlotsArticlesLine',
                  <String, Object>{
                    'occupied': zone.occupiedStorageSlots,
                    'total': zone.totalStorageSlots,
                    'articles': zone.articleCount,
                  },
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr(
                  'zoneFlowLine',
                  <String, Object>{
                    'inbound': zone.inboundPerDay,
                    'throughput': zone.throughputPerDay,
                    'pick': zone.pickRatePerHour,
                  },
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              AbcAnalysisBar(
                aCount: zone.abcAnalysis.aCount,
                bCount: zone.abcAnalysis.bCount,
                cCount: zone.abcAnalysis.cCount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
            Text(
              value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
