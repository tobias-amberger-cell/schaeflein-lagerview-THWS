import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/pick_activity_heatmap.dart';

class PickActivityHeatmapCard extends StatelessWidget {
  const PickActivityHeatmapCard({
    super.key,
    required this.heatmap,
    this.isLoading = false,
  });

  final PickActivityHeatmap heatmap;
  final bool isLoading;

  static const List<String> _weekdayKeys = <String>[
    'weekdayShortSun',
    'weekdayShortMon',
    'weekdayShortTue',
    'weekdayShortWed',
    'weekdayShortThu',
    'weekdayShortFri',
    'weekdayShortSat',
  ];

  static String weekdayLabel(BuildContext context, int weekdayIndex) {
    final safeIndex = weekdayIndex.clamp(0, 6);
    return context.tr(_weekdayKeys[safeIndex]);
  }

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
                Icon(Icons.grid_on_outlined, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.tr('pickActivityTitle'),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _subtitle(context),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (isLoading)
              const _HeatmapSkeleton()
            else if (heatmap.isEmpty)
              Text(
                context.tr('pickActivityEmpty'),
                style: textTheme.bodySmall,
              )
            else ...<Widget>[
              _HeatmapStats(heatmap: heatmap),
              const SizedBox(height: AppSpacing.md),
              _HeatmapGrid(heatmap: heatmap),
              const SizedBox(height: AppSpacing.sm),
              _Legend(maxPicks: heatmap.maxPicks),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context) {
    if (heatmap.isEmpty || heatmap.minDate == null || heatmap.maxDate == null) {
      return context.tr('pickActivitySubtitle');
    }
    final from = _formatDate(heatmap.minDate!);
    final to = _formatDate(heatmap.maxDate!);
    return context.tr('pickActivityRange', <String, Object>{
      'from': from,
      'to': to,
    });
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}

/// Heatmap-Farbskala (kuehl → warm, Streamlit RdYlGn_r-Stil).
const List<Color> _heatStops = <Color>[
  Color(0xFF1E7F4F), // satt-grün (kühl, niedrig)
  Color(0xFF7FC15F),
  Color(0xFFFFD24A),
  Color(0xFFFF8A3D),
  Color(0xFFD93828), // tief-rot (sehr heiß)
];

Color _heatColor(double ratio) {
  if (ratio <= 0) return const Color(0x00000000);
  final t = ratio.clamp(0.0, 1.0).toDouble();
  if (t >= 1) return _heatStops.last;
  final scaled = t * (_heatStops.length - 1);
  final lower = scaled.floor();
  final upper = (lower + 1).clamp(0, _heatStops.length - 1);
  final localT = scaled - lower;
  return Color.lerp(_heatStops[lower], _heatStops[upper], localT)!;
}

class _HeatmapStats extends StatelessWidget {
  const _HeatmapStats({required this.heatmap});

  final PickActivityHeatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    var totalPicks = 0;
    var activeCells = 0;
    var peakPicks = 0;
    int peakWeekday = 0;
    int peakHour = 0;
    for (final cell in heatmap.cells) {
      if (cell.picks <= 0) continue;
      totalPicks += cell.picks;
      activeCells += 1;
      if (cell.picks > peakPicks) {
        peakPicks = cell.picks;
        peakWeekday = cell.weekday;
        peakHour = cell.hour;
      }
    }
    final avgActive = activeCells > 0 ? totalPicks / activeCells : 0;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _StatChip(
          label: context.tr('pickActivityTotalPicks'),
          value: _formatThousands(totalPicks),
        ),
        _StatChip(
          label: context.tr('pickActivityPeakLabel'),
          value: '$peakPicks',
          hint: '${PickActivityHeatmapCard.weekdayLabel(context, peakWeekday)} ${peakHour.toString().padLeft(2, '0')}:00',
          valueColor: _heatStops.last,
        ),
        _StatChip(
          label: context.tr('pickActivityAvgActive'),
          value: avgActive.toStringAsFixed(0),
        ),
        _StatChip(
          label: context.tr('pickActivityActiveCells'),
          value: '$activeCells / 168',
          hint: textTheme.labelSmall != null
              ? '${((activeCells / 168) * 100).round()} %'
              : null,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.hint,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({required this.heatmap});

  final PickActivityHeatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final maxPicks = heatmap.maxPicks <= 0 ? 1 : heatmap.maxPicks;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Wochentag-Reihenfolge: Mo bis So (UI). Sonntag ist im Model index 0.
    const weekdayOrder = <int>[1, 2, 3, 4, 5, 6, 0];

    // Tagessumme + max je Wochentag fuer die rechte Spalte.
    final dayTotals = <int, int>{};
    var maxDayTotal = 0;
    for (final w in weekdayOrder) {
      var sum = 0;
      for (var h = 0; h < 24; h++) {
        sum += heatmap.picksAt(w, h);
      }
      dayTotals[w] = sum;
      if (sum > maxDayTotal) maxDayTotal = sum;
    }

    // Peak (zur Hervorhebung).
    var peakValue = 0;
    int? peakWeekday;
    int? peakHour;
    for (final cell in heatmap.cells) {
      if (cell.picks > peakValue) {
        peakValue = cell.picks;
        peakWeekday = cell.weekday;
        peakHour = cell.hour;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelColumnWidth = 32.0;
        const dayBarWidth = 56.0;
        const cellGap = 2.0;
        final available =
            (constraints.maxWidth - labelColumnWidth - dayBarWidth - cellGap)
                .clamp(0.0, double.infinity);
        final cellWidth =
            ((available - 23 * cellGap) / 24).clamp(8.0, 32.0).toDouble();
        final cellHeight = cellWidth * 0.9;

        Widget hourHeader() {
          return Row(
            children: <Widget>[
              const SizedBox(width: labelColumnWidth),
              for (var h = 0; h < 24; h++) ...<Widget>[
                SizedBox(
                  width: cellWidth,
                  child: Center(
                    child: Text(
                      h % 3 == 0 ? h.toString().padLeft(2, '0') : '',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: h % 3 == 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                if (h < 23) const SizedBox(width: cellGap),
              ],
              const SizedBox(width: cellGap),
              SizedBox(
                width: dayBarWidth,
                child: Text(
                  context.tr('pickActivityDaySumHeader'),
                  textAlign: TextAlign.end,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        }

        Widget dayRow(int weekday) {
          final dayTotal = dayTotals[weekday] ?? 0;
          final dayRatio = maxDayTotal > 0 ? dayTotal / maxDayTotal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: cellGap),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: labelColumnWidth,
                  child: Text(
                    PickActivityHeatmapCard.weekdayLabel(context, weekday),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var hour = 0; hour < 24; hour++) ...<Widget>[
                  _HeatmapCell(
                    width: cellWidth,
                    height: cellHeight,
                    picks: heatmap.picksAt(weekday, hour),
                    maxPicks: maxPicks,
                    weekday: weekday,
                    hour: hour,
                    isNight: hour < 6 || hour >= 22,
                    isPeak: weekday == peakWeekday && hour == peakHour,
                  ),
                  if (hour < 23) const SizedBox(width: cellGap),
                ],
                const SizedBox(width: cellGap),
                _DaySumBar(
                  width: dayBarWidth,
                  height: cellHeight,
                  total: dayTotal,
                  ratio: dayRatio,
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            hourHeader(),
            const SizedBox(height: 4),
            for (final w in weekdayOrder) dayRow(w),
          ],
        );
      },
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.width,
    required this.height,
    required this.picks,
    required this.maxPicks,
    required this.weekday,
    required this.hour,
    required this.isNight,
    required this.isPeak,
  });

  final double width;
  final double height;
  final int picks;
  final int maxPicks;
  final int weekday;
  final int hour;
  final bool isNight;
  final bool isPeak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ratio = picks <= 0 ? 0.0 : (picks / maxPicks).clamp(0.0, 1.0).toDouble();
    final bg = picks <= 0
        ? colorScheme.surfaceContainerHighest.withValues(
            alpha: isNight ? 0.6 : 1.0,
          )
        : _heatColor(ratio);
    return Tooltip(
      message: context.tr(
        'pickActivityTooltip',
        <String, Object>{
          'day': PickActivityHeatmapCard.weekdayLabel(context, weekday),
          'hour': hour.toString().padLeft(2, '0'),
          'picks': picks,
        },
      ),
      waitDuration: const Duration(milliseconds: 200),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: isPeak
              ? Border.all(color: Colors.white, width: 1.6)
              : null,
          boxShadow: isPeak
              ? <BoxShadow>[
                  BoxShadow(
                    color: _heatStops.last.withValues(alpha: 0.45),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _DaySumBar extends StatelessWidget {
  const _DaySumBar({
    required this.width,
    required this.height,
    required this.total,
    required this.ratio,
  });

  final double width;
  final double height;
  final int total;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final track = colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);
    final bar = colorScheme.primary;
    return SizedBox(
      width: width,
      height: height,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                Container(
                  height: height * 0.55,
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    height: height * 0.55,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          bar.withValues(alpha: 0.7),
                          bar,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 24,
            child: Text(
              total > 0 ? _formatThousands(total) : '–',
              textAlign: TextAlign.end,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.maxPicks});

  final int maxPicks;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Text(
          '0',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(colors: _heatStops),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          maxPicks > 0 ? '$maxPicks' : '–',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HeatmapSkeleton extends StatelessWidget {
  const _HeatmapSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: List<Widget>.generate(
        7,
        (row) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: List<Widget>.generate(
              24,
              (col) => Expanded(
                child: Container(
                  height: 14,
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatThousands(int value) {
  final str = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(str[i]);
  }
  return buffer.toString();
}
