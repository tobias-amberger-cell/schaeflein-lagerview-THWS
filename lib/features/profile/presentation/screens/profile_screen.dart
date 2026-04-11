import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../shared/widgets/page_section_header.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;
    final selectedWarehouse = appState.selectedWarehouse;

    return ListView(
      children: <Widget>[
        PageSectionHeader(
          title: context.tr('profile'),
          subtitle: context.tr(
            'role',
            <String, Object>{'role': context.tr(appState.userRoleLabelKey)},
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _SectionHeader(
          title: 'Konto',
          subtitle: 'Benutzerprofil und Status',
        ),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.primaryContainer.withValues(alpha: 0.45),
                colorScheme.secondaryContainer.withValues(alpha: 0.18),
                colorScheme.surfaceContainerLowest,
              ],
            ),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: <Widget>[
                CircleAvatar(
                  radius: 36,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 42,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(appState.userName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  appState.userEmail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.tr(
                    'role',
                    <String, Object>{
                      'role': context.tr(appState.userRoleLabelKey),
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    _ProfileKpiChip(
                      icon: Icons.star_border_rounded,
                      label: context.tr('favorites'),
                      value: '${appState.favoriteWarehouseCount}',
                    ),
                    _ProfileKpiChip(
                      icon: Icons.notifications_none_rounded,
                      label: context.tr('notifications'),
                      value: '${appState.unreadNotificationCount}',
                    ),
                    _ProfileKpiChip(
                      icon: Icons.view_in_ar_outlined,
                      label: context.tr('viewer'),
                      value: appState.selectedWarehouse == null
                          ? context.tr('notActive')
                          : context.tr('ready'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _InfoCard(
          title: 'Aktives Lager',
          value: selectedWarehouse?.name ?? context.tr('none'),
          subtitle: selectedWarehouse?.location ?? context.tr('pleaseSelectWarehouse'),
          icon: Icons.warehouse_outlined,
          onTap: () => context.go('/warehouses'),
        ),
        const SizedBox(height: AppSpacing.md),
        const _SectionHeader(
          title: 'Aktionen',
          subtitle: 'Einstellungen und Abmeldung',
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(context.tr('settings')),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    context.read<AppState>().logout();
                    context.go('/login');
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(context.tr('logout')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(icon, color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileKpiChip extends StatelessWidget {
  const _ProfileKpiChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
