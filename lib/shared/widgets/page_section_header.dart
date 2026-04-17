import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class PageSectionHeader extends StatelessWidget {
  const PageSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.badges,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget>? badges;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...<Widget>[
          Text(
            eyebrow!.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.25,
          ),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
        ],
        if (badges != null && badges!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: badges!,
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTrailing = trailing != null && constraints.maxWidth < 760;
        final headerContent = stackTrailing
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  titleBlock,
                  const SizedBox(height: AppSpacing.sm),
                  trailing!,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: titleBlock),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    trailing!,
                  ],
                ],
              );

        if (!kIsWeb) {
          return headerContent;
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.surfaceContainerLowest,
                colorScheme.surface,
                colorScheme.surfaceContainerLow,
              ],
            ),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: headerContent,
          ),
        );
      },
    );
  }
}
