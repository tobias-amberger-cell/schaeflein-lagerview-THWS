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
    // Farben/Typo aus dem Theme zentral ziehen, damit die Karte in allen Themes konsistent bleibt.
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Auslastungsquote fuer Progressbar berechnen und Division durch 0 vermeiden.
    final utilizationRatio = warehouse.totalStorageSlots == 0
        ? 0.0
        : warehouse.occupiedStorageSlots / warehouse.totalStorageSlots;
    // Status wird in Farbe + Text überführt, damit Information schnell erfassbar ist.
    final statusColor = switch (warehouse.status) {
      WarehouseStatus.online => Colors.green.shade600,
      WarehouseStatus.limited => Colors.orange.shade700,
      WarehouseStatus.maintenance => Colors.red.shade700,
    };
    final statusLabel = context.tr(warehouse.status.labelKey);
    final statusTint = statusColor.withValues(alpha: 0.1);

    return LayoutBuilder(
      builder: (context, constraints) {
        // In sehr schmalen Breiten reduzieren wir optionale Textelemente.
        final isCompact = constraints.maxWidth < 420;
        final isShort = constraints.maxHeight.isFinite && constraints.maxHeight < 420;
        final showDescription = !isCompact && !isShort;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                statusTint,
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
              // Ein Tap auf die Karte bedeutet: Lager selektieren.
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: EdgeInsets.all(isShort ? AppSpacing.sm : AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                    Row(
                      // Kopfbereich: Status, Name, Ort und Favorit.
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  _StateBadge(
                                    label: statusLabel,
                                    icon: Icons.circle,
                                    color: statusColor,
                                  ),
                                  if (isSelected) ...<Widget>[
                                    const SizedBox(width: AppSpacing.xs),
                                    _StateBadge(
                                      label: 'Aktiv',
                                      icon: Icons.check_circle_outline,
                                      color: colorScheme.primary,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                warehouse.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      warehouse.location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        IconButton.filledTonal(
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
                    SizedBox(height: isShort ? AppSpacing.xs : AppSpacing.sm),
                    Wrap(
                      // Kern-Metadaten mit schneller visueller Erkennung.
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
                    SizedBox(height: isShort ? AppSpacing.xs : AppSpacing.sm),
                    Text(
                      'Auslastung',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      // Prozent + absolute Belegung + visuelle Progressbar.
                      children: <Widget>[
                        Text(
                          '${warehouse.utilizationPercent}%',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${warehouse.occupiedStorageSlots}/${warehouse.totalStorageSlots}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
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
                    SizedBox(height: isShort ? AppSpacing.xs : AppSpacing.sm),
                    if (!isShort)
                      Wrap(
                        // Weitere KPI-Schnipsel kompakt untereinander.
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
                            label: 'Pick/h ca.: ${warehouse.pickRatePerHour}',
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: <Widget>[
                          _StatChip(
                            label:
                                '${context.tr('kpiArticles')}: ${warehouse.articleCount}',
                          ),
                          _StatChip(
                            label: 'Pick/h ca.: ${warehouse.pickRatePerHour}',
                          ),
                        ],
                      ),
                    if (showDescription) ...<Widget>[
                      // Beschreibung nur bei genug Platz zeigen.
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        warehouse.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ],
                    SizedBox(height: isShort ? AppSpacing.xs : AppSpacing.sm),
                    Wrap(
                      // CTA-Reihe: Auswahl und 3D-Viewer.
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
                          label: Text(isSelected ? 'Aktiv' : 'Auswaehlen'),
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
    // Status-Badge mit leichter Tönung zur schnellen Orientierung.
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
    // Kompakter Textchip für KPI-Werte.
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
    // Icon + Label Pill für Metadatenblöcke.
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
    // Legacy/Reusable Status-Chip (wird außerhalb der Karte ebenfalls genutzt).
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
