import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/order_volume_point.dart';

class OrderVolumeCard extends StatelessWidget {
  const OrderVolumeCard({
    super.key,
    required this.points,
    this.isLoading = false,
  });

  final List<OrderVolumePoint> points;
  final bool isLoading;

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
                Icon(Icons.receipt_long_outlined, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.tr('orderVolumeTitle'),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('orderVolumeSubtitle'),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (isLoading)
              const _OrderVolumeSkeleton()
            else if (points.isEmpty)
              Text(
                context.tr('orderVolumeEmpty'),
                style: textTheme.bodySmall,
              )
            else
              _OrderVolumeContent(points: points),
          ],
        ),
      ),
    );
  }
}

class _OrderVolumeContent extends StatelessWidget {
  const _OrderVolumeContent({required this.points});

  final List<OrderVolumePoint> points;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalOrders =
        points.fold<int>(0, (sum, point) => sum + point.orders);
    final totalPositions =
        points.fold<int>(0, (sum, point) => sum + point.positions);
    final avgOrders =
        points.isEmpty ? 0.0 : totalOrders / points.length;
    final peak = points.reduce((a, b) => a.orders >= b.orders ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            _OrderStat(
              label: context.tr('orderVolumePerDay'),
              value: '${avgOrders.round()} ${context.tr('orderVolumeOrdersUnit')}',
              color: colorScheme.primary,
            ),
            _OrderStat(
              label: context.tr('orderVolumePeak'),
              value: '${peak.orders}',
              note: peak.shortLabel,
              color: AppColors.brandOrange,
            ),
            _OrderStat(
              label: context.tr('orderVolumePositionsTotal'),
              value: '$totalPositions',
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 220,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, 220),
                painter: _OrderVolumePainter(
                  points: points,
                  avg: avgOrders,
                  peakIndex: points.indexOf(peak),
                  barColor: colorScheme.primary,
                  peakColor: AppColors.brandOrange,
                  gridColor:
                      colorScheme.outlineVariant.withValues(alpha: 0.45),
                  avgColor:
                      colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ) ??
                      const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: _OrderVolumeLabels(points: points),
        ),
      ],
    );
  }
}

class _OrderVolumePainter extends CustomPainter {
  _OrderVolumePainter({
    required this.points,
    required this.avg,
    required this.peakIndex,
    required this.barColor,
    required this.peakColor,
    required this.gridColor,
    required this.avgColor,
    required this.labelStyle,
  });

  final List<OrderVolumePoint> points;
  final double avg;
  final int peakIndex;
  final Color barColor;
  final Color peakColor;
  final Color gridColor;
  final Color avgColor;
  final TextStyle labelStyle;

  static const double _leftPad = 44;
  static const double _rightPad = 8;
  static const double _topPad = 12;
  static const double _bottomPad = 8;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final chartW = size.width - _leftPad - _rightPad;
    final chartH = size.height - _topPad - _bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    final maxValue = points
        .map((p) => p.orders)
        .fold<int>(0, max)
        .clamp(1, 9999999)
        .toInt();
    final niceMax = _niceMax(maxValue);

    // Horizontale Gridlines (gestrichelt) + Y-Achsen-Labels.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = _topPad + chartH * i / 4;
      _drawDashed(
        canvas,
        Offset(_leftPad, y),
        Offset(_leftPad + chartW, y),
        gridPaint,
        dash: 3,
        gap: 4,
      );
      final v = (niceMax * (4 - i) / 4).round();
      final tp = TextPainter(
        text: TextSpan(text: '$v', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_leftPad - tp.width - 6, y - tp.height / 2));
    }

    // Mittelwert-Linie.
    final avgY = _topPad + chartH * (1 - avg / niceMax);
    _drawDashed(
      canvas,
      Offset(_leftPad, avgY),
      Offset(_leftPad + chartW, avgY),
      Paint()
        ..color = avgColor
        ..strokeWidth = 1,
      dash: 4,
      gap: 4,
    );
    final avgTp = TextPainter(
      text: TextSpan(
        text: 'Ø ${avg.toStringAsFixed(0)}',
        style: labelStyle.copyWith(
          color: avgColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    avgTp.paint(
      canvas,
      Offset(_leftPad + chartW - avgTp.width - 4, avgY - avgTp.height - 2),
    );

    // Balken.
    final step = chartW / points.length;
    final barWidth = (step * 0.6).clamp(2.0, 22.0);
    for (var i = 0; i < points.length; i++) {
      final v = points[i].orders.toDouble();
      final barH = chartH * (v / niceMax);
      final xCenter = _leftPad + step * i + step / 2;
      final top = _topPad + chartH - barH;
      final rect = Rect.fromLTWH(xCenter - barWidth / 2, top, barWidth, barH);
      final isPeak = i == peakIndex;
      final topColor = isPeak ? peakColor : barColor;
      final bottomColor =
          isPeak ? peakColor.withValues(alpha: 0.18) : barColor.withValues(alpha: 0.12);
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          <Color>[topColor.withValues(alpha: 0.95), bottomColor],
        );
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(rrect, paint);

      // Peak: kleiner Punkt + Label oberhalb.
      if (isPeak) {
        canvas.drawCircle(
          Offset(xCenter, top - 4),
          3,
          Paint()..color = peakColor,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${points[i].orders}',
            style: labelStyle.copyWith(
              color: peakColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = (xCenter - tp.width / 2)
            .clamp(_leftPad, _leftPad + chartW - tp.width);
        tp.paint(canvas, Offset(lx, (top - tp.height - 8).clamp(_topPad - 4, double.infinity)));
      }
    }
  }

  void _drawDashed(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final total = (to - from).distance;
    if (total <= 0) return;
    final dir = (to - from) / total;
    var traveled = 0.0;
    while (traveled < total) {
      final end = (traveled + dash).clamp(0.0, total);
      canvas.drawLine(from + dir * traveled, from + dir * end, paint);
      traveled += dash + gap;
    }
  }

  int _niceMax(int v) {
    if (v <= 0) return 1;
    final magnitude = pow(10, v.toString().length - 1).toInt();
    final normalized = v / magnitude;
    final step = normalized <= 1
        ? 1
        : normalized <= 2
            ? 2
            : normalized <= 5
                ? 5
                : 10;
    return step * magnitude;
  }

  @override
  bool shouldRepaint(covariant _OrderVolumePainter old) =>
      old.points != points ||
      old.avg != avg ||
      old.peakIndex != peakIndex ||
      old.barColor != barColor ||
      old.peakColor != peakColor ||
      old.gridColor != gridColor ||
      old.avgColor != avgColor;
}

class _OrderVolumeLabels extends StatelessWidget {
  const _OrderVolumeLabels({required this.points});

  final List<OrderVolumePoint> points;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final maxLabels = points.length <= 8 ? points.length : 8;
    final stride = (points.length / maxLabels).ceil().clamp(1, 64);
    final labels = <String>[];
    for (var i = 0; i < points.length; i += stride) {
      labels.add(points[i].shortLabel);
    }
    if (labels.isNotEmpty && labels.last != points.last.shortLabel) {
      labels[labels.length - 1] = points.last.shortLabel;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels
          .map(
            (label) => Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _OrderStat extends StatelessWidget {
  const _OrderStat({
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

class _OrderVolumeSkeleton extends StatelessWidget {
  const _OrderVolumeSkeleton();

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
