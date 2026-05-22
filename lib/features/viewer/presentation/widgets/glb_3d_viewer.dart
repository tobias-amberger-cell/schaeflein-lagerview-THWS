// Wir nutzen direkt die interne ModelViewer-Klasse aus flutter_3d_controller,
// weil das exportierte Flutter3DViewer-Widget den Parameter innerModelViewerHtml
// nicht durchreicht. Damit koennen wir Hotspots als Kindelemente des
// <model-viewer>-Tags einfuegen, die im 3D-Raum am Modell angeheftet sind.
// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/src/core/modules/model_viewer/model_viewer.dart'
    as mv;

import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse_heatmap_layer.dart';

class Glb3DViewer extends StatelessWidget {
  const Glb3DViewer({
    super.key,
    required this.modelPath,
    this.heatmapData = const <ViewerHeatmapEntry>[],
    this.warehouseHeatmapLayer = const <WarehouseHeatmapLayerEntry>[],
    this.heatmapMetric,
    this.showHotspots = false,
    this.hideGenericHallHotspots = false,
    this.useFocusedFraming = true,
  });

  final String modelPath;
  final List<ViewerHeatmapEntry> heatmapData;
  final List<WarehouseHeatmapLayerEntry> warehouseHeatmapLayer;
  final ViewerHeatmapMetric? heatmapMetric;
  final bool showHotspots;
  final bool hideGenericHallHotspots;
  final bool useFocusedFraming;

  static bool canRender(String? path) {
    if (path == null) {
      return false;
    }
    final lower = path.trim().toLowerCase();
    if (!lower.endsWith('.glb') && !lower.endsWith('.gltf')) {
      return false;
    }
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedSrc = _resolveModelSrc(modelPath);
    if (kDebugMode) {
      debugPrint('Glb3DViewer src: $resolvedSrc');
    }
    final activeMetric = heatmapMetric;
    final activeHotspots = showHotspots
        ? (warehouseHeatmapLayer.isNotEmpty
              ? _csvHotspots(warehouseHeatmapLayer)
              : (activeMetric != null
                    ? _zoneHotspots(
                        heatmapData,
                        activeMetric,
                        hideGenericHallHotspots: hideGenericHallHotspots,
                      )
                    : const <_Hotspot>[]))
        : const <_Hotspot>[];

    // ValueKey erzwingt einen Rebuild des ModelViewers, wenn sich die
    // Hotspot-Konfiguration aendert. Andernfalls aktualisiert das Package
    // das innerModelViewerHtml nicht.
    final rebuildKey = ValueKey<String>(
      'glb-${activeHotspots.length}-${activeHotspots.fold<int>(0, (sum, h) => sum + (h.value * 1000).round())}',
    );

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: mv.ModelViewer(
        key: rebuildKey,
        src: resolvedSrc,
        progressBarColor: Theme.of(context).colorScheme.primary,
        loading: mv.Loading.eager,
        cameraControls: true,
        touchAction: mv.TouchAction.none,
        interactionPrompt: mv.InteractionPrompt.none,
        autoPlay: false,
        autoRotate: false,
        autoRotateDelay: null,
        rotationPerSecond: null,
        cameraTarget: null,
        cameraOrbit: null,
        minCameraOrbit: null,
        maxCameraOrbit: null,
        fieldOfView: null,
        minFieldOfView: null,
        maxFieldOfView: null,
        interpolationDecay: null,
        debugLogging: false,
        disableTap: false,
        ar: false,
        relatedCss: _hotspotCss,
        innerModelViewerHtml: activeHotspots.isEmpty
            ? null
            : activeHotspots.map((h) => h.toHtml()).join('\n'),
      ),
    );
  }

  static List<_Hotspot> _zoneHotspots(
    List<ViewerHeatmapEntry> data,
    ViewerHeatmapMetric metric,
    {
    bool hideGenericHallHotspots = false,
    }
  ) {
    if (data.isEmpty) {
      return const <_Hotspot>[];
    }
    // Wir kennen die Geometrie der GLB nicht exakt, verteilen die Hotspots
    // deshalb in einem Raster ueber dem Modellzentrum (Y=1.2 ueber Boden).
    // Die Position ist eine Naeherung; wenn die GLB groesser/kleiner ist,
    // muessen die Konstanten angepasst werden.
    final sourceData = hideGenericHallHotspots
        ? data
            .where((entry) => !_isGenericHallZoneName(entry.zoneName))
            .toList(growable: false)
        : data;
    final sorted = <ViewerHeatmapEntry>[...sourceData]
      ..sort((a, b) => _safeUnitValue(b.valueFor(metric)).compareTo(
            _safeUnitValue(a.valueFor(metric)),
          ));
    final visible = sorted.take(8).toList(growable: false);
    if (visible.isEmpty) {
      return const <_Hotspot>[];
    }
    final cols = visible.length <= 3 ? visible.length : 4;
    final rows = (visible.length / cols).ceil();
    final hotspots = <_Hotspot>[];
    for (var i = 0; i < visible.length; i++) {
      final entry = visible[i];
      final col = i % cols;
      final row = i ~/ cols;
      final x = (col - (cols - 1) / 2.0) * 0.45;
      final z = (row - (rows - 1) / 2.0) * 0.45;
      final value = _safeUnitValue(entry.valueFor(metric));
      hotspots.add(
        _Hotspot(
          slot: 'hotspot-zone-$i',
          x: x,
          y: 1.2,
          z: z,
          label: entry.zoneName,
          value: value,
        ),
      );
    }
    return hotspots;
  }

  static List<_Hotspot> _csvHotspots(
    List<WarehouseHeatmapLayerEntry> entries,
  ) {
    if (entries.isEmpty) {
      return const <_Hotspot>[];
    }
    final sumByRack = <int, double>{};
    final countByRack = <int, int>{};
    for (final entry in entries) {
      if (entry.regal <= 0) {
        continue;
      }
      sumByRack[entry.regal] = (sumByRack[entry.regal] ?? 0) + entry.utilizationUnit;
      countByRack[entry.regal] = (countByRack[entry.regal] ?? 0) + 1;
    }
    if (sumByRack.isEmpty) {
      return const <_Hotspot>[];
    }
    final racks = sumByRack.keys.toList(growable: false)..sort();
    final maxHotspots = 36;
    final visibleRacks = racks.take(maxHotspots).toList(growable: false);
    final cols = visibleRacks.length <= 6 ? visibleRacks.length : 6;
    final rows = (visibleRacks.length / cols).ceil();
    final hotspots = <_Hotspot>[];
    for (var i = 0; i < visibleRacks.length; i++) {
      final rack = visibleRacks[i];
      final avg = ((sumByRack[rack] ?? 0.0) / (countByRack[rack] ?? 1))
          .clamp(0, 1)
          .toDouble();
      final col = i % cols;
      final row = i ~/ cols;
      final x = (col - (cols - 1) / 2.0) * 0.62;
      final z = (row - (rows - 1) / 2.0) * 0.52;
      hotspots.add(
        _Hotspot(
          slot: 'hotspot-rack-$rack',
          x: x,
          y: 1.25,
          z: z,
          label: 'R$rack',
          value: avg,
        ),
      );
    }
    return hotspots;
  }
}

String _resolveModelSrc(String rawPath) {
  final normalized = rawPath.trim();
  if (normalized.isEmpty) {
    return rawPath;
  }
  if (!kIsWeb) {
    return normalized;
  }
  final asLower = normalized.toLowerCase();
  final isAbsolute =
      asLower.startsWith('http://') ||
      asLower.startsWith('https://') ||
      asLower.startsWith('data:') ||
      asLower.startsWith('blob:') ||
      asLower.startsWith('file://') ||
      normalized.startsWith('/');
  if (isAbsolute) {
    return normalized;
  }
  return Uri.base.resolve(normalized).toString();
}

double _safeUnitValue(double raw) {
  if (!raw.isFinite) {
    return 0.0;
  }
  return raw.clamp(0.0, 1.0).toDouble();
}

bool _isGenericHallZoneName(String rawName) {
  final normalized = rawName.trim().toLowerCase();
  final hallRegex = RegExp(r'^(halle|hall)\s*\d+$', caseSensitive: false);
  return hallRegex.hasMatch(normalized);
}

class _Hotspot {
  const _Hotspot({
    required this.slot,
    required this.x,
    required this.y,
    required this.z,
    required this.label,
    required this.value,
  });

  final String slot;
  final double x;
  final double y;
  final double z;
  final String label;
  final double value;

  String _hexColor() {
    if (value >= 0.85) return '#c62828';
    if (value >= 0.65) return '#ef6c00';
    if (value >= 0.45) return '#f9a825';
    return '#2e7d32';
  }

  String toHtml() {
    final color = _hexColor();
    final percent = (value * 100).round();
    final escapedLabel = label
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<button class="HotspotZone" slot="$slot" data-position="$x $y $z" data-normal="0 1 0" data-visibility-attribute="visible">'
        '<div class="HotspotLabel" style="background:$color;">'
        '<span>$escapedLabel</span>'
        '<strong>$percent%</strong>'
        '</div>'
        '</button>';
  }
}

const String _hotspotCss = '''
.HotspotZone {
  border: none;
  background: transparent;
  pointer-events: auto;
  cursor: pointer;
  width: 18px;
  height: 18px;
  border-radius: 999px;
  padding: 0;
  position: relative;
  outline: none;
  display: block;
}
.HotspotZone::before {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: 999px;
  background: rgba(255,255,255,0.95);
  box-shadow: 0 0 0 3px rgba(0,0,0,0.25);
}
.HotspotLabel {
  position: absolute;
  bottom: 22px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  gap: 6px;
  align-items: center;
  padding: 4px 10px;
  border-radius: 999px;
  color: white;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  font-size: 12px;
  white-space: nowrap;
  box-shadow: 0 4px 12px rgba(0,0,0,0.25);
}
.HotspotLabel span { font-weight: 500; }
.HotspotLabel strong { font-weight: 700; }
''';
