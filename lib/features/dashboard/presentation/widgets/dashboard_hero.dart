import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/warehouse.dart';

class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.warehouse,
    required this.utilization,
    required this.availableCount,
    required this.unreadNotifications,
    required this.criticalTickets,
    required this.topRiskZone,
    required this.topRiskScore,
    required this.lastSyncLabel,
    required this.isOffline,
    required this.isSyncing,
    required this.onSync,
    required this.onOpenWarehouseList,
    required this.isCompact,
  });

  final Warehouse? warehouse;
  final int utilization;
  final int availableCount;
  final int unreadNotifications;
  final int criticalTickets;
  final String? topRiskZone;
  final double topRiskScore;
  final String lastSyncLabel;
  final bool isOffline;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onOpenWarehouseList;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final syncColor = isOffline ? AppColors.error : AppColors.success;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primaryContainer.withValues(alpha: 0.55),
            colorScheme.surfaceContainerLowest,
            colorScheme.surface,
          ],
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Lagerleitstand',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Fokuslager, Heatmap und operative Leistungsdaten.',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              warehouse?.name ?? 'Kein Fokuslager gewählt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isCompact) _buildActions(),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _HeroChip(
                  icon: Icons.warehouse_outlined,
                  label: 'Standorte',
                  value: '$availableCount',
                  color: colorScheme.primary,
                ),
                _HeroChip(
                  icon: Icons.speed_outlined,
                  label: 'Auslastung',
                  value: '$utilization%',
                  color: AppColors.brandTeal,
                ),
                if (unreadNotifications > 0)
                  _HeroChip(
                    icon: Icons.notifications_active_outlined,
                    label: 'Meldungen',
                    value: unreadNotifications.toString(),
                    color: AppColors.error,
                  ),
                if (criticalTickets > 0)
                  _HeroChip(
                    icon: Icons.report_outlined,
                    label: 'Kritische Vorgänge',
                    value: criticalTickets.toString(),
                    color: AppColors.brandOrange,
                  ),
                if (topRiskZone != null)
                  _HeroChip(
                    icon: Icons.local_fire_department_outlined,
                    label: 'Risikozone',
                    value: '$topRiskZone ${(topRiskScore * 100).round()}%',
                    color: AppColors.error,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: syncColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: syncColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    isOffline
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                    size: 16,
                    color: syncColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Datenstand: $lastSyncLabel',
                    style:
                        Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: syncColor,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ],
              ),
            ),
            if (isCompact) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _buildActions(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        FilledButton.icon(
          onPressed: onOpenWarehouseList,
          icon: const Icon(Icons.warehouse_outlined, size: 18),
          label: const Text('Lagerliste'),
        ),
        OutlinedButton.icon(
          onPressed: isSyncing ? null : onSync,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(
            isSyncing ? 'Sync läuft...' : 'Daten aktualisieren',
          ),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
