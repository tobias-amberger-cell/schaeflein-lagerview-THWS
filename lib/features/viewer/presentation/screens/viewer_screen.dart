import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse_heatmap_layer.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/abc_analysis_bar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../domain/viewer_adapter.dart';
import '../../domain/viewer_adapter_factory.dart';
import '../../domain/viewer_type.dart';
import '../widgets/glb_3d_viewer.dart';
import '../widgets/heatmap_zone_overlay.dart';
import '../widgets/native_warehouse_3d_view.dart';
import '../widgets/unity_runtime_view.dart';
import '../widgets/unity_source_notice.dart';

String _fileNameFromPath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
    return path;
  }
  final parts = normalized.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? normalized : parts.last;
}

class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewState = context.select<AppState, _ViewerUiState>((state) {
      final warehouse = state.riskFocusWarehouse;
      return _ViewerUiState(
        warehouse: warehouse,
        canUseControls: state.canUseViewerControls,
        viewerType: state.viewerType,
        isWarehousesSyncing: state.isWarehousesSyncing,
        zonesVisible: state.viewerZonesVisible,
        tourRunning: state.viewerTourRunning,
        heatmapVisible: state.viewerHeatmapVisible,
        heatmapMetric: state.viewerHeatmapMetric,
        heatmapZoneTypeFilterKey: state.viewerHeatmapZoneTypeFilter,
        heatmapSeverityFilterKey: state.viewerHeatmapSeverityFilter,
        heatmapLiveModeEnabled: state.viewerHeatmapLiveModeEnabled,
        heatmapAutoFocusEnabled: state.viewerHeatmapAutoFocusEnabled,
        focusZoneName: state.viewerFocusZoneName,
        focusRequestId: state.viewerFocusRequestId,
        focusRackNumber: state.viewerFocusRackNumber,
        focusLevelNumber: state.viewerFocusLevelNumber,
        focusSlotNumber: state.viewerFocusSlotNumber,
        focusLocationRequestId: state.viewerFocusLocationRequestId,
        storageLocations: warehouse == null
            ? const <WarehouseStorageLocation>[]
            : state.getStorageLocationsForWarehouse(warehouse.id),
        selectedStorageLocation: state.selectedStorageLocation,
        storagePrefs: _StorageLocationPrefs.fromState(state),
        resetCount: state.viewerResetCount,
        lastWarehouseSyncAt: state.lastWarehouseSyncAt,
        warehouseApiError: state.warehouseApiError,
        isWarehouseOfflineMode: state.isWarehouseOfflineMode,
        isGeneratingModel:
            warehouse != null &&
            state.hasModelGenerationInProgress(warehouse.id),
        warehouseHeatmapLayer: state.warehouseHeatmapLayer,
        externalModelPath: warehouse == null
            ? null
            : state.getExternalModelPathForWarehouse(warehouse.id),
      );
    });
    final appState = context.read<AppState>();
    final warehouse = viewState.warehouse;
    final canUseControls = viewState.canUseControls;
    final hasBackendIssue =
        viewState.warehouseApiError != null &&
        viewState.warehouseApiError!.trim().isNotEmpty;

    if (warehouse == null) {
      unawaited(appState.syncWarehouses(force: true));
      final isSyncing = viewState.isWarehousesSyncing;
      final message = isSyncing
          ? 'Lagerdaten werden aus der API geladen...'
          : (viewState.warehouseApiError?.trim().isNotEmpty ?? false)
              ? viewState.warehouseApiError!.trim()
              : 'Keine Lagerdaten aus der API gefunden. Bitte API pruefen und erneut laden.';
      return EmptyState(
        icon: Icons.view_in_ar_outlined,
        title: '3D Ansicht wird vorbereitet',
        message: message,
        actionLabel: isSyncing ? null : context.tr('retry'),
        onAction: isSyncing ? null : () => appState.syncWarehouses(force: true),
      );
    }
    unawaited(
      appState.ensureStorageLocationsLoadedForWarehouse(
        warehouse.id,
        limit: 120,
      ),
    );
    unawaited(appState.ensureWarehouseHeatmapLayerLoaded());

    final adapter = ViewerAdapterFactory.create(viewState.viewerType);
    final heatmapData = _buildHeatmapData(warehouse);
    final viewport = MediaQuery.sizeOf(context);
    final isTablet = viewport.shortestSide >= 700;
    final viewerHeight =
        (isTablet ? viewport.height * 0.72 : viewport.height * 0.58)
            .clamp(420.0, 900.0)
            .toDouble();
    final useWebSplitLayout = kIsWeb && viewport.width >= 1180;

    final viewerCanvasHeaderCard = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    context.tr('viewerCanvasTitle'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  StatusPill(
                    icon: Icons.warehouse_outlined,
                    label: warehouse.name,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.66),
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    borderColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.24),
                  ),
                  if (viewState.externalModelPath != null)
                    StatusPill(
                      icon: Icons.view_in_ar_outlined,
                      label: _fileNameFromPath(viewState.externalModelPath!),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      borderColor: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: canUseControls
                  ? () => _openTourFullscreen(
                      context: context,
                      warehouse: warehouse,
                    )
                  : null,
              tooltip: context.tr('viewerFullscreenTour'),
              icon: const Icon(Icons.fullscreen_rounded),
            ),
          ],
        ),
      ),
    );

    final warehouseMetaCard = _WarehouseMeta(warehouse: warehouse);
    final storageLocationCard = _StorageLocationCard(
      warehouse: warehouse,
      initialRack: viewState.focusRackNumber,
      initialLevel: viewState.focusLevelNumber,
      initialSlot: viewState.focusSlotNumber,
      canUseControls: canUseControls,
      samples: viewState.storageLocations,
      prefs: viewState.storagePrefs,
      onFocus: canUseControls
          ? (rack, level, slot) {
              final match = viewState.storageLocations.firstWhere(
                (sample) =>
                    sample.rackNumber == rack &&
                    sample.levelNumber == level &&
                    sample.slotNumber == slot,
                orElse: () => const WarehouseStorageLocation(
                  placeId: '',
                  area: '',
                  rackNumber: 0,
                  levelNumber: 0,
                  slotNumber: 0,
                  abcClass: '',
                  status: '',
                ),
              );
              appState.setSelectedStorageLocation(
                match.rackNumber == 0 ? null : match,
              );
              appState.requestViewerStorageFocus(
                rack: rack,
                level: level,
                slot: slot,
              );
            }
          : null,
    );
    final storageLocationDetailsCard = _StorageLocationDetailsCard(
      selected: viewState.selectedStorageLocation,
      fallbackRack: viewState.focusRackNumber,
      fallbackLevel: viewState.focusLevelNumber,
      fallbackSlot: viewState.focusSlotNumber,
    );
    final modelGenerationCard = _ModelGenerationCard(
      warehouse: warehouse,
      isGenerating: viewState.isGeneratingModel,
      onGenerate: canUseControls
          ? () => _generateModel(context: context, warehouse: warehouse)
          : null,
    );
    final externalModelCard = viewState.externalModelPath == null
        ? null
        : _ExternalModelCard(modelPath: viewState.externalModelPath!);
    final backendStatusCard =
        viewState.warehouseApiError != null || viewState.isWarehouseOfflineMode
        ? _ViewerBackendStatusCard(
            apiError: viewState.warehouseApiError,
            isOfflineMode: viewState.isWarehouseOfflineMode,
            showRetryAction: canUseControls,
            onRetry: viewState.isGeneratingModel
                ? null
                : () => _generateModel(context: context, warehouse: warehouse),
          )
        : null;
    final viewerDetailsPanel = _ViewerDetailsPanel(
      warehouseMetaCard: warehouseMetaCard,
      storageLocationDetailsCard: storageLocationDetailsCard,
      modelGenerationCard: modelGenerationCard,
      externalModelCard: externalModelCard,
      backendStatusCard: backendStatusCard,
    );
    final heatmapOverviewCard = heatmapData.isNotEmpty
        ? _HeatmapOverviewCard(
            entries: heatmapData,
            metric: viewState.heatmapMetric,
            selectedZoneTypeFilterKey: viewState.heatmapZoneTypeFilterKey,
            onZoneTypeFilterChanged: (value) =>
                _setHeatmapZoneTypeFilter(context: context, value: value),
            onFocusTopZone: (entry) =>
                _requestFocusOnZone(context: context, zoneName: entry.zoneName),
            onOpenTopZoneDetails: (entry) => _openZoneDetails(
              context: context,
              warehouse: warehouse,
              entry: entry,
              metric: viewState.heatmapMetric,
            ),
          )
        : null;
    final viewerActionPanel = _ViewerActionPanel(
      canUseControls: canUseControls && !viewState.isGeneratingModel,
      zonesVisible: viewState.zonesVisible,
      tourRunning: viewState.tourRunning,
      heatmapVisible: viewState.heatmapVisible,
      heatmapMetric: viewState.heatmapMetric,
      onReset: () =>
          _onReset(context: context, adapter: adapter, warehouse: warehouse),
      onToggleZones: () => _toggleZones(
        context: context,
        adapter: adapter,
        warehouse: warehouse,
      ),
      onToggleTour: () =>
          _toggleTour(context: context, adapter: adapter, warehouse: warehouse),
      onSelectMetric: (metric) => _setHeatmapMetric(
        context: context,
        adapter: adapter,
        warehouse: warehouse,
        metric: metric,
      ),
      onToggleHeatmap: () => _toggleHeatmap(
        context: context,
        adapter: adapter,
        warehouse: warehouse,
      ),
      canFocusCriticalZone: warehouse.generatedModel?.zones.isNotEmpty ?? false,
      onFocusCriticalZone: () => _focusCriticalZone(
        context: context,
        warehouse: warehouse,
        metric: viewState.heatmapMetric,
        heatmapData: heatmapData,
      ),
    );
    return ListView(
      children: <Widget>[
        _ViewerHeaderBar(
          warehouseName: warehouse.name,
          adapterStatusLabel: context.tr(adapter.statusText),
          hasBackendIssue: hasBackendIssue,
          isOfflineMode: viewState.isWarehouseOfflineMode,
          isSyncing: viewState.isWarehousesSyncing,
          lastSyncAt: viewState.lastWarehouseSyncAt,
          onOpenWarehouses: () => context.go('/warehouses'),
          onOpenDashboard: () => context.go('/dashboard'),
          onRefresh: viewState.isWarehousesSyncing
              ? null
              : () => _syncWarehouseData(
                  context: context,
                  showFeedback: true,
                  warehouseId: warehouse.id,
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (useWebSplitLayout)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    viewerCanvasHeaderCard,
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: viewerHeight,
                      child: _ViewerCanvas(
                        adapter: adapter,
                        warehouse: warehouse,
                        isGeneratingModel: viewState.isGeneratingModel,
                        zonesVisible: viewState.zonesVisible,
                        tourRunning: viewState.tourRunning,
                        heatmapVisible: viewState.heatmapVisible,
                        heatmapMetric: viewState.heatmapMetric,
                        heatmapData: heatmapData,
                        warehouseHeatmapLayer: viewState.warehouseHeatmapLayer,
                        generatedModel: warehouse.generatedModel,
                        focusZoneName: viewState.focusZoneName,
                        focusRequestId: viewState.focusRequestId,
                        focusRackNumber: viewState.focusRackNumber,
                        focusLevelNumber: viewState.focusLevelNumber,
                        focusSlotNumber: viewState.focusSlotNumber,
                        focusLocationRequestId:
                            viewState.focusLocationRequestId,
                        externalModelPath: viewState.externalModelPath,
                        onZoneTap: (entry, metric) {
                          _focusAndOpenZoneDetails(
                            context: context,
                            warehouse: warehouse,
                            entry: entry,
                            metric: metric,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    viewerActionPanel,
                    if (heatmapOverviewCard != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      heatmapOverviewCard,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    storageLocationCard,
                    const SizedBox(height: AppSpacing.md),
                    viewerDetailsPanel,
                  ],
                ),
              ),
            ],
          )
        else ...<Widget>[
          viewerCanvasHeaderCard,
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: viewerHeight,
            child: _ViewerCanvas(
              adapter: adapter,
              warehouse: warehouse,
              isGeneratingModel: viewState.isGeneratingModel,
              zonesVisible: viewState.zonesVisible,
              tourRunning: viewState.tourRunning,
              heatmapVisible: viewState.heatmapVisible,
              heatmapMetric: viewState.heatmapMetric,
              heatmapData: heatmapData,
              warehouseHeatmapLayer: viewState.warehouseHeatmapLayer,
              generatedModel: warehouse.generatedModel,
              focusZoneName: viewState.focusZoneName,
              focusRequestId: viewState.focusRequestId,
              focusRackNumber: viewState.focusRackNumber,
              focusLevelNumber: viewState.focusLevelNumber,
              focusSlotNumber: viewState.focusSlotNumber,
              focusLocationRequestId: viewState.focusLocationRequestId,
              externalModelPath: viewState.externalModelPath,
              onZoneTap: (entry, metric) {
                _focusAndOpenZoneDetails(
                  context: context,
                  warehouse: warehouse,
                  entry: entry,
                  metric: metric,
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          viewerActionPanel,
          if (heatmapOverviewCard != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            heatmapOverviewCard,
          ],
          const SizedBox(height: AppSpacing.md),
          storageLocationCard,
          const SizedBox(height: AppSpacing.md),
          viewerDetailsPanel,
        ],
        if (!canUseControls) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr('viewerRoleHint'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  Future<void> _onReset({
    required BuildContext context,
    required ViewerAdapter adapter,
    required Warehouse warehouse,
  }) async {
    final appState = context.read<AppState>();
    appState.resetViewerState();
    final l10n = context.l10n;
    final message = await adapter.resetView(l10n, warehouse);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generateModel({
    required BuildContext context,
    required Warehouse warehouse,
  }) async {
    final appState = context.read<AppState>();
    final success = await appState.generateWarehouseModel(warehouse.id);
    if (!context.mounted) {
      return;
    }
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('viewerModelGeneratedSuccess'))),
      );
      return;
    }
    final message =
        appState.warehouseApiError ?? context.tr('viewerModelGeneratedError');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleZones({
    required BuildContext context,
    required ViewerAdapter adapter,
    required Warehouse warehouse,
  }) async {
    final appState = context.read<AppState>();
    final enableZones = !appState.viewerZonesVisible;
    appState.setViewerZonesVisible(enableZones);
    final l10n = context.l10n;
    final message = enableZones
        ? await adapter.showZones(l10n, warehouse)
        : l10n.tr('zonesHiddenMsg');
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleTour({
    required BuildContext context,
    required ViewerAdapter adapter,
    required Warehouse warehouse,
  }) async {
    final appState = context.read<AppState>();
    final enableTour = !appState.viewerTourRunning;
    appState.setViewerTourRunning(enableTour);
    final l10n = context.l10n;
    if (enableTour) {
      await adapter.startTour(l10n, warehouse);
      if (!context.mounted) {
        return;
      }
      await context.push('/viewer/tour');
      return;
    }

    final message = l10n.tr('tourPausedMsg');
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openTourFullscreen({
    required BuildContext context,
    required Warehouse warehouse,
  }) async {
    final appState = context.read<AppState>();
    appState.setViewerTourRunning(true);
    if (!context.mounted) {
      return;
    }
    await context.push('/viewer/tour');
  }

  Future<void> _setHeatmapMetric({
    required BuildContext context,
    required ViewerAdapter adapter,
    required Warehouse warehouse,
    required ViewerHeatmapMetric metric,
  }) async {
    final appState = context.read<AppState>();
    appState.setViewerHeatmapMetric(metric);
    final l10n = context.l10n;
    final message = appState.viewerHeatmapVisible
        ? await adapter.showHeatmap(l10n, warehouse, metric)
        : l10n.tr('heatmapMetricChangedMsg', <String, Object>{
            'metric': l10n.tr(metric.labelKey),
          });
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleHeatmap({
    required BuildContext context,
    required ViewerAdapter adapter,
    required Warehouse warehouse,
  }) async {
    final appState = context.read<AppState>();
    final enableHeatmap = !appState.viewerHeatmapVisible;
    appState.setViewerHeatmapVisible(enableHeatmap);
    final l10n = context.l10n;
    final message = enableHeatmap
        ? await adapter.showHeatmap(
            l10n,
            warehouse,
            appState.viewerHeatmapMetric,
          )
        : await adapter.hideHeatmap(l10n, warehouse);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _requestFocusOnZone({
    required BuildContext context,
    required String zoneName,
  }) {
    final appState = context.read<AppState>();
    appState.requestViewerZoneFocus(zoneName);
  }

  void _focusAndOpenZoneDetails({
    required BuildContext context,
    required Warehouse warehouse,
    required ViewerHeatmapEntry entry,
    required ViewerHeatmapMetric metric,
  }) {
    _requestFocusOnZone(context: context, zoneName: entry.zoneName);
    _openZoneDetails(
      context: context,
      warehouse: warehouse,
      entry: entry,
      metric: metric,
    );
  }

  void _focusCriticalZone({
    required BuildContext context,
    required Warehouse warehouse,
    required ViewerHeatmapMetric metric,
    required List<ViewerHeatmapEntry> heatmapData,
  }) {
    final hasModelZones = warehouse.generatedModel?.zones.isNotEmpty ?? false;
    if (!hasModelZones || heatmapData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('viewerNoModelZonesForFocus'))),
      );
      return;
    }

    final sorted = <ViewerHeatmapEntry>[...heatmapData]
      ..sort((a, b) => b.valueFor(metric).compareTo(a.valueFor(metric)));
    final target = sorted.first;
    _requestFocusOnZone(context: context, zoneName: target.zoneName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('viewerFocusCriticalZoneMsg', <String, Object>{
            'zone': target.zoneName,
          }),
        ),
      ),
    );
  }

  List<ViewerHeatmapEntry> _buildHeatmapData(Warehouse warehouse) {
    final maxPick = warehouse.zones
        .map((zone) => zone.pickRatePerHour)
        .fold<int>(1, (prev, value) => value > prev ? value : prev);
    final modelZones =
        warehouse.generatedModel?.zones ?? const <WarehouseModelZone>[];

    return warehouse.zones
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final zone = entry.value;
          final modelZone = _matchModelZone(
            modelZones: modelZones,
            zoneName: zone.name,
            zoneIndex: index,
          );
          final congestion =
              ((zone.utilizationRatio * 0.7) +
                      ((zone.inboundPerDay / (zone.throughputPerDay + 1)) *
                          0.3))
                  .clamp(0, 1)
                  .toDouble();
          final fallbackPickRate = (zone.pickRatePerHour / maxPick)
              .clamp(0, 1)
              .toDouble();
          return ViewerHeatmapEntry(
            zoneId: zone.id,
            zoneName: zone.name,
            utilization: modelZone?.utilization ?? zone.utilizationRatio,
            pickRate: modelZone?.pickRate ?? fallbackPickRate,
            congestion: modelZone?.congestion ?? congestion,
            abcA:
                modelZone?.abcA ??
                zone.abcAnalysis.aRatio.clamp(0, 1).toDouble(),
          );
        })
        .toList(growable: false);
  }

  WarehouseModelZone? _matchModelZone({
    required List<WarehouseModelZone> modelZones,
    required String zoneName,
    required int zoneIndex,
  }) {
    if (modelZones.isEmpty) {
      return null;
    }
    final normalizedZoneName = _normalizeZoneNameForMatching(zoneName);
    for (final modelZone in modelZones) {
      if (_normalizeZoneNameForMatching(modelZone.name) == normalizedZoneName) {
        return modelZone;
      }
    }
    if (zoneIndex >= 0 && zoneIndex < modelZones.length) {
      return modelZones[zoneIndex];
    }
    return null;
  }

  String _normalizeZoneNameForMatching(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _openZoneDetails({
    required BuildContext context,
    required Warehouse warehouse,
    required ViewerHeatmapEntry entry,
    required ViewerHeatmapMetric metric,
  }) async {
    WarehouseZone? zone;
    for (final current in warehouse.zones) {
      if (current.id == entry.zoneId || current.name == entry.zoneName) {
        zone = current;
        break;
      }
    }
    if (zone == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ZoneDetailsSheet(
        zone: zone!,
        metric: metric,
        metricValue: entry.valueFor(metric),
      ),
    );
  }

  Future<void> _syncWarehouseData({
    required BuildContext context,
    required bool showFeedback,
    required String warehouseId,
  }) async {
    final appState = context.read<AppState>();
    await appState.syncWarehouses();
    await appState.syncWarehouseModelFromApi(
      warehouseId,
      suppressErrors: true,
      notify: false,
    );
    if (!context.mounted || !showFeedback) {
      return;
    }
    final error = appState.warehouseApiError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('warehousesSyncError', <String, Object>{'error': error}),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr('viewerDataUpdated'))));
  }

  void _setHeatmapZoneTypeFilter({
    required BuildContext context,
    required String value,
  }) {
    context.read<AppState>().setViewerHeatmapZoneTypeFilter(value);
  }

}

class _ViewerDetailsPanel extends StatelessWidget {
  const _ViewerDetailsPanel({
    required this.warehouseMetaCard,
    required this.storageLocationDetailsCard,
    required this.modelGenerationCard,
    this.externalModelCard,
    this.backendStatusCard,
  });

  final Widget warehouseMetaCard;
  final Widget storageLocationDetailsCard;
  final Widget modelGenerationCard;
  final Widget? externalModelCard;
  final Widget? backendStatusCard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        title: Text(
          'Details und Stammdaten',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Lagerstammdaten, Stellplatz-Fokus und Modellstatus',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: <Widget>[
          warehouseMetaCard,
          const SizedBox(height: AppSpacing.sm),
          storageLocationDetailsCard,
          const SizedBox(height: AppSpacing.sm),
          modelGenerationCard,
          if (externalModelCard != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            externalModelCard!,
          ],
          if (backendStatusCard != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            backendStatusCard!,
          ],
        ],
      ),
    );
  }
}

class _HeatmapOverviewCard extends StatefulWidget {
  const _HeatmapOverviewCard({
    required this.entries,
    required this.metric,
    required this.selectedZoneTypeFilterKey,
    required this.onZoneTypeFilterChanged,
    required this.onFocusTopZone,
    required this.onOpenTopZoneDetails,
  });

  final List<ViewerHeatmapEntry> entries;
  final ViewerHeatmapMetric metric;
  final String selectedZoneTypeFilterKey;
  final ValueChanged<String> onZoneTypeFilterChanged;
  final ValueChanged<ViewerHeatmapEntry> onFocusTopZone;
  final ValueChanged<ViewerHeatmapEntry> onOpenTopZoneDetails;

  @override
  State<_HeatmapOverviewCard> createState() => _HeatmapOverviewCardState();
}

class _HeatmapOverviewCardState extends State<_HeatmapOverviewCard> {
  late _ZoneTypeFilter _zoneTypeFilter;

  @override
  void initState() {
    super.initState();
    _zoneTypeFilter = _zoneTypeFilterFromKey(widget.selectedZoneTypeFilterKey);
  }

  @override
  void didUpdateWidget(covariant _HeatmapOverviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedZoneTypeFilterKey !=
        widget.selectedZoneTypeFilterKey) {
      _zoneTypeFilter = _zoneTypeFilterFromKey(
        widget.selectedZoneTypeFilterKey,
      );
    }
  }

  List<ViewerHeatmapEntry> _filteredEntries() {
    final source = <ViewerHeatmapEntry>[...widget.entries]
      ..sort(
        (a, b) =>
            b.valueFor(widget.metric).compareTo(a.valueFor(widget.metric)),
      );
    return source
        .where((entry) {
          if (_zoneTypeFilter == _ZoneTypeFilter.all) {
            return true;
          }
          return _classifyHeatmapZoneType(entry.zoneName) == _zoneTypeFilter;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final filteredEntries = _filteredEntries();
    final values = filteredEntries
        .map((entry) => entry.valueFor(widget.metric).clamp(0, 1).toDouble())
        .toList(growable: false);
    final average = values.isEmpty
        ? 0
        : values.fold<double>(0, (sum, value) => sum + value) / values.length;
    final criticalCount = values.where((value) => value >= 0.85).length;
    final highCount = values
        .where((value) => value >= 0.65 && value < 0.85)
        .length;
    final lowCount = values.where((value) => value < 0.65).length;
    final topEntry = filteredEntries.isEmpty ? null : filteredEntries.first;
    final topValue =
        topEntry?.valueFor(widget.metric).clamp(0, 1).toDouble() ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.query_stats_outlined, size: 20),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.tr('heatmapOverviewTitle'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _SeverityBadge(
                  label: context.tr(widget.metric.labelKey),
                  color: heatColorForValue(topValue),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('heatmapOverviewSubtitle'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Icon(
                  Icons.category_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  context.tr('heatmapZoneTypeLabel'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_ZoneTypeFilter>(
                segments: <ButtonSegment<_ZoneTypeFilter>>[
                  ButtonSegment<_ZoneTypeFilter>(
                    value: _ZoneTypeFilter.all,
                    label: Text(_ZoneTypeFilter.all.label(context)),
                  ),
                  ButtonSegment<_ZoneTypeFilter>(
                    value: _ZoneTypeFilter.inbound,
                    label: Text(_ZoneTypeFilter.inbound.label(context)),
                  ),
                  ButtonSegment<_ZoneTypeFilter>(
                    value: _ZoneTypeFilter.picking,
                    label: Text(_ZoneTypeFilter.picking.label(context)),
                  ),
                  ButtonSegment<_ZoneTypeFilter>(
                    value: _ZoneTypeFilter.shipping,
                    label: Text(_ZoneTypeFilter.shipping.label(context)),
                  ),
                  ButtonSegment<_ZoneTypeFilter>(
                    value: _ZoneTypeFilter.storage,
                    label: Text(_ZoneTypeFilter.storage.label(context)),
                  ),
                  ButtonSegment<_ZoneTypeFilter>(
                    value: _ZoneTypeFilter.other,
                    label: Text(_ZoneTypeFilter.other.label(context)),
                  ),
                ],
                selected: <_ZoneTypeFilter>{_zoneTypeFilter},
                onSelectionChanged: (selection) {
                  final selected = selection.first;
                  setState(() {
                    _zoneTypeFilter = selected;
                  });
                  widget.onZoneTypeFilterChanged(selected.key);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (topEntry != null)
              Text(
                '${context.tr('heatmapTopZoneLabel')}: ${topEntry.zoneName}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              )
            else
              Text(
                context.tr('heatmapNoZonesForType'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: average.clamp(0, 1).toDouble(),
                color: heatColorForValue(average.toDouble()),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('heatmapAverageLabel', <String, Object>{
                'value': '${(average * 100).round()}%',
              }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _ZoneCountChip(
                  label: context.tr('severityCritical'),
                  count: criticalCount,
                  color: heatColorForValue(0.9),
                ),
                _ZoneCountChip(
                  label: context.tr('heatmapSeverityHigh'),
                  count: highCount,
                  color: heatColorForValue(0.7),
                ),
                _ZoneCountChip(
                  label: context.tr('heatmapSeverityLow'),
                  count: lowCount,
                  color: heatColorForValue(0.3),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: topEntry == null
                      ? null
                      : () => widget.onFocusTopZone(topEntry),
                  icon: const Icon(Icons.center_focus_strong_rounded),
                  label: Text(context.tr('heatmapFocusTopZone')),
                ),
                TextButton.icon(
                  onPressed: topEntry == null
                      ? null
                      : () => widget.onOpenTopZoneDetails(topEntry),
                  icon: const Icon(Icons.info_outline),
                  label: Text(context.tr('heatmapOpenTopZoneDetails')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneCountChip extends StatelessWidget {
  const _ZoneCountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.48)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          '$label: $count',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

enum _ZoneSeverityFilter { all, high, critical }

extension _ZoneSeverityFilterX on _ZoneSeverityFilter {
  String get key {
    return switch (this) {
      _ZoneSeverityFilter.all => 'all',
      _ZoneSeverityFilter.high => 'high',
      _ZoneSeverityFilter.critical => 'critical',
    };
  }

  String label(BuildContext context) {
    return switch (this) {
      _ZoneSeverityFilter.all => context.tr('all'),
      _ZoneSeverityFilter.high => context.tr('heatmapSeverityHigh'),
      _ZoneSeverityFilter.critical => context.tr('severityCritical'),
    };
  }
}

enum _ZoneTypeFilter { all, inbound, picking, shipping, storage, other }

extension _ZoneTypeFilterX on _ZoneTypeFilter {
  String get key {
    return switch (this) {
      _ZoneTypeFilter.all => 'all',
      _ZoneTypeFilter.inbound => 'inbound',
      _ZoneTypeFilter.picking => 'picking',
      _ZoneTypeFilter.shipping => 'shipping',
      _ZoneTypeFilter.storage => 'storage',
      _ZoneTypeFilter.other => 'other',
    };
  }

  String label(BuildContext context) {
    return switch (this) {
      _ZoneTypeFilter.all => context.tr('all'),
      _ZoneTypeFilter.inbound => context.tr('heatmapZoneTypeInbound'),
      _ZoneTypeFilter.picking => context.tr('heatmapZoneTypePicking'),
      _ZoneTypeFilter.shipping => context.tr('heatmapZoneTypeShipping'),
      _ZoneTypeFilter.storage => context.tr('heatmapZoneTypeStorage'),
      _ZoneTypeFilter.other => context.tr('heatmapZoneTypeOther'),
    };
  }
}

_ZoneSeverityFilter _zoneSeverityFilterFromKey(String key) {
  switch (key) {
    case 'critical':
      return _ZoneSeverityFilter.critical;
    case 'high':
      return _ZoneSeverityFilter.high;
    case 'all':
    default:
      return _ZoneSeverityFilter.all;
  }
}

_ZoneTypeFilter _zoneTypeFilterFromKey(String key) {
  switch (key) {
    case 'inbound':
      return _ZoneTypeFilter.inbound;
    case 'picking':
      return _ZoneTypeFilter.picking;
    case 'shipping':
      return _ZoneTypeFilter.shipping;
    case 'storage':
      return _ZoneTypeFilter.storage;
    case 'other':
      return _ZoneTypeFilter.other;
    case 'all':
    default:
      return _ZoneTypeFilter.all;
  }
}

_ZoneTypeFilter _classifyHeatmapZoneType(String zoneName) {
  final normalized = zoneName.trim().toLowerCase();
  if (normalized.contains('wareneingang') ||
      normalized.contains('eingang') ||
      normalized.contains('inbound') ||
      normalized.contains('receiving')) {
    return _ZoneTypeFilter.inbound;
  }
  if (normalized.contains('kommission') ||
      normalized.contains('picking') ||
      normalized.contains('pick')) {
    return _ZoneTypeFilter.picking;
  }
  if (normalized.contains('versand') ||
      normalized.contains('ausgang') ||
      normalized.contains('shipping') ||
      normalized.contains('outbound') ||
      normalized.contains('dispatch')) {
    return _ZoneTypeFilter.shipping;
  }
  if (normalized.contains('lager') ||
      normalized.contains('storage') ||
      normalized.contains('hochregal') ||
      normalized.contains('reserve')) {
    return _ZoneTypeFilter.storage;
  }
  return _ZoneTypeFilter.other;
}

class _CriticalZonesStrip extends StatefulWidget {
  const _CriticalZonesStrip({
    required this.entries,
    required this.metric,
    required this.selectedSeverityFilterKey,
    required this.selectedZoneTypeFilterKey,
    required this.liveModeEnabled,
    required this.autoFocusEnabled,
    required this.onSeverityFilterChanged,
    required this.onZoneTypeFilterChanged,
    required this.onLiveModeChanged,
    required this.onAutoFocusChanged,
    required this.onTapZone,
    required this.onOpenDetails,
  });

  final List<ViewerHeatmapEntry> entries;
  final ViewerHeatmapMetric metric;
  final String selectedSeverityFilterKey;
  final String selectedZoneTypeFilterKey;
  final bool liveModeEnabled;
  final bool autoFocusEnabled;
  final ValueChanged<String> onSeverityFilterChanged;
  final ValueChanged<String> onZoneTypeFilterChanged;
  final ValueChanged<bool> onLiveModeChanged;
  final ValueChanged<bool> onAutoFocusChanged;
  final ValueChanged<ViewerHeatmapEntry> onTapZone;
  final ValueChanged<ViewerHeatmapEntry> onOpenDetails;

  @override
  State<_CriticalZonesStrip> createState() => _CriticalZonesStripState();
}

class _CriticalZonesStripState extends State<_CriticalZonesStrip> {
  late _ZoneSeverityFilter _filter;
  late _ZoneTypeFilter _zoneTypeFilter;
  late bool _autoFocusEnabled;
  late bool _liveModeEnabled;
  int _autoFocusIndex = 0;
  int _liveTick = 0;
  Timer? _autoFocusTimer;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _filter = _zoneSeverityFilterFromKey(widget.selectedSeverityFilterKey);
    _zoneTypeFilter = _zoneTypeFilterFromKey(widget.selectedZoneTypeFilterKey);
    _liveModeEnabled = widget.liveModeEnabled;
    _autoFocusEnabled = widget.autoFocusEnabled;
    _syncLiveTimer();
    _syncAutoFocusTimer();
  }

  @override
  void didUpdateWidget(covariant _CriticalZonesStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metric != widget.metric) {
      _autoFocusIndex = 0;
    }
    if (oldWidget.selectedSeverityFilterKey !=
        widget.selectedSeverityFilterKey) {
      _filter = _zoneSeverityFilterFromKey(widget.selectedSeverityFilterKey);
      _autoFocusIndex = 0;
    }
    if (oldWidget.selectedZoneTypeFilterKey !=
        widget.selectedZoneTypeFilterKey) {
      _zoneTypeFilter = _zoneTypeFilterFromKey(
        widget.selectedZoneTypeFilterKey,
      );
      _autoFocusIndex = 0;
    }
    if (oldWidget.liveModeEnabled != widget.liveModeEnabled) {
      _liveModeEnabled = widget.liveModeEnabled;
    }
    if (oldWidget.autoFocusEnabled != widget.autoFocusEnabled) {
      _autoFocusEnabled = widget.autoFocusEnabled;
      _autoFocusIndex = 0;
    }
    _syncLiveTimer();
    _syncAutoFocusTimer();
  }

  @override
  void dispose() {
    _autoFocusTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  List<ViewerHeatmapEntry> _filteredEntries() {
    final source = <ViewerHeatmapEntry>[...widget.entries]
      ..sort((a, b) => _entryValue(b).compareTo(_entryValue(a)));
    return source
        .where((entry) {
          final value = _entryValue(entry);
          final matchesSeverity = switch (_filter) {
            _ZoneSeverityFilter.all => true,
            _ZoneSeverityFilter.high => value >= 0.65,
            _ZoneSeverityFilter.critical => value >= 0.85,
          };
          final matchesZoneType = switch (_zoneTypeFilter) {
            _ZoneTypeFilter.all => true,
            _ => _classifyHeatmapZoneType(entry.zoneName) == _zoneTypeFilter,
          };
          return matchesSeverity && matchesZoneType;
        })
        .toList(growable: false);
  }

  double _entryValue(ViewerHeatmapEntry entry) {
    final base = entry.valueFor(widget.metric).clamp(0, 1).toDouble();
    if (!_liveModeEnabled) {
      return base;
    }
    final zoneSeed =
        ((entry.zoneName.hashCode ^ entry.zoneId.hashCode) & 0x7FFFFFFF) % 1000;
    final phase = (_liveTick * 0.38) + (zoneSeed / 115.0);
    final modulation = math.sin(phase) * 0.06;
    final volatility = base >= 0.75
        ? 0.05
        : base >= 0.45
        ? 0.035
        : 0.02;
    final trend = math.cos((phase * 0.6) + (zoneSeed / 300)) * volatility;
    return (base + modulation + trend).clamp(0, 1).toDouble();
  }

  void _syncLiveTimer() {
    _liveTimer?.cancel();
    if (!_liveModeEnabled || !mounted) {
      return;
    }
    final interval = kIsWeb
        ? const Duration(seconds: 5)
        : const Duration(seconds: 2);
    _liveTimer = Timer.periodic(interval, (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _liveTick += 1;
      });
    });
  }

  void _syncAutoFocusTimer() {
    _autoFocusTimer?.cancel();
    final filtered = _filteredEntries();
    if (!_autoFocusEnabled || filtered.isEmpty) {
      return;
    }
    final interval = kIsWeb
        ? const Duration(seconds: 9)
        : const Duration(seconds: 4);
    _autoFocusTimer = Timer.periodic(interval, (_) {
      if (!mounted) {
        return;
      }
      final current = _filteredEntries();
      if (current.isEmpty) {
        return;
      }
      final target = current[_autoFocusIndex % current.length];
      widget.onTapZone(target);
      _autoFocusIndex = (_autoFocusIndex + 1) % current.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final filteredEntries = _filteredEntries();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= AppBreakpoints.tablet;
            final stripHeight = isTablet ? 62.0 : 54.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.priority_high_rounded, size: 18),
                    Text(
                      context.tr('heatmapCriticalZonesTitle'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    StatusPill(
                      icon: Icons.speed_rounded,
                      label: context.tr(widget.metric.labelKey),
                      compact: true,
                    ),
                    if (_liveModeEnabled)
                      StatusPill(
                        icon: Icons.sensors_rounded,
                        label: context.tr('heatmapLiveBadge'),
                        compact: true,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onTertiaryContainer,
                      ),
                    if (_autoFocusEnabled)
                      StatusPill(
                        icon: Icons.center_focus_strong_rounded,
                        label: context.tr('heatmapAutoFocusActive'),
                        compact: true,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.8),
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    IconButton.filledTonal(
                      tooltip: _liveModeEnabled
                          ? context.tr('heatmapLivePause')
                          : context.tr('heatmapLiveStart'),
                      onPressed: () {
                        final nextValue = !_liveModeEnabled;
                        setState(() {
                          _liveModeEnabled = nextValue;
                        });
                        _syncLiveTimer();
                        _syncAutoFocusTimer();
                        widget.onLiveModeChanged(nextValue);
                      },
                      icon: Icon(
                        _liveModeEnabled
                            ? Icons.sensors
                            : Icons.sensors_off_outlined,
                        size: 18,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: _autoFocusEnabled
                          ? context.tr('heatmapAutoFocusPause')
                          : context.tr('heatmapAutoFocusStart'),
                      onPressed: () {
                        final nextValue = !_autoFocusEnabled;
                        setState(() {
                          _autoFocusEnabled = nextValue;
                          _autoFocusIndex = 0;
                        });
                        _syncAutoFocusTimer();
                        widget.onAutoFocusChanged(nextValue);
                      },
                      icon: Icon(
                        _autoFocusEnabled
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_ZoneSeverityFilter>(
                    segments: <ButtonSegment<_ZoneSeverityFilter>>[
                      ButtonSegment<_ZoneSeverityFilter>(
                        value: _ZoneSeverityFilter.all,
                        label: Text(_ZoneSeverityFilter.all.label(context)),
                      ),
                      ButtonSegment<_ZoneSeverityFilter>(
                        value: _ZoneSeverityFilter.high,
                        label: Text(_ZoneSeverityFilter.high.label(context)),
                      ),
                      ButtonSegment<_ZoneSeverityFilter>(
                        value: _ZoneSeverityFilter.critical,
                        label: Text(
                          _ZoneSeverityFilter.critical.label(context),
                        ),
                      ),
                    ],
                    selected: <_ZoneSeverityFilter>{_filter},
                    onSelectionChanged: (selection) {
                      final selected = selection.first;
                      setState(() {
                        _filter = selected;
                        _autoFocusIndex = 0;
                      });
                      widget.onSeverityFilterChanged(selected.key);
                      _syncAutoFocusTimer();
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.category_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.tr('heatmapZoneTypeLabel'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_ZoneTypeFilter>(
                    segments: <ButtonSegment<_ZoneTypeFilter>>[
                      ButtonSegment<_ZoneTypeFilter>(
                        value: _ZoneTypeFilter.all,
                        label: Text(_ZoneTypeFilter.all.label(context)),
                      ),
                      ButtonSegment<_ZoneTypeFilter>(
                        value: _ZoneTypeFilter.inbound,
                        label: Text(_ZoneTypeFilter.inbound.label(context)),
                      ),
                      ButtonSegment<_ZoneTypeFilter>(
                        value: _ZoneTypeFilter.picking,
                        label: Text(_ZoneTypeFilter.picking.label(context)),
                      ),
                      ButtonSegment<_ZoneTypeFilter>(
                        value: _ZoneTypeFilter.shipping,
                        label: Text(_ZoneTypeFilter.shipping.label(context)),
                      ),
                      ButtonSegment<_ZoneTypeFilter>(
                        value: _ZoneTypeFilter.storage,
                        label: Text(_ZoneTypeFilter.storage.label(context)),
                      ),
                      ButtonSegment<_ZoneTypeFilter>(
                        value: _ZoneTypeFilter.other,
                        label: Text(_ZoneTypeFilter.other.label(context)),
                      ),
                    ],
                    selected: <_ZoneTypeFilter>{_zoneTypeFilter},
                    onSelectionChanged: (selection) {
                      final selected = selection.first;
                      setState(() {
                        _zoneTypeFilter = selected;
                        _autoFocusIndex = 0;
                      });
                      widget.onZoneTypeFilterChanged(selected.key);
                      _syncAutoFocusTimer();
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (filteredEntries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      context.tr('heatmapNoZonesForSelectedFilters'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  SizedBox(
                    height: stripHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filteredEntries.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        final value = _entryValue(entry);
                        final zoneColor = _heatColor(value);
                        final severityColor = _severityColor(value);

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onTapZone(entry),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: zoneColor.withValues(alpha: 0.14),
                              border: Border.all(
                                color: zoneColor.withValues(alpha: 0.72),
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: isTablet
                                    ? AppSpacing.sm
                                    : AppSpacing.xs,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.adjust_rounded,
                                    size: 14,
                                    color: zoneColor,
                                  ),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: isTablet ? 210 : 160,
                                    ),
                                    child: Text(
                                      entry.zoneName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _SeverityBadge(
                                    label: _severityLabel(context, value),
                                    color: severityColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${(value * 100).round()}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: zoneColor,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(width: 2),
                                  IconButton(
                                    tooltip: 'Details',
                                    onPressed: () =>
                                        widget.onOpenDetails(entry),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.info_outline,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _severityLabel(BuildContext context, double value) {
    if (value >= 0.85) {
      return context.tr('severityCritical');
    }
    if (value >= 0.65) {
      return context.tr('heatmapSeverityHigh');
    }
    if (value >= 0.45) {
      return context.tr('heatmapSeverityMedium');
    }
    return context.tr('heatmapSeverityLow');
  }

  Color _severityColor(double value) {
    return heatColorForValue(value);
  }

  Color _heatColor(double value) {
    return heatColorForValue(value);
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.62)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ViewerActionPanel extends StatelessWidget {
  const _ViewerActionPanel({
    required this.canUseControls,
    required this.zonesVisible,
    required this.tourRunning,
    required this.heatmapVisible,
    required this.heatmapMetric,
    required this.canFocusCriticalZone,
    required this.onReset,
    required this.onToggleZones,
    required this.onToggleTour,
    required this.onSelectMetric,
    required this.onToggleHeatmap,
    required this.onFocusCriticalZone,
  });

  final bool canUseControls;
  final bool zonesVisible;
  final bool tourRunning;
  final bool heatmapVisible;
  final ViewerHeatmapMetric heatmapMetric;
  final bool canFocusCriticalZone;
  final VoidCallback onReset;
  final VoidCallback onToggleZones;
  final VoidCallback onToggleTour;
  final ValueChanged<ViewerHeatmapMetric> onSelectMetric;
  final VoidCallback onToggleHeatmap;
  final VoidCallback onFocusCriticalZone;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      OutlinedButton.icon(
        onPressed: canUseControls ? onReset : null,
        icon: const Icon(Icons.refresh),
        label: Text(context.tr('viewerReset')),
      ),
      OutlinedButton.icon(
        onPressed: canUseControls ? onToggleZones : null,
        icon: Icon(
          zonesVisible ? Icons.grid_off_outlined : Icons.grid_view_outlined,
        ),
        label: Text(
          zonesVisible
              ? context.tr('viewerHideZones')
              : context.tr('viewerShowZones'),
        ),
      ),
      FilledButton.icon(
        onPressed: canUseControls ? onToggleTour : null,
        icon: Icon(
          tourRunning ? Icons.pause_circle_outline : Icons.play_circle_outline,
        ),
        label: Text(
          tourRunning
              ? context.tr('viewerPauseTour')
              : context.tr('viewerStartTour'),
        ),
      ),
      PopupMenuButton<ViewerHeatmapMetric>(
        enabled: canUseControls,
        onSelected: onSelectMetric,
        itemBuilder: (context) => ViewerHeatmapMetric.values
            .map(
              (metric) => PopupMenuItem<ViewerHeatmapMetric>(
                value: metric,
                child: Row(
                  children: <Widget>[
                    if (heatmapMetric == metric) ...<Widget>[
                      const Icon(Icons.check, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Text(context.tr(metric.labelKey)),
                  ],
                ),
              ),
            )
            .toList(growable: false),
        child: _MetricMenuTrigger(label: context.tr('heatmapMetricLabel')),
      ),
      FilledButton.tonalIcon(
        onPressed: canUseControls ? onToggleHeatmap : null,
        icon: Icon(
          heatmapVisible ? Icons.layers_clear_outlined : Icons.layers_outlined,
        ),
        label: Text(
          heatmapVisible
              ? context.tr('viewerHideHeatmap')
              : context.tr('viewerShowHeatmap'),
        ),
      ),
      FilledButton.tonalIcon(
        onPressed: canUseControls && canFocusCriticalZone
            ? onFocusCriticalZone
            : null,
        icon: const Icon(Icons.center_focus_strong_outlined),
        label: Text(context.tr('viewerFocusCriticalZoneAction')),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < AppBreakpoints.tablet;
            final actions = compact
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: controls
                          .map(
                            (widget) => Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.sm,
                              ),
                              child: widget,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  )
                : Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: controls,
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ViewerUiState {
  const _ViewerUiState({
    required this.warehouse,
    required this.canUseControls,
    required this.viewerType,
    required this.isWarehousesSyncing,
    required this.zonesVisible,
    required this.tourRunning,
    required this.heatmapVisible,
    required this.heatmapMetric,
    required this.heatmapZoneTypeFilterKey,
    required this.heatmapSeverityFilterKey,
    required this.heatmapLiveModeEnabled,
    required this.heatmapAutoFocusEnabled,
    required this.focusZoneName,
    required this.focusRequestId,
    required this.focusRackNumber,
    required this.focusLevelNumber,
    required this.focusSlotNumber,
    required this.focusLocationRequestId,
    required this.storageLocations,
    required this.selectedStorageLocation,
    required this.storagePrefs,
    required this.resetCount,
    required this.lastWarehouseSyncAt,
    required this.warehouseApiError,
    required this.isWarehouseOfflineMode,
    required this.isGeneratingModel,
    required this.warehouseHeatmapLayer,
    required this.externalModelPath,
  });

  final Warehouse? warehouse;
  final bool canUseControls;
  final ViewerType viewerType;
  final bool isWarehousesSyncing;
  final bool zonesVisible;
  final bool tourRunning;
  final bool heatmapVisible;
  final ViewerHeatmapMetric heatmapMetric;
  final String heatmapZoneTypeFilterKey;
  final String heatmapSeverityFilterKey;
  final bool heatmapLiveModeEnabled;
  final bool heatmapAutoFocusEnabled;
  final String? focusZoneName;
  final int focusRequestId;
  final int focusRackNumber;
  final int focusLevelNumber;
  final int focusSlotNumber;
  final int focusLocationRequestId;
  final List<WarehouseStorageLocation> storageLocations;
  final WarehouseStorageLocation? selectedStorageLocation;
  final _StorageLocationPrefs storagePrefs;
  final int resetCount;
  final DateTime? lastWarehouseSyncAt;
  final String? warehouseApiError;
  final bool isWarehouseOfflineMode;
  final bool isGeneratingModel;
  final List<WarehouseHeatmapLayerEntry> warehouseHeatmapLayer;
  final String? externalModelPath;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _ViewerUiState &&
        other.warehouse == warehouse &&
        other.canUseControls == canUseControls &&
        other.viewerType == viewerType &&
        other.isWarehousesSyncing == isWarehousesSyncing &&
        other.zonesVisible == zonesVisible &&
        other.tourRunning == tourRunning &&
        other.heatmapVisible == heatmapVisible &&
        other.heatmapMetric == heatmapMetric &&
        other.heatmapZoneTypeFilterKey == heatmapZoneTypeFilterKey &&
        other.heatmapSeverityFilterKey == heatmapSeverityFilterKey &&
        other.heatmapLiveModeEnabled == heatmapLiveModeEnabled &&
        other.heatmapAutoFocusEnabled == heatmapAutoFocusEnabled &&
        other.focusZoneName == focusZoneName &&
        other.focusRequestId == focusRequestId &&
        other.focusRackNumber == focusRackNumber &&
        other.focusLevelNumber == focusLevelNumber &&
        other.focusSlotNumber == focusSlotNumber &&
        other.focusLocationRequestId == focusLocationRequestId &&
        other.storageLocations == storageLocations &&
        other.selectedStorageLocation == selectedStorageLocation &&
        other.storagePrefs == storagePrefs &&
        other.resetCount == resetCount &&
        other.lastWarehouseSyncAt == lastWarehouseSyncAt &&
        other.warehouseApiError == warehouseApiError &&
        other.isWarehouseOfflineMode == isWarehouseOfflineMode &&
        other.isGeneratingModel == isGeneratingModel &&
        other.warehouseHeatmapLayer == warehouseHeatmapLayer &&
        other.externalModelPath == externalModelPath;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    warehouse,
    canUseControls,
    viewerType,
    isWarehousesSyncing,
    zonesVisible,
    tourRunning,
    heatmapVisible,
    heatmapMetric,
    heatmapZoneTypeFilterKey,
    heatmapSeverityFilterKey,
    heatmapLiveModeEnabled,
    heatmapAutoFocusEnabled,
    focusZoneName,
    focusRequestId,
    focusRackNumber,
    focusLevelNumber,
    focusSlotNumber,
    focusLocationRequestId,
    storageLocations,
    selectedStorageLocation,
    storagePrefs,
    resetCount,
    lastWarehouseSyncAt,
    warehouseApiError,
    isWarehouseOfflineMode,
    isGeneratingModel,
    warehouseHeatmapLayer,
    externalModelPath,
  ]);
}

class _ViewerHeaderBar extends StatelessWidget {
  const _ViewerHeaderBar({
    required this.warehouseName,
    required this.adapterStatusLabel,
    required this.hasBackendIssue,
    required this.isOfflineMode,
    required this.isSyncing,
    required this.lastSyncAt,
    required this.onOpenWarehouses,
    required this.onOpenDashboard,
    required this.onRefresh,
  });

  final String warehouseName;
  final String adapterStatusLabel;
  final bool hasBackendIssue;
  final bool isOfflineMode;
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final VoidCallback onOpenWarehouses;
  final VoidCallback onOpenDashboard;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final navButtons = Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: onOpenWarehouses,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(context.tr('toWarehouseList')),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenDashboard,
                      icon: const Icon(Icons.dashboard_outlined, size: 18),
                      label: Text(context.tr('dashboard')),
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        warehouseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      navButtons,
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        warehouseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    navButtons,
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                Chip(
                  avatar: const Icon(Icons.view_in_ar_outlined, size: 18),
                  label: Text(adapterStatusLabel),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                _ViewerBackendStatusChip(
                  isOfflineMode: isOfflineMode,
                  hasError: hasBackendIssue,
                ),
                _ViewerRefreshChip(isSyncing: isSyncing, onPressed: onRefresh),
                _ViewerLastSyncChip(lastSyncAt: lastSyncAt),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerBackendStatusCard extends StatelessWidget {
  const _ViewerBackendStatusCard({
    required this.apiError,
    required this.isOfflineMode,
    required this.showRetryAction,
    required this.onRetry,
  });

  final String? apiError;
  final bool isOfflineMode;
  final bool showRetryAction;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasError = apiError != null && apiError!.trim().isNotEmpty;
    final background = hasError
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final foreground = hasError
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  hasError
                      ? Icons.warning_amber_rounded
                      : Icons.cloud_off_outlined,
                  color: foreground,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    hasError
                        ? context.tr('warehousesSyncError', <String, Object>{
                            'error': apiError!,
                          })
                        : context.tr('viewerBackendOfflineInfo'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
            if (isOfflineMode && hasError) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr('viewerBackendOfflineInfo'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ],
            if (hasError && showRetryAction) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.tr('retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewerBackendStatusChip extends StatelessWidget {
  const _ViewerBackendStatusChip({
    required this.isOfflineMode,
    required this.hasError,
  });

  final bool isOfflineMode;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelKey = isOfflineMode
        ? 'backendOffline'
        : (hasError ? 'backendIssue' : 'backendOnline');
    final icon = isOfflineMode
        ? Icons.cloud_off_outlined
        : (hasError ? Icons.warning_amber_rounded : Icons.cloud_done_outlined);
    final background = isOfflineMode
        ? colorScheme.errorContainer
        : (hasError
              ? colorScheme.tertiaryContainer
              : colorScheme.primaryContainer);
    final foreground = isOfflineMode
        ? colorScheme.onErrorContainer
        : (hasError
              ? colorScheme.onTertiaryContainer
              : colorScheme.onPrimaryContainer);

    return StatusPill(
      icon: icon,
      label: context.tr(labelKey),
      backgroundColor: background,
      foregroundColor: foreground,
      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
  }
}

class _ViewerRefreshChip extends StatelessWidget {
  const _ViewerRefreshChip({required this.isSyncing, required this.onPressed});

  final bool isSyncing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onPressed,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
      avatar: isSyncing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(context.tr('refreshNow')),
    );
  }
}

class _ViewerLastSyncChip extends StatelessWidget {
  const _ViewerLastSyncChip({required this.lastSyncAt});

  final DateTime? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = lastSyncAt == null
        ? context.tr('lastSyncUnknown')
        : context.tr('lastSyncShort', <String, Object>{
            'time': _formatRelativeTime(context, lastSyncAt!),
          });
    return StatusPill(
      icon: Icons.schedule_rounded,
      label: label,
      backgroundColor: colorScheme.surfaceContainerHighest,
      foregroundColor: colorScheme.onSurfaceVariant,
      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
  }

  String _formatRelativeTime(BuildContext context, DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) {
      return context.tr('justNow');
    }
    if (diff.inMinutes < 60) {
      return context.tr('minutesAgo', <String, Object>{
        'count': diff.inMinutes,
      });
    }
    if (diff.inHours < 24) {
      return context.tr('hoursAgo', <String, Object>{'count': diff.inHours});
    }
    return context.tr('daysAgo', <String, Object>{'count': diff.inDays});
  }
}

class _ViewerCanvas extends StatelessWidget {
  const _ViewerCanvas({
    required this.adapter,
    required this.warehouse,
    required this.isGeneratingModel,
    required this.zonesVisible,
    required this.tourRunning,
    required this.heatmapVisible,
    required this.heatmapMetric,
    required this.heatmapData,
    required this.warehouseHeatmapLayer,
    required this.generatedModel,
    required this.focusZoneName,
    required this.focusRequestId,
    required this.focusRackNumber,
    required this.focusLevelNumber,
    required this.focusSlotNumber,
    required this.focusLocationRequestId,
    required this.onZoneTap,
    this.externalModelPath,
  });

  final ViewerAdapter adapter;
  final Warehouse warehouse;
  final bool isGeneratingModel;
  final bool zonesVisible;
  final bool tourRunning;
  final bool heatmapVisible;
  final ViewerHeatmapMetric heatmapMetric;
  final List<ViewerHeatmapEntry> heatmapData;
  final List<WarehouseHeatmapLayerEntry> warehouseHeatmapLayer;
  final WarehouseModelData? generatedModel;
  final String? focusZoneName;
  final int focusRequestId;
  final int focusRackNumber;
  final int focusLevelNumber;
  final int focusSlotNumber;
  final int focusLocationRequestId;
  final void Function(ViewerHeatmapEntry, ViewerHeatmapMetric) onZoneTap;
  final String? externalModelPath;

  @override
  Widget build(BuildContext context) {
    final useGlbViewer = Glb3DViewer.canRender(externalModelPath);
    final useUnitySource = isUnitySceneSourcePath(externalModelPath);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: useGlbViewer
                ? Glb3DViewer(
                    modelPath: externalModelPath!,
                    heatmapData: heatmapData,
                    warehouseHeatmapLayer: warehouseHeatmapLayer,
                    heatmapMetric: heatmapMetric,
                    showHotspots:
                        heatmapVisible || warehouseHeatmapLayer.isNotEmpty,
                    hideGenericHallHotspots: true,
                  )
                : useUnitySource
                ? UnityRuntimeView(scenePath: externalModelPath!)
                : adapter.type == ViewerType.nativePlaceholder
                ? NativeWarehouse3DView(
                    warehouse: warehouse,
                    model: generatedModel,
                    tourRunning: tourRunning,
                    zonesVisible: zonesVisible,
                    heatmapVisible: heatmapVisible,
                    heatmapMetric: heatmapMetric,
                    heatmapData: heatmapData,
                    warehouseHeatmapLayer: warehouseHeatmapLayer,
                    focusZoneName: focusZoneName,
                    focusRequestId: focusRequestId,
                    focusRackNumber: focusRackNumber,
                    focusLevelNumber: focusLevelNumber,
                    focusSlotNumber: focusSlotNumber,
                    focusLocationRequestId: focusLocationRequestId,
                    enableFirstPersonControls: false,
                  )
                : generatedModel == null
                ? adapter.buildViewerCanvas(context, warehouse)
                : _GeneratedWarehouseCanvas(
                    warehouse: warehouse,
                    model: generatedModel!,
                  ),
          ),
        ),
        if (useUnitySource)
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: UnitySourceNotice(scenePath: externalModelPath!),
            ),
          ),
        if (heatmapVisible && heatmapData.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: HeatmapZoneOverlay(
                metric: heatmapMetric,
                data: heatmapData,
                onZoneTap: onZoneTap,
                hideGenericHallZones: true,
              ),
            ),
          ),
        if (isGeneratingModel)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.9),
              ),
              child: const Center(child: _ViewerGeneratingOverlay()),
            ),
          ),
      ],
    );
  }
}

class _ViewerGeneratingOverlay extends StatelessWidget {
  const _ViewerGeneratingOverlay();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.tr('viewerGenerateAction'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('viewerGenerationSubtitleMissing'),
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
}

class _ExternalModelCard extends StatelessWidget {
  const _ExternalModelCard({required this.modelPath});

  final String modelPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fileName = _fileNameFromPath(modelPath);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.view_in_ar_rounded, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Externes 3D-Modell eingebunden',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              fileName,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              modelPath,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.file(modelPath);
                    final opened = await launchUrl(uri);
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Modell-Datei konnte nicht geoeffnet werden.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Modell oeffnen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelGenerationCard extends StatelessWidget {
  const _ModelGenerationCard({
    required this.warehouse,
    required this.isGenerating,
    required this.onGenerate,
  });

  final Warehouse warehouse;
  final bool isGenerating;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    final hasModel = warehouse.generatedModel != null;

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
                    context.tr('viewerGenerationTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    hasModel
                        ? context.tr('viewerModelStateAvailable')
                        : context.tr('viewerModelStateMissing'),
                  ),
                  avatar: Icon(
                    hasModel
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined,
                    size: 18,
                  ),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hasModel
                  ? context.tr('viewerGenerationSubtitleReady')
                  : context.tr('viewerGenerationSubtitleMissing'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: isGenerating ? null : onGenerate,
              icon: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(context.tr('viewerGenerateAction')),
            ),
            if (hasModel) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr('viewerModelGeneratedAt', <String, Object>{
                  'time': _formatRelativeTime(
                    context,
                    warehouse.generatedModel!.generatedAt,
                  ),
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRelativeTime(BuildContext context, DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) {
      return context.tr('justNow');
    }
    if (diff.inMinutes < 60) {
      return context.tr('minutesAgo', <String, Object>{
        'count': diff.inMinutes,
      });
    }
    if (diff.inHours < 24) {
      return context.tr('hoursAgo', <String, Object>{'count': diff.inHours});
    }
    return context.tr('daysAgo', <String, Object>{'count': diff.inDays});
  }
}

class _GeneratedWarehouseCanvas extends StatelessWidget {
  const _GeneratedWarehouseCanvas({
    required this.warehouse,
    required this.model,
  });

  final Warehouse warehouse;
  final WarehouseModelData model;

  @override
  Widget build(BuildContext context) {
    final rows = model.shelfRows.clamp(1, 200).toInt();
    final columns = model.shelfColumns.clamp(1, 200).toInt();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('viewerGeneratedCanvasTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _PlanChip(
                  label: context.tr('warehouseLengthLabel'),
                  value: '${model.warehouseLengthM} m',
                ),
                _PlanChip(
                  label: context.tr('warehouseWidthLabel'),
                  value: '${model.warehouseWidthM} m',
                ),
                _PlanChip(
                  label: context.tr('warehouseHeightLabel'),
                  value: '${model.warehouseHeightM} m',
                ),
                _PlanChip(label: context.tr('rackRowsLabel'), value: '$rows'),
                _PlanChip(
                  label: context.tr('rackLevelsLabel'),
                  value: '${model.shelfLevels}',
                ),
                _PlanChip(
                  label: context.tr('viewerModelShelves'),
                  value: '$rows x $columns',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: _WarehousePlanPainter(
                    rows: rows,
                    columns: columns,
                    zones: model.zones,
                    colorScheme: Theme.of(context).colorScheme,
                  ),
                  child: Container(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('viewerGeneratedCanvasSubtitle', <String, Object>{
                'name': warehouse.name,
              }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.4),
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
            Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehousePlanPainter extends CustomPainter {
  const _WarehousePlanPainter({
    required this.rows,
    required this.columns,
    required this.zones,
    required this.colorScheme,
  });

  final int rows;
  final int columns;
  final List<WarehouseModelZone> zones;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = colorScheme.surface;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final borderPaint = Paint()
      ..color = colorScheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(
      Rect.fromLTWH(0.6, 0.6, size.width - 1.2, size.height - 1.2),
      borderPaint,
    );

    final shelfPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final shelfStroke = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final safeRows = rows.clamp(1, 60);
    final safeColumns = columns.clamp(1, 80);
    final cellWidth = size.width / safeColumns;
    final cellHeight = size.height / safeRows;

    for (var row = 0; row < safeRows; row++) {
      for (var column = 0; column < safeColumns; column++) {
        if ((row + column).isOdd) {
          continue;
        }
        final rect = Rect.fromLTWH(
          column * cellWidth + 1.4,
          row * cellHeight + 1.4,
          (cellWidth - 2.8).clamp(2, cellWidth),
          (cellHeight - 2.8).clamp(2, cellHeight),
        );
        canvas.drawRect(rect, shelfPaint);
        canvas.drawRect(rect, shelfStroke);
      }
    }

    final zoneFillColors = <Color>[
      Colors.orange.withValues(alpha: 0.26),
      Colors.blue.withValues(alpha: 0.22),
      Colors.green.withValues(alpha: 0.22),
      Colors.red.withValues(alpha: 0.2),
    ];

    for (var i = 0; i < zones.length; i++) {
      final zone = zones[i];
      final left = (zone.x.clamp(0, 1) * size.width).toDouble();
      final top = (zone.y.clamp(0, 1) * size.height).toDouble();
      final width = (zone.width.clamp(0.05, 1) * size.width).toDouble();
      final height = (zone.height.clamp(0.05, 1) * size.height).toDouble();

      final rect = Rect.fromLTWH(
        left,
        top,
        width,
        height,
      ).intersect(Rect.fromLTWH(0, 0, size.width, size.height));
      final fillPaint = Paint()
        ..color = zoneFillColors[i % zoneFillColors.length];
      final strokePaint = Paint()
        ..color = colorScheme.secondary.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WarehousePlanPainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.columns != columns ||
        oldDelegate.zones != zones ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _ZoneDetailsSheet extends StatelessWidget {
  const _ZoneDetailsSheet({
    required this.zone,
    required this.metric,
    required this.metricValue,
  });

  final WarehouseZone zone;
  final ViewerHeatmapMetric metric;
  final double metricValue;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${context.tr('zones')}: ${zone.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr('heatmapLegendTitle', <String, Object>{
                  'metric': context.tr(metric.labelKey),
                }),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 12,
                  value: metricValue.clamp(0, 1).toDouble(),
                  color: _metricColor(metricValue),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  _ZoneMetricChip(
                    label: context.tr('kpiUtilization'),
                    value: '${zone.utilizationPercent}%',
                  ),
                  _ZoneMetricChip(
                    label: context.tr('kpiOccupiedSlots'),
                    value: '${zone.occupiedStorageSlots}',
                  ),
                  _ZoneMetricChip(
                    label: context.tr('kpiFreeSlots'),
                    value: '${zone.freeStorageSlots}',
                  ),
                  _ZoneMetricChip(
                    label: context.tr('kpiTotalSlots'),
                    value: '${zone.totalStorageSlots}',
                  ),
                  _ZoneMetricChip(
                    label: context.tr('kpiArticles'),
                    value: '${zone.articleCount}',
                  ),
                  _ZoneMetricChip(
                    label: context.tr('kpiInboundPerDay'),
                    value: '${zone.inboundPerDay}',
                  ),
                  _ZoneMetricChip(
                    label: context.tr('kpiThroughputPerDay'),
                    value: '${zone.throughputPerDay}',
                  ),
                  _ZoneMetricChip(
                    label: context.tr('kpiPickRatePerHour'),
                    value: '${zone.pickRatePerHour}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.tr('warehouseAbcTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              AbcAnalysisBar(
                aCount: zone.abcAnalysis.aCount,
                bCount: zone.abcAnalysis.bCount,
                cCount: zone.abcAnalysis.cCount,
                height: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _metricColor(double value) {
    return heatColorForValue(value);
  }
}

class _ZoneMetricChip extends StatelessWidget {
  const _ZoneMetricChip({required this.label, required this.value});

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
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricMenuTrigger extends StatelessWidget {
  const _MetricMenuTrigger({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.tune, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _WarehouseMeta extends StatelessWidget {
  const _WarehouseMeta({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context) {
    final layout = warehouse.layoutSpec;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: <Widget>[
            _MetaItem(
              label: context.tr('name'),
              value: warehouse.name,
              icon: Icons.warehouse_outlined,
            ),
            _MetaItem(
              label: context.tr('location'),
              value: warehouse.location,
              icon: Icons.location_on_outlined,
            ),
            _MetaItem(
              label: context.tr('status'),
              value: context.tr(warehouse.status.labelKey),
              icon: Icons.info_outline,
            ),
            _MetaItem(
              label: context.tr('zones'),
              value: '${warehouse.zoneCount}',
              icon: Icons.grid_4x4_outlined,
            ),
            if (layout != null)
              _MetaItem(
                label: context.tr('warehouseLengthLabel'),
                value: '${layout.lengthM} m',
                icon: Icons.straighten_outlined,
              ),
            if (layout != null)
              _MetaItem(
                label: context.tr('warehouseWidthLabel'),
                value: '${layout.widthM} m',
                icon: Icons.straighten_outlined,
              ),
            if (layout != null)
              _MetaItem(
                label: context.tr('warehouseHeightLabel'),
                value: '${layout.heightM} m',
                icon: Icons.height_outlined,
              ),
          ],
        ),
      ),
    );
  }
}

class _StorageLocationCard extends StatefulWidget {
  const _StorageLocationCard({
    required this.warehouse,
    required this.initialRack,
    required this.initialLevel,
    required this.initialSlot,
    required this.canUseControls,
    required this.samples,
    required this.prefs,
    this.onFocus,
  });

  final Warehouse warehouse;
  final int initialRack;
  final int initialLevel;
  final int initialSlot;
  final bool canUseControls;
  final List<WarehouseStorageLocation> samples;
  final _StorageLocationPrefs prefs;
  final void Function(int rack, int level, int slot)? onFocus;

  @override
  State<_StorageLocationCard> createState() => _StorageLocationCardState();
}

class _StorageLocationCardState extends State<_StorageLocationCard> {
  late int _rackCount;
  late int _levelCount;
  late int _slotMax;
  late int _slotDigits;
  int? _selectedRack;
  int? _selectedLevel;
  int? _selectedSlot;
  late TextEditingController _slotController;
  late TextEditingController _codeController;
  late TextEditingController _filterController;
  bool _slotValid = true;
  bool _codeValid = true;
  String _filterQuery = '';
  bool _sortByAbc = true;
  int _visibleSampleCount = 12;

  @override
  void initState() {
    super.initState();
    _selectedRack = widget.initialRack;
    _selectedLevel = widget.initialLevel;
    _selectedSlot = widget.initialSlot;
    _initFromWarehouse(widget.warehouse);
    _slotController = TextEditingController(
      text: (_selectedSlot ?? 1).toString().padLeft(_slotDigits, '0'),
    );
    _codeController = TextEditingController(text: _locationCode());
    _filterController = TextEditingController();
    _sortByAbc = widget.prefs.sortByAbc;
    _visibleSampleCount = widget.prefs.visibleSampleCount;
    _filterQuery = widget.prefs.filterQuery;
    _filterController.text = _filterQuery;
  }

  @override
  void didUpdateWidget(covariant _StorageLocationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.warehouse.id != widget.warehouse.id ||
        oldWidget.initialRack != widget.initialRack ||
        oldWidget.initialLevel != widget.initialLevel ||
        oldWidget.initialSlot != widget.initialSlot) {
      _sortByAbc = widget.prefs.sortByAbc;
      _visibleSampleCount = widget.prefs.visibleSampleCount;
      _filterQuery = widget.prefs.filterQuery;
      _filterController.text = _filterQuery;
      _selectedRack = widget.initialRack;
      _selectedLevel = widget.initialLevel;
      _selectedSlot = widget.initialSlot;
      _initFromWarehouse(widget.warehouse);
      _slotController.text = (_selectedSlot ?? 1).toString().padLeft(
        _slotDigits,
        '0',
      );
      _codeController.text = _locationCode();
    }
  }

  @override
  void dispose() {
    _slotController.dispose();
    _codeController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _initFromWarehouse(Warehouse warehouse) {
    _rackCount = _resolveRackCount(warehouse);
    _levelCount = _resolveLevelCount(warehouse);
    _slotMax = _resolveSlotMax(warehouse, _rackCount, _levelCount);
    _slotDigits = math.max(3, _slotMax.toString().length);
    _selectedRack ??= 1;
    _selectedLevel ??= 1;
    _selectedSlot ??= 1;
    _selectedRack = _clampSelection(_selectedRack, _rackCount);
    _selectedLevel = _clampSelection(_selectedLevel, _levelCount);
    _selectedSlot = _clampSelection(_selectedSlot, _slotMax);
    _slotValid = true;
    _codeValid = true;
  }

  int _resolveRackCount(Warehouse warehouse) {
    final model = warehouse.generatedModel;
    if (model != null && model.shelfRows > 0) {
      return model.shelfRows;
    }
    final layout = warehouse.layoutSpec;
    if (layout != null && layout.rackRowCount > 0) {
      return layout.rackRowCount;
    }
    return 1;
  }

  int _resolveLevelCount(Warehouse warehouse) {
    final model = warehouse.generatedModel;
    if (model != null && model.shelfLevels > 0) {
      return model.shelfLevels;
    }
    final layout = warehouse.layoutSpec;
    if (layout != null && layout.rackLevels > 0) {
      return layout.rackLevels;
    }
    return 1;
  }

  int _resolveSlotMax(Warehouse warehouse, int rackCount, int levelCount) {
    final model = warehouse.generatedModel;
    if (model != null && model.shelfColumns > 0) {
      return model.shelfColumns;
    }
    final total = warehouse.totalStorageSlots;
    final divisor = rackCount * levelCount;
    if (total > 0 && divisor > 0) {
      return math.max(1, (total / divisor).round());
    }
    return 12;
  }

  int _clampSelection(int? value, int max) {
    final safe = value ?? 1;
    return safe.clamp(1, math.max(1, max));
  }

  void _updateSlotFromText(String value) {
    if (value.trim().isEmpty) {
      setState(() => _slotValid = false);
      return;
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > _slotMax) {
      setState(() => _slotValid = false);
      return;
    }
    setState(() {
      _selectedSlot = parsed;
      _slotValid = true;
      _codeValid = true;
    });
    _codeController.text = _locationCode();
  }

  void _applyLocationCode(String raw) {
    final match = RegExp(
      r'R\s*(\d+)\s*[-/ ]?\s*E\s*(\d+)\s*[-/ ]?\s*F\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      setState(() => _codeValid = false);
      return;
    }
    final rack = int.tryParse(match.group(1) ?? '') ?? 1;
    final level = int.tryParse(match.group(2) ?? '') ?? 1;
    final slot = int.tryParse(match.group(3) ?? '') ?? 1;
    setState(() {
      _selectedRack = _clampSelection(rack, _rackCount);
      _selectedLevel = _clampSelection(level, _levelCount);
      _selectedSlot = _clampSelection(slot, _slotMax);
      _slotValid = true;
      _codeValid = true;
    });
    _slotController.text = (_selectedSlot ?? 1).toString().padLeft(
      _slotDigits,
      '0',
    );
    _codeController.text = _locationCode();
  }

  void _applySample(WarehouseStorageLocation sample) {
    setState(() {
      _selectedRack = _clampSelection(sample.rackNumber, _rackCount);
      _selectedLevel = _clampSelection(sample.levelNumber, _levelCount);
      _selectedSlot = _clampSelection(sample.slotNumber, _slotMax);
      _slotValid = true;
      _codeValid = true;
    });
    _slotController.text = (_selectedSlot ?? 1).toString().padLeft(
      _slotDigits,
      '0',
    );
    _codeController.text = _locationCode();
    if (widget.onFocus != null) {
      widget.onFocus!.call(
        _selectedRack ?? 1,
        _selectedLevel ?? 1,
        _selectedSlot ?? 1,
      );
    }
  }

  List<WarehouseStorageLocation> _filteredSamples() {
    final query = _filterQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.samples
        : widget.samples
              .where((sample) {
                final code = sample.displayCode.toLowerCase();
                final rack = sample.rackNumber.toString();
                final level = sample.levelNumber.toString();
                final slot = sample.slotNumber.toString();
                return code.contains(query) ||
                    rack == query ||
                    level == query ||
                    slot == query ||
                    sample.placeId.toLowerCase().contains(query) ||
                    sample.area.toLowerCase().contains(query) ||
                    sample.abcClass.toLowerCase().contains(query);
              })
              .toList(growable: false);
    final sorted = filtered.toList(growable: false);
    sorted.sort((a, b) {
      if (_sortByAbc) {
        final rankA = _abcRank(a.abcClass);
        final rankB = _abcRank(b.abcClass);
        if (rankA != rankB) {
          return rankA.compareTo(rankB);
        }
      }
      if (a.rackNumber != b.rackNumber) {
        return a.rackNumber.compareTo(b.rackNumber);
      }
      if (a.levelNumber != b.levelNumber) {
        return a.levelNumber.compareTo(b.levelNumber);
      }
      if (a.slotNumber != b.slotNumber) {
        return a.slotNumber.compareTo(b.slotNumber);
      }
      if (!_sortByAbc) {
        return _abcRank(a.abcClass).compareTo(_abcRank(b.abcClass));
      }
      return 0;
    });
    return sorted;
  }

  List<WarehouseStorageLocation> _visibleSamples() {
    final filtered = _filteredSamples();
    final limit = _visibleSampleCount.clamp(1, filtered.length);
    return filtered.take(limit).toList(growable: false);
  }

  List<WarehouseStorageLocation> _suggestedSamples() {
    if (_filterQuery.trim().isEmpty) {
      return const <WarehouseStorageLocation>[];
    }
    final query = _filterQuery.trim().toLowerCase();
    final candidates = _filteredSamples().toList(growable: false);
    candidates.sort((a, b) {
      final scoreA = _suggestionScore(a, query);
      final scoreB = _suggestionScore(b, query);
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }
      if (a.rackNumber != b.rackNumber) {
        return a.rackNumber.compareTo(b.rackNumber);
      }
      if (a.levelNumber != b.levelNumber) {
        return a.levelNumber.compareTo(b.levelNumber);
      }
      return a.slotNumber.compareTo(b.slotNumber);
    });
    return candidates.take(6).toList(growable: false);
  }

  int _suggestionScore(WarehouseStorageLocation sample, String query) {
    final code = sample.displayCode.toLowerCase();
    if (code == query) {
      return 100;
    }
    if (code.startsWith(query)) {
      return 80;
    }
    if (code.contains(query)) {
      return 60;
    }
    if (sample.placeId.toLowerCase().contains(query)) {
      return 40;
    }
    if (sample.area.toLowerCase().contains(query)) {
      return 30;
    }
    if (sample.abcClass.toLowerCase() == query) {
      return 20;
    }
    return 10;
  }

  int _abcRank(String abc) {
    switch (abc.trim().toUpperCase()) {
      case 'A':
        return 0;
      case 'B':
        return 1;
      case 'C':
        return 2;
      default:
        return 3;
    }
  }

  (Color, Color) _abcChipColor(String abc, ColorScheme colorScheme) {
    switch (abc) {
      case 'A':
        return (colorScheme.errorContainer, colorScheme.onErrorContainer);
      case 'B':
        return (colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer);
      case 'C':
        return (
          colorScheme.secondaryContainer,
          colorScheme.onSecondaryContainer,
        );
      default:
        return (
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
        );
    }
  }

  String _locationCode() {
    final rack = (_selectedRack ?? 1).toString().padLeft(2, '0');
    final level = (_selectedLevel ?? 1).toString().padLeft(2, '0');
    final slot = (_selectedSlot ?? 1).toString().padLeft(_slotDigits, '0');
    return 'R$rack-E$level-F$slot';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final formTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= 900;
            final isMedium = width >= 640;
            final fieldWidth = isWide ? 220.0 : (isMedium ? 200.0 : width);
            final codeWidth = isWide ? 360.0 : (isMedium ? 320.0 : width);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.location_searching, color: colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            context.tr('storageLocationTitle'),
                            style: formTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('storageLocationSubtitle'),
                            style: formTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.9,
                        ),
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
                            Icon(
                              Icons.qr_code_2,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _locationCode(),
                              style: formTheme.labelLarge?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: codeWidth,
                  child: TextFormField(
                    controller: _codeController,
                    enabled: widget.canUseControls,
                    decoration: InputDecoration(
                      labelText: context.tr('storageLocationCodeLabel'),
                      hintText: context.tr('storageLocationCodeHint'),
                      errorText: _codeValid
                          ? null
                          : context.tr('storageLocationCodeInvalid'),
                      suffixIcon: IconButton(
                        tooltip: context.tr('storageLocationCodeApply'),
                        onPressed: widget.canUseControls
                            ? () => _applyLocationCode(_codeController.text)
                            : null,
                        icon: const Icon(Icons.check_circle_outline),
                      ),
                    ),
                    onFieldSubmitted: (value) {
                      if (!widget.canUseControls) {
                        return;
                      }
                      _applyLocationCode(value);
                    },
                    onChanged: (_) {
                      if (_codeValid) {
                        return;
                      }
                      setState(() => _codeValid = true);
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: <Widget>[
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedRack ?? 1,
                        decoration: InputDecoration(
                          labelText: context.tr('storageLocationRackLabel'),
                        ),
                        items: List<DropdownMenuItem<int>>.generate(_rackCount, (
                          index,
                        ) {
                          final value = index + 1;
                          return DropdownMenuItem<int>(
                            value: value,
                            child: Text(
                              '${context.tr('storageLocationRackLabel')} $value',
                            ),
                          );
                        }),
                        onChanged: widget.canUseControls
                            ? (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _selectedRack = value;
                                  _codeValid = true;
                                });
                                _codeController.text = _locationCode();
                              }
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedLevel ?? 1,
                        decoration: InputDecoration(
                          labelText: context.tr('storageLocationLevelLabel'),
                        ),
                        items: List<DropdownMenuItem<int>>.generate(_levelCount, (
                          index,
                        ) {
                          final value = index + 1;
                          return DropdownMenuItem<int>(
                            value: value,
                            child: Text(
                              '${context.tr('storageLocationLevelLabel')} $value',
                            ),
                          );
                        }),
                        onChanged: widget.canUseControls
                            ? (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _selectedLevel = value;
                                  _codeValid = true;
                                });
                                _codeController.text = _locationCode();
                              }
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _slotController,
                        enabled: widget.canUseControls,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: context.tr('storageLocationSlotLabel'),
                          helperText: context.tr(
                            'storageLocationSlotHelper',
                            <String, Object>{'max': _slotMax},
                          ),
                          errorText: _slotValid
                              ? null
                              : context.tr('storageLocationSlotInvalid'),
                        ),
                        onChanged: _updateSlotFromText,
                        onEditingComplete: () {
                          _slotController.text = (_selectedSlot ?? 1)
                              .toString()
                              .padLeft(_slotDigits, '0');
                          _codeController.text = _locationCode();
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.tr('storageLocationSamplesTitle'),
                        style: formTheme.titleSmall,
                      ),
                    ),
                    _CountPill(
                      label: context
                          .tr('storageLocationSamplesCount', <String, Object>{
                            'count': _filteredSamples().length,
                            'total': widget.samples.length,
                          }),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _filterController,
                  enabled: widget.canUseControls,
                  decoration: InputDecoration(
                    labelText: context.tr('storageLocationFilterLabel'),
                    hintText: context.tr('storageLocationFilterHint'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _filterQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: context.tr('storageLocationFilterClear'),
                            onPressed: () {
                              setState(() {
                                _filterQuery = '';
                                _filterController.clear();
                              });
                              context.read<AppState>().setStorageFilterQuery(
                                '',
                              );
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() => _filterQuery = value);
                    context.read<AppState>().setStorageFilterQuery(value);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_suggestedSamples().isNotEmpty) ...<Widget>[
                  Text(
                    context.tr('storageLocationSuggestionsTitle'),
                    style: formTheme.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _suggestedSamples().map((sample) {
                      final abc = sample.abcClass.trim().toUpperCase();
                      final chipColor = _abcChipColor(abc, colorScheme);
                      return InputChip(
                        label: Text(sample.displayCode),
                        labelStyle: formTheme.labelMedium?.copyWith(
                          color: chipColor.$2,
                        ),
                        backgroundColor: chipColor.$1,
                        onPressed: widget.canUseControls
                            ? () {
                                _filterController.text = sample.displayCode;
                                setState(
                                  () => _filterQuery = sample.displayCode,
                                );
                                context.read<AppState>().setStorageFilterQuery(
                                  sample.displayCode,
                                );
                                _applySample(sample);
                              }
                            : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    ChoiceChip(
                      label: Text(context.tr('storageLocationSortAbc')),
                      selected: _sortByAbc,
                      onSelected: widget.canUseControls
                          ? (_) {
                              setState(() => _sortByAbc = true);
                              context.read<AppState>().setStorageSortByAbc(
                                true,
                              );
                            }
                          : null,
                    ),
                    ChoiceChip(
                      label: Text(context.tr('storageLocationSortRack')),
                      selected: !_sortByAbc,
                      onSelected: widget.canUseControls
                          ? (_) {
                              setState(() => _sortByAbc = false);
                              context.read<AppState>().setStorageSortByAbc(
                                false,
                              );
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (widget.samples.isEmpty)
                  Text(
                    context.tr('storageLocationSamplesEmpty'),
                    style: formTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _visibleSamples().map((sample) {
                      final abc = sample.abcClass.trim().toUpperCase();
                      final chipColor = _abcChipColor(abc, colorScheme);
                      final label = abc.isEmpty
                          ? sample.displayCode
                          : '${sample.displayCode} · $abc';
                      return InputChip(
                        label: Text(label),
                        labelStyle: formTheme.labelMedium?.copyWith(
                          color: chipColor.$2,
                        ),
                        backgroundColor: chipColor.$1,
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        onPressed: widget.canUseControls
                            ? () => _applySample(sample)
                            : null,
                      );
                    }).toList(),
                  ),
                if (widget.samples.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          context.tr(
                            'storageLocationVisibleCount',
                            <String, Object>{
                              'count': _visibleSamples().length,
                              'total': _filteredSamples().length,
                            },
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: formTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: OverflowBar(
                          alignment: MainAxisAlignment.end,
                          overflowAlignment: OverflowBarAlignment.end,
                          spacing: 0,
                          children: <Widget>[
                            TextButton(
                              onPressed:
                                  _visibleSampleCount >=
                                      _filteredSamples().length
                                  ? null
                                  : () {
                                      setState(() {
                                        _visibleSampleCount += 12;
                                      });
                                      context
                                          .read<AppState>()
                                          .setStorageVisibleSampleCount(
                                            _visibleSampleCount,
                                          );
                                    },
                              child: Text(context.tr('storageLocationShowMore')),
                            ),
                            TextButton(
                              onPressed: _visibleSampleCount <= 12
                                  ? null
                                  : () {
                                      setState(() {
                                        _visibleSampleCount = 12;
                                      });
                                      context
                                          .read<AppState>()
                                          .setStorageVisibleSampleCount(
                                            _visibleSampleCount,
                                          );
                                    },
                              child: Text(context.tr('storageLocationShowLess')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.tr('storageLocationSummary', <String, Object>{
                          'rack': _selectedRack ?? 1,
                          'level': _selectedLevel ?? 1,
                          'slot': (_selectedSlot ?? 1).toString().padLeft(
                            _slotDigits,
                            '0',
                          ),
                        }),
                        style: formTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: (_slotValid && widget.onFocus != null)
                          ? () {
                              final rack = _selectedRack ?? 1;
                              final level = _selectedLevel ?? 1;
                              final slot = _selectedSlot ?? 1;
                              widget.onFocus?.call(rack, level, slot);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.tr(
                                      'storageLocationFocusToast',
                                      <String, Object>{
                                        'rack': rack,
                                        'level': level,
                                        'slot': slot.toString().padLeft(
                                          _slotDigits,
                                          '0',
                                        ),
                                      },
                                    ),
                                  ),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.center_focus_strong),
                      label: Text(context.tr('storageLocationFocusAction')),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 18),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageLocationDetailsCard extends StatelessWidget {
  const _StorageLocationDetailsCard({
    required this.selected,
    required this.fallbackRack,
    required this.fallbackLevel,
    required this.fallbackSlot,
  });

  final WarehouseStorageLocation? selected;
  final int fallbackRack;
  final int fallbackLevel;
  final int fallbackSlot;

  List<_LocationActionRecommendation> _buildRecommendations(
    WarehouseStorageLocation sample,
  ) {
    final recommendations = <_LocationActionRecommendation>[];
    final abc = sample.abcClass.trim().toUpperCase();
    final idle = sample.daysSinceMovement ?? 0;
    final moves30 = sample.movements30d ?? 0;
    final status = sample.status.trim().toLowerCase();
    final isEmpty = status.contains('frei') || status.contains('leer');
    final isOccupied = status.contains('belegt') || status.contains('occupied');

    if (idle >= 180 && moves30 <= 1) {
      recommendations.add(
        _LocationActionRecommendation(
          icon: Icons.cleaning_services_outlined,
          title: 'Bestandsbereinigung anstoßen',
          summary:
              'Platz seit langer Zeit ohne Bewegung. Prüfen auf Löschung/Abzug.',
          dataBasis: 'Tage seit Bewegung, Bewegungen 30T, Status, Artikel-ID',
          critical: true,
        ),
      );
    }

    if (idle >= 90 && isOccupied) {
      recommendations.add(
        _LocationActionRecommendation(
          icon: Icons.swap_horiz_rounded,
          title: 'Relocate / Retrieval prüfen',
          summary:
              'Langläufer erkannt. In Reserve umlagern oder gezielt auslagern.',
          dataBasis:
              'Tage seit Bewegung, ABC-Klasse, Platzcode, Bewegungen 30T',
        ),
      );
    }

    if ((abc == 'A' && sample.levelNumber >= 3) ||
        (abc == 'B' && moves30 >= 20 && sample.levelNumber >= 2)) {
      recommendations.add(
        _LocationActionRecommendation(
          icon: Icons.vertical_align_bottom_outlined,
          title: 'Replenishment für Pick-Ebene',
          summary:
              'Schnelldreher liegt zu hoch. Für Kommissionierung nach unten ziehen.',
          dataBasis: 'ABC-Klasse, Ebene, Picks 30T, Pick-Strategie',
        ),
      );
    }

    if ((abc == 'A' && (idle >= 45 || moves30 <= 2)) ||
        (abc == 'C' && moves30 >= 25)) {
      recommendations.add(
        _LocationActionRecommendation(
          icon: Icons.auto_graph_outlined,
          title: 'ABC-Klassifizierung neu bewerten',
          summary: 'Umschlag passt nicht zur aktuellen ABC-Zuordnung.',
          dataBasis: 'ABC-Klasse, Picks 30T, Tage seit Bewegung, Artikel-ID',
        ),
      );
    }

    if (isEmpty) {
      recommendations.add(
        _LocationActionRecommendation(
          icon: Icons.inventory_2_outlined,
          title: 'Putaway-Kandidat',
          summary: 'Freier Platz kann für Einlagerung genutzt werden.',
          dataBasis: 'Status, Zone/Bereich, Putaway-Regeln, Artikelprofil',
        ),
      );
    }

    return recommendations;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasSelection = selected != null;
    final rack = hasSelection ? selected!.rackNumber : fallbackRack;
    final level = hasSelection ? selected!.levelNumber : fallbackLevel;
    final slot = hasSelection ? selected!.slotNumber : fallbackSlot;
    final code = WarehouseStorageLocation(
      placeId: selected?.placeId ?? '',
      area: selected?.area ?? '',
      rackNumber: rack,
      levelNumber: level,
      slotNumber: slot,
      abcClass: selected?.abcClass ?? '',
      status: selected?.status ?? '',
    ).displayCode;

    final recommendations = hasSelection
        ? _buildRecommendations(selected!)
        : const <_LocationActionRecommendation>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.visibility_outlined, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.tr('storageLocationDetailsTitle'),
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('storageLocationDetailsSubtitle'),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  code,
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (!hasSelection)
              Text(
                context.tr('storageLocationDetailsEmpty'),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  _DetailChip(
                    label: context.tr('storageLocationFieldPlace'),
                    value: selected!.placeId.isEmpty ? '-' : selected!.placeId,
                  ),
                  _DetailChip(
                    label: context.tr('storageLocationFieldArea'),
                    value: selected!.area.isEmpty ? '-' : selected!.area,
                  ),
                  _DetailChip(
                    label: context.tr('storageLocationFieldAbc'),
                    value: selected!.abcClass.isEmpty
                        ? '-'
                        : selected!.abcClass,
                  ),
                  _DetailChip(
                    label: context.tr('storageLocationFieldStatus'),
                    value: selected!.status.isEmpty ? '-' : selected!.status,
                  ),
                  _DetailChip(
                    label: 'Artikel',
                    value: selected!.articleId.isEmpty
                        ? '-'
                        : selected!.articleId,
                  ),
                  _DetailChip(
                    label: 'Bewegungen (30T)',
                    value: selected!.movements30d?.toString() ?? '-',
                  ),
                  _DetailChip(
                    label: 'Tage ohne Bewegung',
                    value: selected!.daysSinceMovement?.toString() ?? '-',
                  ),
                  _DetailChip(
                    label: context.tr('storageLocationFieldRack'),
                    value: rack.toString(),
                  ),
                  _DetailChip(
                    label: context.tr('storageLocationFieldLevel'),
                    value: level.toString(),
                  ),
                  _DetailChip(
                    label: context.tr('storageLocationFieldSlot'),
                    value: slot.toString(),
                  ),
                ],
              ),
            if (recommendations.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Empfohlene Maßnahmen',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Konkrete nächste Schritte inkl. benötigter Datenbasis.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Column(
                children: recommendations
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: _LocationActionRecommendationTile(item: item),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(value, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _LocationActionRecommendation {
  const _LocationActionRecommendation({
    required this.icon,
    required this.title,
    required this.summary,
    required this.dataBasis,
    this.critical = false,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String dataBasis;
  final bool critical;
}

class _LocationActionRecommendationTile extends StatelessWidget {
  const _LocationActionRecommendationTile({required this.item});

  final _LocationActionRecommendation item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.critical ? AppColors.error : AppColors.brandBlue;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(item.icon, size: 18, color: accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.summary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Daten: ${item.dataBasis}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _StorageLocationPrefs {
  const _StorageLocationPrefs({
    required this.filterQuery,
    required this.sortByAbc,
    required this.visibleSampleCount,
  });

  final String filterQuery;
  final bool sortByAbc;
  final int visibleSampleCount;

  factory _StorageLocationPrefs.fromState(AppState state) {
    return _StorageLocationPrefs(
      filterQuery: state.storageFilterQuery,
      sortByAbc: state.storageSortByAbc,
      visibleSampleCount: state.storageVisibleSampleCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _StorageLocationPrefs &&
        other.filterQuery == filterQuery &&
        other.sortByAbc == sortByAbc &&
        other.visibleSampleCount == visibleSampleCount;
  }

  @override
  int get hashCode => Object.hash(filterQuery, sortByAbc, visibleSampleCount);
}
