import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/warehouse.dart';

class AbcAdjustmentPanel extends StatelessWidget {
  const AbcAdjustmentPanel({
    super.key,
    required this.summaries,
    this.promotePickThreshold = 35,
    this.demotePickThreshold = 8,
    this.demoteIdleDaysThreshold = 90,
  });

  final List<WarehouseAbcArticleSummary> summaries;
  final int promotePickThreshold;
  final int demotePickThreshold;
  final int demoteIdleDaysThreshold;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(context.tr('abcAdjustEmpty')),
      );
    }

    final promote = summaries
        .where(
          (entry) =>
              entry.abcClass.trim().toUpperCase() == 'C' &&
              entry.movements30d >= promotePickThreshold,
        )
        .toList(growable: false);
    final demote = summaries
        .where(
          (entry) =>
              entry.abcClass.trim().toUpperCase() == 'A' &&
              (entry.movements30d <= demotePickThreshold ||
                  entry.maxIdleDays >= demoteIdleDaysThreshold),
        )
        .toList(growable: false);
    final review = summaries
        .where(
          (entry) =>
              entry.abcClass.trim().toUpperCase() == 'B' &&
              (entry.movements30d >= promotePickThreshold ||
                  entry.maxIdleDays >= demoteIdleDaysThreshold),
        )
        .toList(growable: false);

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.tr('abcAdjustDataTitle'),
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
              icon: Icons.trending_up_rounded,
              color: AppColors.brandBlue,
              label: context.tr('abcAdjustPromoteChip'),
              count: promote.length,
              note: context.tr(
                'abcAdjustPromoteNote',
                <String, Object>{'n': promotePickThreshold},
              ),
            ),
            _SummaryChip(
              icon: Icons.trending_down_rounded,
              color: AppColors.warningDark,
              label: context.tr('abcAdjustDemoteChip'),
              count: demote.length,
              note: context.tr(
                'abcAdjustDemoteNote',
                <String, Object>{
                  'picks': demotePickThreshold,
                  'days': demoteIdleDaysThreshold,
                },
              ),
            ),
            _SummaryChip(
              icon: Icons.rule_rounded,
              color: AppColors.brandOrange,
              label: context.tr('abcAdjustReviewChip'),
              count: review.length,
              note: context.tr('abcAdjustReviewNote'),
            ),
          ],
        ),
        if (promote.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('abcAdjustPromoteTitle'),
            subtitle: context.tr('abcAdjustPromoteSubtitle'),
            color: AppColors.brandBlue,
            candidates: promote,
          ),
        ],
        if (demote.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('abcAdjustDemoteTitle'),
            subtitle: context.tr('abcAdjustDemoteSubtitle'),
            color: AppColors.warningDark,
            candidates: demote,
          ),
        ],
        if (review.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('abcAdjustReviewTitle'),
            subtitle: context.tr('abcAdjustReviewSubtitle'),
            color: AppColors.brandOrange,
            candidates: review,
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
      constraints: const BoxConstraints(maxWidth: 260),
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
  });

  final String title;
  final String subtitle;
  final Color color;
  final List<WarehouseAbcArticleSummary> candidates;

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
  });

  final WarehouseAbcArticleSummary candidate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Ink(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                candidate.articleId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr(
                  'abcAdjustMetrics',
                  <String, Object>{
                    'abc': candidate.abcClass.trim().toUpperCase(),
                    'moves': candidate.movements30d,
                    'slots': candidate.slotCount,
                    'days': candidate.maxIdleDays,
                  },
                ),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
