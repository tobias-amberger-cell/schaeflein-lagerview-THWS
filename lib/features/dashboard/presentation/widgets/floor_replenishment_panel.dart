import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/replenishment_candidate.dart';

class FloorReplenishmentPanel extends StatelessWidget {
  const FloorReplenishmentPanel({
    super.key,
    required this.urgent,
    required this.overdue,
    required this.medium,
    required this.floorLevelThreshold,
    this.isLoading = false,
    this.onCandidateTap,
  });

  final List<ReplenishmentCandidate> urgent;
  final List<ReplenishmentCandidate> overdue;
  final List<ReplenishmentCandidate> medium;
  final int floorLevelThreshold;
  final bool isLoading;
  final void Function(ReplenishmentCandidate candidate)? onCandidateTap;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _FloorReplenishmentSkeleton();
    }
    if (urgent.isEmpty && overdue.isEmpty && medium.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(context.tr('floorReplenishmentEmpty')),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.tr(
            'floorReplenishmentDataTitle',
            <String, Object>{'n': floorLevelThreshold},
          ),
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
              label: context.tr('floorReplenishmentUrgentChip'),
              count: urgent.length,
            ),
            _SummaryChip(
              icon: Icons.history_rounded,
              color: AppColors.brandOrange,
              label: context.tr('floorReplenishmentOverdueChip'),
              count: overdue.length,
            ),
            _SummaryChip(
              icon: Icons.schedule_rounded,
              color: AppColors.brandBlue,
              label: context.tr('floorReplenishmentMediumChip'),
              count: medium.length,
            ),
          ],
        ),
        if (urgent.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('floorReplenishmentUrgentTitle'),
            subtitle: context.tr('floorReplenishmentUrgentSubtitle'),
            color: AppColors.warningDark,
            candidates: urgent,
            onTap: onCandidateTap,
          ),
        ],
        if (overdue.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('floorReplenishmentOverdueTitle'),
            subtitle: context.tr('floorReplenishmentOverdueSubtitle'),
            color: AppColors.brandOrange,
            candidates: overdue,
            onTap: onCandidateTap,
            showDays: true,
          ),
        ],
        if (medium.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('floorReplenishmentMediumTitle'),
            subtitle: context.tr('floorReplenishmentMediumSubtitle'),
            color: AppColors.brandBlue,
            candidates: medium,
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
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
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
          Text(
            '$count $label',
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
  final void Function(ReplenishmentCandidate candidate)? onTap;
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
    required this.showDays,
    required this.onTap,
  });

  final ReplenishmentCandidate candidate;
  final Color color;
  final bool showDays;
  final VoidCallback? onTap;

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
                      '${candidate.picks} ${context.tr('relocationPicksUnit')}',
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (showDays && candidate.daysEmpty > 0) ...<Widget>[
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        context.tr(
                          'replenishmentDaysEmpty',
                          <String, Object>{'n': candidate.daysEmpty},
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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

class _FloorReplenishmentSkeleton extends StatelessWidget {
  const _FloorReplenishmentSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: List<Widget>.generate(
        3,
        (index) => Container(
          width: 220,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
