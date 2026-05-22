import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/replenishment_candidate.dart';

class ReplenishmentCandidatesPanel extends StatelessWidget {
  const ReplenishmentCandidatesPanel({
    super.key,
    required this.summary,
    this.isLoading = false,
    this.onCandidateTap,
  });

  final ReplenishmentCandidateSummary summary;
  final bool isLoading;
  final void Function(ReplenishmentCandidate candidate)? onCandidateTap;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _ReplenishmentSkeleton();
    }
    if (summary.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(context.tr('replenishmentEmpty')),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.tr('replenishmentDataTitle'),
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
              icon: Icons.priority_high_rounded,
              color: AppColors.warningDark,
              label: context.tr('replenishmentUrgentChip'),
              count: summary.urgent,
              note: context.tr(
                'replenishmentUrgentNote',
                <String, Object>{'n': summary.pickThreshold},
              ),
            ),
            _SummaryChip(
              icon: Icons.history_rounded,
              color: AppColors.brandOrange,
              label: context.tr('replenishmentOverdueChip'),
              count: summary.overdue,
              note: context.tr(
                'replenishmentOverdueNote',
                <String, Object>{'n': summary.overdueDays},
              ),
            ),
            _SummaryChip(
              icon: Icons.schedule_rounded,
              color: AppColors.brandBlue,
              label: context.tr('replenishmentMediumChip'),
              count: summary.medium,
              note: context.tr(
                'replenishmentMediumNote',
                <String, Object>{
                  'min': summary.mediumPickThreshold,
                  'max': summary.pickThreshold,
                },
              ),
            ),
          ],
        ),
        if (summary.urgentPlaces.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('replenishmentUrgentTitle'),
            subtitle: context.tr('replenishmentUrgentSubtitle'),
            color: AppColors.warningDark,
            candidates: summary.urgentPlaces,
            onTap: onCandidateTap,
          ),
        ],
        if (summary.overduePlaces.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('replenishmentOverdueTitle'),
            subtitle: context.tr('replenishmentOverdueSubtitle'),
            color: AppColors.brandOrange,
            candidates: summary.overduePlaces,
            onTap: onCandidateTap,
            showDays: true,
          ),
        ],
        if (summary.mediumPlaces.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('replenishmentMediumTitle'),
            subtitle: context.tr('replenishmentMediumSubtitle'),
            color: AppColors.brandBlue,
            candidates: summary.mediumPlaces,
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
    this.showDays = false,
  });

  final String title;
  final String subtitle;
  final Color color;
  final List<ReplenishmentCandidate> candidates;
  final void Function(ReplenishmentCandidate)? onTap;
  final bool showDays;

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
                  showDays: showDays,
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
    required this.showDays,
  });

  final ReplenishmentCandidate candidate;
  final Color color;
  final VoidCallback? onTap;
  final bool showDays;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
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
            constraints: const BoxConstraints(maxWidth: 300),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
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
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '${candidate.picks} ${context.tr('relocationPicksUnit')}',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (showDays && candidate.daysEmpty > 0) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          context.tr(
                            'replenishmentDaysEmpty',
                            <String, Object>{'n': candidate.daysEmpty},
                          ),
                          style: textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplenishmentSkeleton extends StatelessWidget {
  const _ReplenishmentSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: List<Widget>.generate(
        3,
        (index) => Container(
          width: 200,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
