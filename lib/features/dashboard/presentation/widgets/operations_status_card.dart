import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/warehouse_operations_profile.dart';
import 'dashboard_helpers.dart';

class OperationsStatusCard extends StatelessWidget {
  const OperationsStatusCard({super.key, required this.profile});

  final WarehouseOperationsProfile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final totalZones = profile.totalZoneTypes;
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
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _StatusMetric(
                  label: 'Qualitätsholds',
                  value: profile.qualityHolds,
                  icon: Icons.verified_outlined,
                  color: AppColors.brandBlue,
                ),
                _StatusMetric(
                  label: 'Sicherheitsvorfälle',
                  value: profile.safetyIncidentsMonth,
                  icon: Icons.health_and_safety_outlined,
                  color: AppColors.error,
                ),
                _StatusMetric(
                  label: 'Blockierte Plätze',
                  value: profile.blockedSlots,
                  icon: Icons.block_outlined,
                  color: AppColors.brownDark,
                ),
                _StatusMetric(
                  label: 'Reserviert',
                  value: profile.reservedSlots,
                  icon: Icons.bookmark_added_outlined,
                  color: AppColors.brandIndigo,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Zonentypen',
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ZoneTypeBar(
              coldCount: profile.coldZoneCount,
              ambientCount: profile.ambientZoneCount,
              hazardousCount: profile.hazardousZoneCount,
              total: totalZones,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                InlineKpi(
                  label: 'Kühlzonen',
                  value: profile.coldZoneCount.toString(),
                  color: AppColors.brandSky,
                ),
                InlineKpi(
                  label: 'Ambient',
                  value: profile.ambientZoneCount.toString(),
                  color: AppColors.success,
                ),
                InlineKpi(
                  label: 'Gefahrgut',
                  value: profile.hazardousZoneCount.toString(),
                  color: AppColors.brandOrange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value.toString(),
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoneTypeBar extends StatelessWidget {
  const _ZoneTypeBar({
    required this.coldCount,
    required this.ambientCount,
    required this.hazardousCount,
    required this.total,
  });

  final int coldCount;
  final int ambientCount;
  final int hazardousCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final safeTotal = total == 0 ? 1 : total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: (coldCount / safeTotal * 100).round().clamp(1, 100),
            child: Container(height: 10, color: AppColors.brandSky),
          ),
          Expanded(
            flex: (ambientCount / safeTotal * 100).round().clamp(1, 100),
            child: Container(height: 10, color: AppColors.success),
          ),
          Expanded(
            flex: (hazardousCount / safeTotal * 100).round().clamp(1, 100),
            child: Container(height: 10, color: AppColors.brandOrange),
          ),
        ],
      ),
    );
  }
}
