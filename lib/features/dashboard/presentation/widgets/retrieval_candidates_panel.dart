import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/warehouse.dart';

class RetrievalCandidatesPanel extends StatelessWidget {
  const RetrievalCandidatesPanel({
    super.key,
    required this.samples,
    this.onCandidateTap,
    this.idleDaysThreshold = 90,
    this.staleDaysThreshold = 120,
    this.criticalDaysThreshold = 180,
  });

  final List<WarehouseStorageLocation> samples;
  final void Function(WarehouseStorageLocation candidate)? onCandidateTap;
  final int idleDaysThreshold;
  final int staleDaysThreshold;
  final int criticalDaysThreshold;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(context.tr('retrievalEmpty')),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final critical = samples
        .where((sample) => (sample.daysSinceMovement ?? 0) >= criticalDaysThreshold)
        .toList(growable: false);
    final stale = samples
        .where((sample) {
          final days = sample.daysSinceMovement ?? 0;
          return days >= staleDaysThreshold && days < criticalDaysThreshold;
        })
        .toList(growable: false);
    final observe = samples
        .where((sample) {
          final days = sample.daysSinceMovement ?? 0;
          return days >= idleDaysThreshold && days < staleDaysThreshold;
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.tr('retrievalDataTitle'),
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            _SummaryChip(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warningDark,
              label: context.tr('retrievalCriticalChip'),
              count: critical.length,
              note: context.tr(
                'retrievalCriticalNote',
                <String, Object>{'n': criticalDaysThreshold},
              ),
            ),
            _SummaryChip(
              icon: Icons.inventory_2_outlined,
              color: AppColors.brandOrange,
              label: context.tr('retrievalStaleChip'),
              count: stale.length,
              note: context.tr(
                'retrievalStaleNote',
                <String, Object>{'n': staleDaysThreshold},
              ),
            ),
            _SummaryChip(
              icon: Icons.schedule_rounded,
              color: AppColors.brandBlue,
              label: context.tr('retrievalObserveChip'),
              count: observe.length,
              note: context.tr(
                'retrievalObserveNote',
                <String, Object>{'n': idleDaysThreshold},
              ),
            ),
          ],
        ),
        if (critical.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('retrievalCriticalTitle'),
            subtitle: context.tr('retrievalCriticalSubtitle'),
            color: AppColors.warningDark,
            candidates: critical,
            onTap: onCandidateTap,
          ),
        ],
        if (stale.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('retrievalStaleTitle'),
            subtitle: context.tr('retrievalStaleSubtitle'),
            color: AppColors.brandOrange,
            candidates: stale,
            onTap: onCandidateTap,
          ),
        ],
        if (observe.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('retrievalObserveTitle'),
            subtitle: context.tr('retrievalObserveSubtitle'),
            color: AppColors.brandBlue,
            candidates: observe,
            onTap: onCandidateTap,
          ),
        ],
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.note,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final String note;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '$count $label',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    note,
                    style: textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateGroup extends StatelessWidget {
  const _CandidateGroup({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.candidates,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final List<WarehouseStorageLocation> candidates;
  final void Function(WarehouseStorageLocation)? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final visible = candidates.take(6).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: visible
              .map(
                (candidate) => _CandidateTile(
                  candidate: candidate,
                  color: color,
                  onTap: onTap == null ? null : () => onTap!(candidate),
                ),
              )
              .toList(growable: false),
        ),
        if (candidates.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              context.tr(
                'relocationMoreCount',
                <String, Object>{'n': candidates.length - visible.length},
              ),
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.color,
    required this.onTap,
  });

  final WarehouseStorageLocation candidate;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final idleDays = candidate.daysSinceMovement ?? 0;
    final movements = candidate.movements30d ?? 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      candidate.displayCode,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      '$idleDays T · $movements P',
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onTap != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
