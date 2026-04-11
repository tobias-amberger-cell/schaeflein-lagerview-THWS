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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 240;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (badgeLabel != null) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 96),
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
                                vertical: 2,
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
                                  Flexible(
                                    child: Text(
                                      badgeLabel!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: badgeForegroundColor ??
                                            colorScheme.onSecondaryContainer,
                                      ),
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
                  const SizedBox(height: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (compact ? textTheme.titleMedium : textTheme.titleLarge)
                                  ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
