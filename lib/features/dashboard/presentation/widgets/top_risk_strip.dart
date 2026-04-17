import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../models/viewer_heatmap.dart';
import 'dashboard_helpers.dart';

class TopRiskStrip extends StatelessWidget {
  const TopRiskStrip({
    super.key,
    required this.zones,
    required this.metric,
    required this.onOpenViewer,
    required this.onSelectZone,
  });

  final List<ViewerHeatmapEntry> zones;
  final ViewerHeatmapMetric metric;
  final VoidCallback onOpenViewer;
  final ValueChanged<String> onSelectZone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topRisks = zones.take(3).toList(growable: false);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.priority_high_rounded,
                    color: Color(0xFFDC2626)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Top 3 Risiken',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenViewer,
                  child: const Text('Heatmap öffnen'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Priorität nach ${heatmapMetricLabel(metric)}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (topRisks.isEmpty)
              Text(
                'Keine Risikodaten verfügbar.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 980
                      ? 3
                      : constraints.maxWidth >= 640
                          ? 2
                          : 1;
                  final cardWidth =
                      (constraints.maxWidth - (AppSpacing.sm * (columns - 1))) /
                          columns;
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: topRisks.map((zone) {
                      final raw = zone.valueFor(metric).clamp(0.0, 1.0);
                      final score = (raw * 100).round();
                      final tone = riskToneForScore(score);
                      return SizedBox(
                        width: cardWidth,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onSelectZone(zone.zoneName),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: tone.background,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: tone.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Icon(tone.icon,
                                          size: 16, color: tone.foreground),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          zone.zoneName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$score%',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: tone.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tone.label,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: tone.foreground,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
