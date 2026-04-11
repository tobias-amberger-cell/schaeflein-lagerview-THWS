import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/viewer_adapter_factory.dart';
import '../../domain/viewer_type.dart';
import '../widgets/native_warehouse_3d_view.dart';

class ViewerTourFullscreenScreen extends StatefulWidget {
  const ViewerTourFullscreenScreen({super.key});

  @override
  State<ViewerTourFullscreenScreen> createState() =>
      _ViewerTourFullscreenScreenState();
}

class _ViewerTourFullscreenScreenState extends State<ViewerTourFullscreenScreen> {
  bool _showLegend = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final warehouse = appState.selectedWarehouse;
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final bottomInset = media.padding.bottom;
    final compactHeader = media.size.width < 900;
    final headerReservedHeight = compactHeader ? 68.0 : 56.0;
    final headerTop = topInset + AppSpacing.sm;
    final legendBottomOffset = compactHeader ? 132.0 : 112.0;
    final isNarrowPhone = media.size.width < 640;

    if (warehouse == null) {
      return EmptyState(
        icon: Icons.view_in_ar_outlined,
        title: context.tr('emptyViewerTitle'),
        message: context.tr('emptyViewerMessage'),
        actionLabel: context.tr('toWarehouseList'),
        onAction: () => context.go('/warehouses'),
      );
    }

    final adapter = ViewerAdapterFactory.create(appState.viewerType);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          appState.setViewerTourRunning(false);
        }
      },
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: adapter.type == ViewerType.nativePlaceholder
                ? NativeWarehouse3DView(
                    warehouse: warehouse,
                    model: warehouse.generatedModel,
                    tourRunning: true,
                    zonesVisible: appState.viewerZonesVisible,
                    heatmapVisible: appState.viewerHeatmapVisible,
                    heatmapMetric: appState.viewerHeatmapMetric,
                    heatmapData: appState.viewerHeatmapData,
                    focusZoneName: appState.viewerFocusZoneName,
                    focusRequestId: appState.viewerFocusRequestId,
                    focusRackNumber: appState.viewerFocusRackNumber,
                    focusLevelNumber: appState.viewerFocusLevelNumber,
                    focusSlotNumber: appState.viewerFocusSlotNumber,
                    focusLocationRequestId: appState.viewerFocusLocationRequestId,
                    enableFirstPersonControls: true,
                    topOverlayReservedSpace: headerReservedHeight + topInset + AppSpacing.sm,
                    bottomOverlayReservedSpace: 76,
                    cameraToggleBottom: true,
                    showOperatorPanel: false,
                  )
                : adapter.buildViewerCanvas(context, warehouse),
          ),
          Positioned(
            top: headerTop,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _closeTour(context, appState),
                  icon: const Icon(Icons.close_fullscreen),
                  label: Text(context.tr('viewerPauseTour')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _TourInfoChip(
                    title: warehouse.name,
                    subtitle: context.tr('tourActive'),
                  ),
                ),
              ],
            ),
          ),
          if (_showLegend)
            isNarrowPhone
                ? Positioned(
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    bottom: bottomInset + legendBottomOffset,
                    child: _FullscreenLegendCard(
                      heatmapVisible: appState.viewerHeatmapVisible,
                    ),
                  )
                : Positioned(
                    right: AppSpacing.sm,
                    bottom: bottomInset + legendBottomOffset,
                    child: _FullscreenLegendCard(
                      heatmapVisible: appState.viewerHeatmapVisible,
                    ),
                  ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: bottomInset + AppSpacing.sm,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: <Widget>[
                    IconButton.filledTonal(
                      tooltip: appState.viewerZonesVisible
                          ? context.tr('viewerHideZones')
                          : context.tr('viewerShowZones'),
                      onPressed: () {
                        final next = !appState.viewerZonesVisible;
                        appState.setViewerZonesVisible(next);
                      },
                      icon: Icon(
                        appState.viewerZonesVisible
                            ? Icons.grid_off_outlined
                            : Icons.grid_view_outlined,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filledTonal(
                      tooltip: appState.viewerHeatmapVisible
                          ? context.tr('viewerHideHeatmap')
                          : context.tr('viewerShowHeatmap'),
                      onPressed: () {
                        final next = !appState.viewerHeatmapVisible;
                        appState.setViewerHeatmapVisible(next);
                      },
                      icon: Icon(
                        appState.viewerHeatmapVisible
                            ? Icons.layers_clear_outlined
                            : Icons.layers_outlined,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.outlined(
                      tooltip: context.tr('viewerReset'),
                      onPressed: () {
                        appState.resetViewerState();
                        appState.setViewerTourRunning(true);
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filledTonal(
                      tooltip: _showLegend
                          ? context.tr('viewerLegendHide')
                          : context.tr('viewerLegendShow'),
                      onPressed: () => setState(() => _showLegend = !_showLegend),
                      icon: Icon(
                        _showLegend ? Icons.legend_toggle : Icons.legend_toggle_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _closeTour(BuildContext context, AppState appState) {
    appState.setViewerTourRunning(false);
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/viewer');
  }
}

class _FullscreenLegendCard extends StatelessWidget {
  const _FullscreenLegendCard({required this.heatmapVisible});

  final bool heatmapVisible;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.32;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.tr('viewerLegendTitle'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: const <Widget>[
                      _LegendBadge(color: Colors.red, text: 'hoch belegt'),
                      _LegendBadge(color: Colors.orange, text: 'mittel'),
                      _LegendBadge(color: Colors.green, text: 'niedrig/frei'),
                      _LegendBadge(color: Color(0xFF8D6E63), text: 'Palettenplatz'),
                      _LegendBadge(color: Colors.blueGrey, text: 'Förderlinie'),
                      _LegendBadge(color: Colors.amber, text: 'Stapler-Zone'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    heatmapVisible
                        ? context.tr('viewerLegendHeatmapOn')
                        : context.tr('viewerLegendHeatmapOff'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Kurz erklärt: Wischen dreht, Zwei Finger zoomen.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'FP-Modus: Linker Stick = Bewegung, rechter = Blick.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TourInfoChip extends StatelessWidget {
  const _TourInfoChip({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                const Icon(Icons.warehouse_outlined, size: 16),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
                    ),
                    child: Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendBadge extends StatelessWidget {
  const _LegendBadge({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
