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
      color: colorScheme.surfaceContainer,
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
                const Icon(Icons.radar_rounded, color: Color(0xFFDC2626)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Risiko-Radar (Top 3)',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenViewer,
                  child: const Text('Heatmap oeffnen'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ranking nach ${heatmapMetricLabel(metric)}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (topRisks.isEmpty)
              Text(
                'Keine Risikodaten verfuegbar.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else ...<Widget>[
              _RiskSummaryRow(risks: topRisks, metric: metric),
              const SizedBox(height: AppSpacing.sm),
              ...topRisks.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final zone = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: rank == topRisks.length ? 0 : AppSpacing.xs,
                  ),
                  child: _RiskRankRow(
                    rank: rank,
                    zone: zone,
                    metric: metric,
                    onTap: () => onSelectZone(zone.zoneName),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _RiskSummaryRow extends StatelessWidget {
  const _RiskSummaryRow({required this.risks, required this.metric});

  final List<ViewerHeatmapEntry> risks;
  final ViewerHeatmapMetric metric;

  @override
  Widget build(BuildContext context) {
    final maxScore = risks
        .map((risk) => (risk.valueFor(metric).clamp(0.0, 1.0) * 100).round())
        .fold<int>(0, (max, score) => score > max ? score : max);
    final avgScore =
        risks
            .map((risk) => risk.valueFor(metric).clamp(0.0, 1.0))
            .fold<double>(0, (sum, value) => sum + value) /
        risks.length;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _RiskSummaryChip(label: 'Max', value: '$maxScore%'),
        _RiskSummaryChip(
          label: 'Schnitt',
          value: '${(avgScore * 100).round()}%',
        ),
        _RiskSummaryChip(label: 'Zonen', value: '${risks.length}'),
      ],
    );
  }
}

class _RiskSummaryChip extends StatelessWidget {
  const _RiskSummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
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
        child: Text(
          '$label: $value',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _RiskRankRow extends StatelessWidget {
  const _RiskRankRow({
    required this.rank,
    required this.zone,
    required this.metric,
    required this.onTap,
  });

  final int rank;
  final ViewerHeatmapEntry zone;
  final ViewerHeatmapMetric metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final rawScore = zone.valueFor(metric).clamp(0.0, 1.0);
    final scorePercent = (rawScore * 100).round();
    final tone = riskToneForScore(scorePercent);

    return Container(
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
              CircleAvatar(
                radius: 14,
                backgroundColor: tone.border,
                child: Text(
                  '$rank',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: tone.foreground,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      zone.zoneName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
              Text(
                '$scorePercent%',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: rawScore,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerLowest,
              valueColor: AlwaysStoppedAnimation<Color>(tone.foreground),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            children: <Widget>[
              _RiskMiniStat(
                label: 'Auslastung',
                value: '${(zone.utilization * 100).round()}%',
              ),
              _RiskMiniStat(
                label: 'Pick',
                value: '${(zone.pickRate * 100).round()}%',
              ),
              _RiskMiniStat(
                label: 'Stau',
                value: '${(zone.congestion * 100).round()}%',
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.center_focus_strong, size: 16),
              label: const Text('Im 3D fokussieren'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskMiniStat extends StatelessWidget {
  const _RiskMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      '$label: $value',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
