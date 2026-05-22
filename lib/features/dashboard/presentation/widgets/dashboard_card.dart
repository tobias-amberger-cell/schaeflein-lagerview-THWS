import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.badgeLabel,
    this.badgeIcon,
    this.badgeBackgroundColor,
    this.badgeForegroundColor,
    this.badgeOutlined = false,
    this.details = const <String>[],
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String? badgeLabel;
  final IconData? badgeIcon;
  final Color? badgeBackgroundColor;
  final Color? badgeForegroundColor;
  final bool badgeOutlined;
  final List<String> details;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < 400;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      elevation: 0,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.surfaceContainerLowest,
                colorScheme.surface,
              ],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 150),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              iconColor.withValues(alpha: 0.22),
                              iconColor.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: iconColor.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(icon, color: iconColor, size: 18),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 0.14,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (badgeLabel != null) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 104),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: badgeBackgroundColor ??
                                  colorScheme.secondaryContainer.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                              border: badgeOutlined
                                  ? Border.all(
                                      color: badgeForegroundColor?.withValues(alpha: 0.34) ??
                                          colorScheme.outlineVariant,
                                    )
                                  : null,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: 3,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (badgeIcon != null) ...<Widget>[
                                    Icon(
                                      badgeIcon,
                                      size: 12,
                                      color: badgeForegroundColor ??
                                          colorScheme.onSecondaryContainer,
                                    ),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    badgeLabel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: badgeForegroundColor ??
                                          colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (compact ? textTheme.titleMedium : textTheme.titleLarge)
                            ?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.24,
                          height: 1.06,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                      if (details.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: details
                              .where((detail) => detail.trim().isNotEmpty)
                              .take(3)
                              .map(
                                (detail) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest.withValues(
                                      alpha: 0.56,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant.withValues(alpha: 0.33),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      detail,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
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
