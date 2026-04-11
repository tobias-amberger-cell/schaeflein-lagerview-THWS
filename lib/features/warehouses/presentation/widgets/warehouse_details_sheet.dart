import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/abc_analysis_bar.dart';
import 'warehouse_card.dart';

class WarehouseDetailsSheet extends StatelessWidget {
  const WarehouseDetailsSheet({
    super.key,
    required this.warehouse,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onOpenViewer,
  });

  final Warehouse warehouse;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenViewer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    warehouse.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip:
                      isFavorite ? 'Aus Favoriten entfernen' : 'Als Favorit markieren',
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border_rounded,
                    color: isFavorite ? Colors.amber.shade700 : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(warehouse.location)),
                StatusChip(status: warehouse.status),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                _MiniInfo(
                  icon: Icons.grid_4x4_outlined,
                  label: 'Zonen',
                  value: '${warehouse.zoneCount}',
                ),
                const SizedBox(width: AppSpacing.sm),
                _MiniInfo(
                  icon: Icons.badge_outlined,
                  label: 'ID',
                  value: warehouse.id,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _KpiPanel(warehouse: warehouse),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ABC Analyse',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Artikelklassifikation pro Lager',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AbcAnalysisBar(
                      aCount: warehouse.abcAnalysis.aCount,
                      bCount: warehouse.abcAnalysis.bCount,
                      cCount: warehouse.abcAnalysis.cCount,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              warehouse.description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Schlie\u00DFen'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onOpenViewer,
                    icon: const Icon(Icons.view_in_ar_outlined),
                    label: const Text('3D Ansicht \u00F6ffnen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiPanel extends StatelessWidget {
  const _KpiPanel({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Lagerkapazit\u00E4t',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${warehouse.occupiedStorageSlots} von ${warehouse.totalStorageSlots} Pl\u00E4tzen belegt',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: warehouse.utilizationRatio,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _KpiChip(label: 'Auslastung', value: '${warehouse.utilizationPercent}%'),
                _KpiChip(label: 'Frei', value: '${warehouse.freeStorageSlots}'),
                _KpiChip(label: 'Artikel', value: '${warehouse.articleCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
            Text(
              value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
