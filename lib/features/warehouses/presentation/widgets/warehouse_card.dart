import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/warehouse.dart';

class WarehouseCard extends StatelessWidget {
  const WarehouseCard({
    super.key,
    required this.warehouse,
    required this.isSelected,
    required this.isFavorite,
    required this.onTap,
    required this.onSelect,
    required this.onOpenViewer,
    required this.onToggleFavorite,
  });

  final Warehouse warehouse;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final VoidCallback onOpenViewer;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final utilizationRatio = warehouse.totalStorageSlots == 0
        ? 0.0
        : warehouse.occupiedStorageSlots / warehouse.totalStorageSlots;
    final statusColor = switch (warehouse.status) {
      WarehouseStatus.online => Colors.green.shade600,
      WarehouseStatus.limited => Colors.orange.shade700,
      WarehouseStatus.maintenance => Colors.red.shade700,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.surfaceContainerLowest,
                colorScheme.surfaceContainerLow,
              ],
            ),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
              width: isSelected ? 1.6 : 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: isSelected ? 0.12 : 0.07),
                blurRadius: isSelected ? 22 : 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.apartment_rounded,
                              size: 18,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                warehouse.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                warehouse.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            if (isSelected)
                              _StateBadge(
                                label: 'Aktiv',
                                icon: Icons.check_circle_outline,
                                color: colorScheme.primary,
                              )
                            else
                              StatusChip(status: warehouse.status),
                            const SizedBox(height: 4),
                            IconButton(
                              tooltip: isFavorite
                                  ? context.tr('removeFavorite')
                                  : context.tr('markFavorite'),
                              onPressed: onToggleFavorite,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border_rounded,
                                color: isFavorite ? Colors.amber.shade700 : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        _MetaPill(
                          icon: Icons.grid_view_rounded,
                          label: '${warehouse.zoneCount} ${context.tr('zones')}',
                        ),
                        _MetaPill(
                          icon: Icons.layers_outlined,
                          label:
                              '${context.tr('kpiTotalSlots')}: ${warehouse.totalStorageSlots}',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: <Widget>[
                        Text(
                          '${warehouse.utilizationPercent}%',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: utilizationRatio.clamp(0, 1).toDouble(),
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        _StatChip(
                          label: '${context.tr('kpiTotalSlots')}: '
                              '${warehouse.occupiedStorageSlots}/${warehouse.totalStorageSlots}',
                        ),
                        _StatChip(
                          label: '${context.tr('kpiArticles')}: ${warehouse.articleCount}',
                        ),
                        _StatChip(
                          label: 'Pick/h: ${warehouse.pickRatePerHour}',
                        ),
                      ],
                    ),
                    if (!isCompact) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        warehouse.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.end,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: onSelect,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                          ),
                          icon: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                          ),
                          label: Text(isSelected ? 'Aktiv' : 'Auswählen'),
                        ),
                        FilledButton.icon(
                          onPressed: onOpenViewer,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                          ),
                          icon: const Icon(Icons.view_in_ar_outlined),
                          label: Text(context.tr('open3d')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final WarehouseStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      WarehouseStatus.online => Colors.green,
      WarehouseStatus.limited => Colors.orange,
      WarehouseStatus.maintenance => Colors.redAccent,
    };

    return Chip(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      label: Text(context.tr(status.labelKey)),
      avatar: Icon(Icons.circle, size: 10, color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
