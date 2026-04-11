import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class AbcAnalysisBar extends StatelessWidget {
  const AbcAnalysisBar({
    super.key,
    required this.aCount,
    required this.bCount,
    required this.cCount,
    this.height = 12,
    this.showLegend = true,
  });

  final int aCount;
  final int bCount;
  final int cCount;
  final double height;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final total = aCount + bCount + cCount;
    final aFlex = aCount <= 0 ? 1 : aCount;
    final bFlex = bCount <= 0 ? 1 : bCount;
    final cFlex = cCount <= 0 ? 1 : cCount;
    final mutedColor = Theme.of(context).colorScheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: height,
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: aFlex,
                  child: ColoredBox(
                    color: total == 0
                        ? mutedColor
                        : const Color(0xFF1E8E3E),
                  ),
                ),
                Expanded(
                  flex: bFlex,
                  child: ColoredBox(
                    color: total == 0
                        ? mutedColor
                        : const Color(0xFFF29900),
                  ),
                ),
                Expanded(
                  flex: cFlex,
                  child: ColoredBox(
                    color: total == 0
                        ? mutedColor
                        : const Color(0xFF5F6368),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showLegend) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _LegendItem(
                label: 'A',
                value: aCount,
                color: const Color(0xFF1E8E3E),
              ),
              _LegendItem(
                label: 'B',
                value: bCount,
                color: const Color(0xFFF29900),
              ),
              _LegendItem(
                label: 'C',
                value: cCount,
                color: const Color(0xFF5F6368),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
