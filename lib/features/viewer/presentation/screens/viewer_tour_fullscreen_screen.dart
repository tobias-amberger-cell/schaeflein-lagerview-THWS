import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/viewer_heatmap.dart';
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
  bool _showUiChrome = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _showUiChrome = true;
      });
    });
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
    final isWideLayout = media.size.width >= 960;
    final headerReservedHeight = compactHeader ? 78.0 : 64.0;
    final headerTop = topInset + AppSpacing.sm;
    final dockHeight = isWideLayout ? 84.0 : 76.0;
    final dockBottom = bottomInset + AppSpacing.sm;
    final legendBottomOffset = dockBottom + dockHeight + AppSpacing.sm;
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
                    bottomOverlayReservedSpace: dockHeight + AppSpacing.md,
                    cameraToggleBottom: true,
                    showOperatorPanel: false,
                  )
                : adapter.buildViewerCanvas(context, warehouse),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.24),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const SizedBox(height: 120),
              ),
            ),
          ),
          Positioned(
            top: headerTop,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            child: _AnimatedOverlay(
              visible: _showUiChrome,
              offset: const Offset(0, -0.08),
              child: _TourHeaderBar(
                warehouseName: warehouse.name,
                tourActiveLabel: context.tr('tourActive'),
                zonesVisible: appState.viewerZonesVisible,
                heatmapVisible: appState.viewerHeatmapVisible,
                heatmapMetricLabel: context.tr(appState.viewerHeatmapMetric.labelKey),
                onClose: () => _closeTour(context, appState),
                onToggleLegend: () => setState(() => _showLegend = !_showLegend),
                showLegend: _showLegend,
              ),
            ),
          ),
          isNarrowPhone
              ? Positioned(
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  bottom: bottomInset + legendBottomOffset,
                  child: _AnimatedOverlay(
                    visible: _showLegend,
                    offset: const Offset(0, 0.08),
                    child: _FullscreenLegendCard(
                      heatmapVisible: appState.viewerHeatmapVisible,
                    ),
                  ),
                )
              : Positioned(
                  right: AppSpacing.sm,
                  bottom: bottomInset + legendBottomOffset,
                  child: _AnimatedOverlay(
                    visible: _showLegend,
                    offset: const Offset(0, 0.08),
                    child: _FullscreenLegendCard(
                      heatmapVisible: appState.viewerHeatmapVisible,
                    ),
                  ),
                ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: dockBottom,
            child: _AnimatedOverlay(
              visible: _showUiChrome,
              offset: const Offset(0, 0.08),
              child: _TourControlDock(
                isWideLayout: isWideLayout,
                zonesVisible: appState.viewerZonesVisible,
                heatmapVisible: appState.viewerHeatmapVisible,
                showLegend: _showLegend,
                onToggleZones: () {
                  final next = !appState.viewerZonesVisible;
                  appState.setViewerZonesVisible(next);
                },
                onToggleHeatmap: () {
                  final next = !appState.viewerHeatmapVisible;
                  appState.setViewerHeatmapVisible(next);
                },
                onReset: () {
                  appState.resetViewerState();
                  appState.setViewerTourRunning(true);
                },
                onToggleLegend: () => setState(() => _showLegend = !_showLegend),
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

class _AnimatedOverlay extends StatelessWidget {
  const _AnimatedOverlay({
    required this.visible,
    required this.child,
    this.offset = const Offset(0, 0.06),
  });

  final bool visible;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : offset,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          opacity: visible ? 1 : 0,
          child: child,
        ),
      ),
    );
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
          color: colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
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

class _TourHeaderBar extends StatelessWidget {
  const _TourHeaderBar({
    required this.warehouseName,
    required this.tourActiveLabel,
    required this.zonesVisible,
    required this.heatmapVisible,
    required this.heatmapMetricLabel,
    required this.onClose,
    required this.onToggleLegend,
    required this.showLegend,
  });

  final String warehouseName;
  final String tourActiveLabel;
  final bool zonesVisible;
  final bool heatmapVisible;
  final String heatmapMetricLabel;
  final VoidCallback onClose;
  final VoidCallback onToggleLegend;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final showStatusChips = width >= 980;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: onClose,
              icon: const Icon(Icons.close_fullscreen),
              label: Text(context.tr('viewerPauseTour')),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _TourInfoChip(
                title: warehouseName,
                subtitle: tourActiveLabel,
              ),
            ),
            if (showStatusChips) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              _TourStatusChip(
                icon:
                    zonesVisible ? Icons.grid_view_outlined : Icons.grid_off_outlined,
                label: zonesVisible ? 'Zonen an' : 'Zonen aus',
              ),
              const SizedBox(width: AppSpacing.xs),
              _TourStatusChip(
                icon: heatmapVisible
                    ? Icons.layers_outlined
                    : Icons.layers_clear_outlined,
                label: heatmapVisible ? heatmapMetricLabel : 'Heatmap aus',
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            IconButton.filledTonal(
              tooltip: showLegend
                  ? context.tr('viewerLegendHide')
                  : context.tr('viewerLegendShow'),
              onPressed: onToggleLegend,
              icon: Icon(
                showLegend ? Icons.legend_toggle : Icons.legend_toggle_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourStatusChip extends StatelessWidget {
  const _TourStatusChip({
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
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TourControlDock extends StatelessWidget {
  const _TourControlDock({
    required this.isWideLayout,
    required this.zonesVisible,
    required this.heatmapVisible,
    required this.showLegend,
    required this.onToggleZones,
    required this.onToggleHeatmap,
    required this.onReset,
    required this.onToggleLegend,
  });

  final bool isWideLayout;
  final bool zonesVisible;
  final bool heatmapVisible;
  final bool showLegend;
  final VoidCallback onToggleZones;
  final VoidCallback onToggleHeatmap;
  final VoidCallback onReset;
  final VoidCallback onToggleLegend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controls = <Widget>[
      _DockActionButton(
        active: zonesVisible,
        icon: zonesVisible ? Icons.grid_off_outlined : Icons.grid_view_outlined,
        label: zonesVisible ? 'Zonen aus' : 'Zonen an',
        onTap: onToggleZones,
      ),
      _DockActionButton(
        active: heatmapVisible,
        icon: heatmapVisible ? Icons.layers_clear_outlined : Icons.layers_outlined,
        label: heatmapVisible ? 'Heatmap aus' : 'Heatmap an',
        onTap: onToggleHeatmap,
      ),
      _DockActionButton(
        active: false,
        icon: Icons.refresh,
        label: 'Reset',
        onTap: onReset,
      ),
      _DockActionButton(
        active: showLegend,
        icon: showLegend ? Icons.legend_toggle : Icons.legend_toggle_outlined,
        label: showLegend ? 'Legende aus' : 'Legende an',
        onTap: onToggleLegend,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: isWideLayout
            ? Row(
                children: controls
                    .map(
                      (button) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: button,
                        ),
                      ),
                    )
                    .toList(growable: false),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: controls
                      .map(
                        (button) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: button,
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
      ),
    );
  }
}

class _DockActionButton extends StatelessWidget {
  const _DockActionButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = active
        ? colorScheme.primaryContainer.withValues(alpha: 0.8)
        : colorScheme.surfaceContainerHighest;
    final foreground = active ? colorScheme.onPrimaryContainer : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
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
