import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/abc_analysis_bar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../domain/viewer_adapter_factory.dart';
import '../../domain/viewer_type.dart';
import '../widgets/glb_3d_viewer.dart';
import '../widgets/heatmap_zone_overlay.dart';
import '../widgets/native_warehouse_3d_view.dart';
import '../widgets/unity_runtime_view.dart';
import '../widgets/unity_source_notice.dart';

class ViewerTourFullscreenScreen extends StatefulWidget {
  const ViewerTourFullscreenScreen({super.key});

  @override
  State<ViewerTourFullscreenScreen> createState() =>
      _ViewerTourFullscreenScreenState();
}

class _ViewerTourFullscreenScreenState extends State<ViewerTourFullscreenScreen> {
  // Legende kann unabhängig von der restlichen Steuerleiste ein-/ausgeblendet werden.
  bool _showLegend = false;
  // "UI-Chrome" steuert Header + Dock + Hilfsanzeigen.
  bool _showUiChrome = false;
  // Timer blendet UI nach Inaktivität automatisch aus.
  Timer? _chromeAutoHideTimer;
  // Einmaliger Hinweis für Nutzer, dass Tippen das Menü einblendet.
  bool _showTapHint = true;

  @override
  void initState() {
    super.initState();
    // Immersiver Modus für echte Vollbild-Nutzung.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // Heatmap beim Tour-Start einschalten, damit das Overlay sofort sichtbar ist.
      // Der Nutzer kann sie ueber das Dock weiterhin ausblenden.
      final appState = context.read<AppState>();
      if (!appState.viewerHeatmapVisible) {
        appState.setViewerHeatmapVisible(true);
      }
      setState(() {
        _showUiChrome = true;
      });
      // Nach App-Start kurz zeigen und dann automatisch verstecken.
      _armChromeAutoHide();
    });
  }

  @override
  void dispose() {
    // Timer sauber schließen, sonst läuft er nach Screen-Wechsel weiter.
    _chromeAutoHideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Alles auf das aktuell aktive Lager ausrichten.
    final appState = context.watch<AppState>();
    final warehouse = appState.riskFocusWarehouse;
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
      unawaited(appState.syncWarehouses(force: true));
      return EmptyState(
        icon: Icons.view_in_ar_outlined,
        title: '3D Ansicht wird vorbereitet',
        message: appState.isWarehousesSyncing
            ? 'Lagerdaten werden aus der API geladen...'
            : (appState.warehouseApiError?.trim().isNotEmpty ?? false)
                ? appState.warehouseApiError!.trim()
                : 'Keine Lagerdaten aus der API gefunden. Bitte API pruefen und erneut laden.',
        actionLabel: appState.isWarehousesSyncing ? null : context.tr('retry'),
        onAction: appState.isWarehousesSyncing
            ? null
            : () => appState.syncWarehouses(force: true),
      );
    }

    final adapter = ViewerAdapterFactory.create(appState.viewerType);
    final externalModelPath =
        appState.getExternalModelPathForWarehouse(warehouse.id);
    final useGlbViewer = Glb3DViewer.canRender(externalModelPath);
    final useUnitySource = isUnitySceneSourcePath(externalModelPath);
    unawaited(appState.ensureWarehouseHeatmapLayerLoaded());

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          appState.setViewerTourRunning(false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Tap auf freie Fläche toggelt die komplette UI-Chrome.
        onTap: _toggleUiChromeVisibility,
        child: Stack(
          children: <Widget>[
          // Im GLB-Modus den 3D-Viewer eingrenzen, damit oberhalb und unterhalb
          // Platz fuer Heatmap- und ABC-Overlays bleibt. Sonst rendert das
          // model-viewer-DOM-Element auf Web ueber den Flutter-Widgets und
          // verdeckt sie (Platform-View-Z-Order).
          if (useGlbViewer) ...<Widget>[
            Positioned(
              top: headerTop +
                  headerReservedHeight +
                  AppSpacing.sm +
                  (appState.viewerHeatmapVisible &&
                          appState.viewerHeatmapData.isNotEmpty
                      ? 140
                      : 0),
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              bottom: dockBottom + dockHeight + AppSpacing.md + 80,
              child: Glb3DViewer(
                modelPath: externalModelPath!,
                heatmapData: appState.viewerHeatmapData,
                warehouseHeatmapLayer: appState.warehouseHeatmapLayer,
                heatmapMetric: appState.viewerHeatmapMetric,
                showHotspots: appState.viewerHeatmapVisible ||
                    appState.warehouseHeatmapLayer.isNotEmpty,
                hideGenericHallHotspots: true,
              ),
            ),
            if (appState.viewerHeatmapVisible &&
                appState.viewerHeatmapData.isNotEmpty)
              Positioned(
                top: headerTop + headerReservedHeight + AppSpacing.sm,
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: HeatmapZoneOverlay(
                    metric: appState.viewerHeatmapMetric,
                    data: appState.viewerHeatmapData,
                    hideGenericHallZones: true,
                  ),
                ),
              ),
            Positioned(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              bottom: dockBottom + dockHeight + AppSpacing.sm,
              child: _TourAbcSummaryCard(warehouse: warehouse),
            ),
          ] else if (useUnitySource)
            Positioned.fill(
              child: UnityRuntimeView(scenePath: externalModelPath!),
            )
          else
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
                      focusLocationRequestId:
                          appState.viewerFocusLocationRequestId,
                      enableFirstPersonControls: true,
                      // Reserviert Platz fuer Overlays, damit UI und 3D nicht kollidieren.
                      topOverlayReservedSpace:
                          headerReservedHeight + topInset + AppSpacing.sm,
                      bottomOverlayReservedSpace: dockHeight + AppSpacing.md,
                      cameraToggleBottom: true,
                      showOperatorPanel: false,
                    )
                  : adapter.buildViewerCanvas(context, warehouse),
            ),
          if (useUnitySource)
            Positioned(
              top: headerTop + AppSpacing.sm,
              right: AppSpacing.sm,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: UnitySourceNotice(
                  scenePath: externalModelPath!,
                  compact: true,
                ),
              ),
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
                onToggleLegend: _toggleLegend,
                showLegend: _showLegend,
              ),
            ),
          ),
          isNarrowPhone
              // Auf sehr schmalen Geräten mittig statt rechts andocken.
              ? Positioned(
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  bottom: bottomInset + legendBottomOffset,
                  child: _AnimatedOverlay(
                    visible: _showLegend && _showUiChrome,
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
                    visible: _showLegend && _showUiChrome,
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
                  // Jede Nutzeraktion "berührt" die UI und startet Auto-Hide neu.
                  _touchUi();
                  final next = !appState.viewerZonesVisible;
                  appState.setViewerZonesVisible(next);
                },
                onToggleHeatmap: () {
                  _touchUi();
                  final next = !appState.viewerHeatmapVisible;
                  appState.setViewerHeatmapVisible(next);
                },
                onReset: () {
                  _touchUi();
                  // Viewer-Filter zurücksetzen und Tour-Kontext aktiv halten.
                  appState.resetViewerState();
                  appState.setViewerTourRunning(true);
                },
                onToggleLegend: _toggleLegend,
              ),
            ),
          ),
          if (!_showUiChrome)
            // Minimale Wiederherstellungsaktion, wenn alles ausgeblendet ist.
            Positioned(
              top: headerTop,
              right: AppSpacing.sm,
              child: IconButton.filledTonal(
                tooltip: 'Menue einblenden',
                onPressed: _toggleUiChromeVisibility,
                icon: const Icon(Icons.visibility_outlined),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: dockBottom + dockHeight + AppSpacing.sm,
            child: IgnorePointer(
              child: _AnimatedOverlay(
                // Tap-Hinweis nur solange anzeigen, bis Nutzer mit UI interagiert.
                visible: !_showUiChrome && _showTapHint,
                child: const _FullscreenTapHint(),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleUiChromeVisibility() {
    // Benutzerwunsch hat Vorrang: sofort umschalten.
    setState(() {
      _showUiChrome = !_showUiChrome;
      _showTapHint = false;
    });
    if (_showUiChrome) {
      _armChromeAutoHide();
    } else {
      _chromeAutoHideTimer?.cancel();
    }
  }

  void _toggleLegend() {
    // Legendentoggle zählt als Interaktion und hält die UI sichtbar.
    _touchUi();
    setState(() {
      _showLegend = !_showLegend;
    });
  }

  void _touchUi() {
    // Weckt die UI auf und entfernt den Erst-Hinweis beim ersten Kontakt.
    if (!_showUiChrome) {
      setState(() {
        _showUiChrome = true;
        _showTapHint = false;
      });
    } else if (_showTapHint) {
      setState(() {
        _showTapHint = false;
      });
    }
    _armChromeAutoHide();
  }

  void _armChromeAutoHide([Duration duration = const Duration(seconds: 5)]) {
    // Immer genau ein aktiver Timer; alte Instanz vorher stoppen.
    _chromeAutoHideTimer?.cancel();
    _chromeAutoHideTimer = Timer(duration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showUiChrome = false;
      });
    });
  }
  void _closeTour(BuildContext context, AppState appState) {
    // Tour-Flag zurücksetzen und unabhaengig von der Stack-Tiefe sicher zurueck.
    appState.setViewerTourRunning(false);
    if (!context.mounted) {
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
    // Sichtbarkeit wird weich animiert statt hart ein-/ausgeblendet.
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
    // Legende ist bewusst scrollbar, damit sie auch bei kleinen Displays vollständig bleibt.
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
                    'Kurz erklaert: Wischen dreht, zwei Finger zoomen.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'FP-Modus: Links bewegen, rechts Blickrichtung steuern.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Steuerleisten blenden sich nach kurzer Zeit aus.',
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
    // Header zeigt Tour-Kontext + zentrale Quick-Status-Infos.
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
    return StatusPill(
      icon: icon,
      label: label,
      backgroundColor: colorScheme.surfaceContainerHighest,
      foregroundColor: colorScheme.onSurfaceVariant,
      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
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
    // Dock bündelt alle manipulierenden Viewer-Aktionen.
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
    // Einheitlicher Button für aktiven/inaktiven Steuerstatus.
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

class _FullscreenTapHint extends StatelessWidget {
  const _FullscreenTapHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Text('Tippen fuer Menue'),
        ),
      ),
    );
  }
}

class _TourAbcSummaryCard extends StatelessWidget {
  const _TourAbcSummaryCard({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final abc = warehouse.abcAnalysis;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('tourAbcSummaryTitle'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AbcAnalysisBar(
              aCount: abc.aCount,
              bCount: abc.bCount,
              cCount: abc.cCount,
              height: 10,
            ),
          ],
        ),
      ),
    );
  }
}
