import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../models/viewer_heatmap.dart';

class HeatmapZoneOverlay extends StatelessWidget {
  const HeatmapZoneOverlay({
    super.key,
    required this.metric,
    required this.data,
    this.onZoneTap,
    this.hideGenericHallZones = false,
  });

  final ViewerHeatmapMetric metric;
  final List<ViewerHeatmapEntry> data;
  final void Function(ViewerHeatmapEntry, ViewerHeatmapMetric)? onZoneTap;
  final bool hideGenericHallZones;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860
            ? 4
            : constraints.maxWidth >= 620
            ? 3
            : 2;
        final maxItems = constraints.maxWidth >= 860
            ? 14
            : constraints.maxWidth >= 620
            ? 10
            : 6;
        final itemWidth =
            ((constraints.maxWidth - ((columns + 1) * AppSpacing.sm)) / columns)
                .clamp(90.0, 220.0);
        final sourceEntries = hideGenericHallZones
            ? data
                .where((entry) => !_isGenericHallZoneName(entry.zoneName))
                .toList(growable: false)
            : data;
        final sortedEntries = <ViewerHeatmapEntry>[...sourceEntries]
          ..sort((a, b) => b.valueFor(metric).compareTo(a.valueFor(metric)));
        final visibleEntries = sortedEntries
            .take(maxItems)
            .toList(growable: false);

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: visibleEntries
                .map(
                  (entry) => SizedBox(
                    width: itemWidth,
                    child: _HeatmapZoneTile(
                      zoneName: entry.zoneName,
                      value: entry.valueFor(metric),
                      onTap: onZoneTap == null
                          ? null
                          : () => onZoneTap!(entry, metric),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

bool _isGenericHallZoneName(String rawName) {
  final normalized = rawName.trim().toLowerCase();
  final hallRegex = RegExp(r'^(halle|hall)\s*\d+$', caseSensitive: false);
  return hallRegex.hasMatch(normalized);
}

class _HeatmapZoneTile extends StatelessWidget {
  const _HeatmapZoneTile({
    required this.zoneName,
    required this.value,
    required this.onTap,
  });

  final String zoneName;
  final double value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0, 1).toDouble();
    final tileColor = heatColorForValue(safeValue);
    final textColor = safeValue > 0.72 ? Colors.white : Colors.black87;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: tileColor.withValues(alpha: 0.33),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: tileColor.withValues(alpha: 0.74),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    zoneName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${(safeValue * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: textColor,
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

Color heatColorForValue(double value) {
  final safeValue = value.clamp(0, 1).toDouble();
  if (safeValue >= 0.85) {
    return Colors.red.shade700;
  }
  if (safeValue >= 0.65) {
    return Colors.orange.shade700;
  }
  if (safeValue >= 0.45) {
    return Colors.amber.shade700;
  }
  return Colors.green.shade700;
}
