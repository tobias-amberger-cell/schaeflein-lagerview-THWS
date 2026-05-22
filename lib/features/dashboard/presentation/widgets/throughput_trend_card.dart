import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/warehouse_trend.dart';

class ThroughputTrendCard extends StatelessWidget {
  const ThroughputTrendCard({
    super.key,
    required this.trendFuture,
  });

  final Future<List<WarehouseTrendPoint>> trendFuture;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
                Icon(Icons.timeline_rounded, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Leistungs-Trend',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Auftragsabschluesse pro Tag (warehouse.db).',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FutureBuilder<List<WarehouseTrendPoint>>(
              future: trendFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _TrendSkeleton();
                }
                final trend =
                    snapshot.data ?? const <WarehouseTrendPoint>[];
                if (trend.isEmpty) {
                  return Text(
                    'Keine Trenddaten gefunden.',
                    style: textTheme.bodySmall,
                  );
                }
                final avg = trend
                        .map((point) => point.value)
                        .fold<int>(0, (a, b) => a + b) /
                    trend.length;
                final peak = trend.reduce(
                  (a, b) => a.value >= b.value ? a : b,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        _TrendStat(
                          label: 'Ø/Tag',
                          value: avg.round().toString(),
                          color: AppColors.brandBlue,
                        ),
                        _TrendStat(
                          label: 'Peak',
                          value: peak.value.toString(),
                          note: peak.shortLabel,
                          color: AppColors.brandOrange,
                        ),
                        _TrendStat(
                          label: 'Letzter Tag',
                          value: trend.last.value.toString(),
                          note: trend.last.shortLabel,
                          color: AppColors.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _TrendChart(trend: trend),
                    const SizedBox(height: AppSpacing.xs),
                    _TrendLabels(trend: trend),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: List<Widget>.generate(
        8,
        (index) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 64 + (index % 3) * 12,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendStat extends StatelessWidget {
  const _TrendStat({
    required this.label,
    required this.value,
    required this.color,
    this.note,
  });

  final String label;
  final String value;
  final String? note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
          Text(
            '$label: $value${note == null ? '' : ' ($note)'}',
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.trend});

  final List<WarehouseTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      child: CustomPaint(
        painter: _TrendChartPainter(
          trend: trend,
          barColor: colorScheme.primary,
          lineColor: AppColors.brandOrange,
        ),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.trend,
    required this.barColor,
    required this.lineColor,
  });

  final List<WarehouseTrendPoint> trend;
  final Color barColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (trend.isEmpty) {
      return;
    }
    final maxValue =
        trend.map((point) => point.value).fold<int>(0, max).clamp(1, 999999);
    final barPaint = Paint()
      ..color = barColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()..color = lineColor;

    final chartHeight = size.height;
    final step = size.width / trend.length;
    final barWidth = step * 0.45;
    final linePath = Path();

    for (var i = 0; i < trend.length; i++) {
      final value = trend[i].value.toDouble();
      final barHeight = (value / maxValue) * (chartHeight * 0.85);
      final xCenter = step * i + step / 2;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(xCenter, chartHeight - barHeight / 2),
          width: barWidth,
          height: barHeight,
        ),
        const Radius.circular(999),
      );
      canvas.drawRRect(barRect, barPaint);

      final lineY = chartHeight - barHeight;
      if (i == 0) {
        linePath.moveTo(xCenter, lineY);
      } else {
        linePath.lineTo(xCenter, lineY);
      }
    }

    canvas.drawPath(linePath, linePaint);

    for (var i = 0; i < trend.length; i++) {
      final value = trend[i].value.toDouble();
      final barHeight = (value / maxValue) * (chartHeight * 0.85);
      final xCenter = step * i + step / 2;
      final lineY = chartHeight - barHeight;
      canvas.drawCircle(Offset(xCenter, lineY), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.trend != trend ||
        oldDelegate.barColor != barColor ||
        oldDelegate.lineColor != lineColor;
  }
}

class _TrendLabels extends StatelessWidget {
  const _TrendLabels({required this.trend});

  final List<WarehouseTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: trend
          .map(
            (point) => Expanded(
              child: Text(
                point.shortLabel,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

