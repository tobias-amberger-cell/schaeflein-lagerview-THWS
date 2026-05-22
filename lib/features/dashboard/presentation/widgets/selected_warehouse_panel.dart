import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/warehouse.dart';
import '../../../../models/warehouse_operations_profile.dart';
import 'dashboard_helpers.dart';

class SelectedWarehousePanel extends StatelessWidget {
  const SelectedWarehousePanel({
    super.key,
    required this.warehouse,
    required this.operationsProfile,
  });

  final Warehouse? warehouse;
  final WarehouseOperationsProfile? operationsProfile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (warehouse == null) {
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Kein Lager gewählt',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Wähle ein Lager aus der Liste, um Detailkennzahlen zu sehen.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => context.go('/warehouses'),
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                label: const Text('Zur Lagerliste'),
              ),
            ],
          ),
        ),
      );
    }

    final current = warehouse!;
    final utilization = current.utilizationPercent;
    final sColor = statusColor(current.status);
    final sLabel = statusLabel(current.status);

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
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: sColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: sColor.withValues(alpha: 0.4)),
                  ),
                  child:
                      Icon(Icons.warehouse_outlined, color: sColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        current.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        current.location,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: sColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                sLabel,
                style: textTheme.labelLarge?.copyWith(
                  color: sColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Kapazität',
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: utilization / 100,
                minHeight: 10,
                color: sColor,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${current.occupiedStorageSlots} von ${current.totalStorageSlots} Plätzen belegt',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                InlineKpi(
                  label: 'Zonen',
                  value: current.zoneCount.toString(),
                  color: AppColors.brandBlue,
                ),
                InlineKpi(
                  label: 'Artikel',
                  value: formatNumber(current.articleCount),
                  color: AppColors.brandTeal,
                ),
                InlineKpi(
                  label: 'Pick/Std',
                  value: current.pickRatePerHour.toString(),
                  color: AppColors.brandOrange,
                ),
              ],
            ),
            if (operationsProfile != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                'SLA',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: operationsProfile!.slaCurrentPercent / 100,
                  minHeight: 10,
                  color: AppColors.success,
                  backgroundColor:
                      colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${operationsProfile!.slaCurrentPercent}% Ziel ${operationsProfile!.slaTargetPercent}%',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Tor-Auslastung',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: operationsProfile!.dockUtilizationRatio,
                  minHeight: 10,
                  color: AppColors.brandSky,
                  backgroundColor:
                      colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${operationsProfile!.activeDocks} von ${operationsProfile!.dockCount} Docks aktiv',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Lagerplatz-Mix',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _SlotMixRow(
                label: 'Hochregal',
                value: operationsProfile!.highBaySlots,
                total: operationsProfile!.totalSlotMix,
                color: AppColors.brandBlue,
              ),
              const SizedBox(height: AppSpacing.xs),
              _SlotMixRow(
                label: 'Blocklager',
                value: operationsProfile!.blockStorageSlots,
                total: operationsProfile!.totalSlotMix,
                color: AppColors.brandTeal,
              ),
              const SizedBox(height: AppSpacing.xs),
              _SlotMixRow(
                label: 'Shuttle',
                value: operationsProfile!.shuttleSlots,
                total: operationsProfile!.totalSlotMix,
                color: AppColors.brandOrange,
              ),
              const SizedBox(height: AppSpacing.xs),
              _SlotMixRow(
                label: 'Bodenlager',
                value: operationsProfile!.floorStorageSlots,
                total: operationsProfile!.totalSlotMix,
                color: AppColors.brandPurple,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlotMixRow extends StatelessWidget {
  const _SlotMixRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : value / total;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              formatNumber(value),
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            color: color,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
