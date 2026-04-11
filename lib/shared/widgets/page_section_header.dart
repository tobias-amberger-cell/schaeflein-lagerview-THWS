import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class PageSectionHeader extends StatelessWidget {
  const PageSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTrailing = trailing != null && constraints.maxWidth < 760;
        if (stackTrailing) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              titleBlock,
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: titleBlock),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        );
      },
    );
  }
}
