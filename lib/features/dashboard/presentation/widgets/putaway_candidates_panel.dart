import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../models/warehouse.dart';

class PutawayCandidatesPanel extends StatelessWidget {
  const PutawayCandidatesPanel({
    super.key,
    required this.fastLaneSlots,
    required this.reserveSlots,
    required this.blockedSlots,
    required this.floorLevelThreshold,
    required this.reserveLevelThreshold,
    this.onCandidateTap,
  });

  final List<WarehouseStorageLocation> fastLaneSlots;
  final List<WarehouseStorageLocation> reserveSlots;
  final List<WarehouseStorageLocation> blockedSlots;
  final int floorLevelThreshold;
  final int reserveLevelThreshold;
  final void Function(WarehouseStorageLocation candidate)? onCandidateTap;

  @override
  Widget build(BuildContext context) {
    if (fastLaneSlots.isEmpty &&
        reserveSlots.isEmpty &&
        blockedSlots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(context.tr('putawayEmpty')),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.tr('putawayDataTitle'),
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
              icon: Icons.bolt_rounded,
              color: AppColors.brandBlue,
              label: context.tr('putawayFastLaneChip'),
              count: fastLaneSlots.length,
              note: context.tr(
                'putawayFastLaneNote',
                <String, Object>{'n': floorLevelThreshold},
              ),
            ),
            _SummaryChip(
              icon: Icons.layers_rounded,
              color: AppColors.brandOrange,
              label: context.tr('putawayReserveChip'),
              count: reserveSlots.length,
              note: context.tr(
                'putawayReserveNote',
                <String, Object>{'n': reserveLevelThreshold},
              ),
            ),
            _SummaryChip(
              icon: Icons.block_rounded,
              color: AppColors.warningDark,
              label: context.tr('putawayBlockedChip'),
              count: blockedSlots.length,
              note: context.tr('putawayBlockedNote'),
            ),
          ],
        ),
        if (fastLaneSlots.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('putawayFastLaneTitle'),
            subtitle: context.tr('putawayFastLaneSubtitle'),
            color: AppColors.brandBlue,
            candidates: fastLaneSlots,
            onTap: onCandidateTap,
          ),
        ],
        if (reserveSlots.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('putawayReserveTitle'),
            subtitle: context.tr('putawayReserveSubtitle'),
            color: AppColors.brandOrange,
            candidates: reserveSlots,
            onTap: onCandidateTap,
          ),
        ],
        if (blockedSlots.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _CandidateGroup(
            title: context.tr('putawayBlockedTitle'),
            subtitle: context.tr('putawayBlockedSubtitle'),
            color: AppColors.warningDark,
            candidates: blockedSlots,
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final List<WarehouseStorageLocation> candidates;
  final void Function(WarehouseStorageLocation candidate)? onTap;

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
                  Text(
                    context.tr(
                      'putawayTileMeta',
                      <String, Object>{
                        'abc': candidate.abcClass.trim().toUpperCase(),
                        'level': candidate.levelNumber,
                        'status': candidate.status.trim(),
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
        ),
      ),
    );
  }
}
