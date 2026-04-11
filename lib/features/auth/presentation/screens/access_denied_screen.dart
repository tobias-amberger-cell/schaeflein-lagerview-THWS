import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/page_section_header.dart';
import '../../../../shared/widgets/ssi_branding.dart';

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({
    super.key,
    this.fromPath,
  });

  final String? fromPath;

  @override
  Widget build(BuildContext context) {
    final deniedPath = fromPath?.trim().isNotEmpty == true ? fromPath! : '-';

    return Scaffold(
      appBar: AppBar(
        title: CompanyAppBarTitle(sectionTitle: context.tr('accessDeniedTitle')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.desktop),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: <Widget>[
                PageSectionHeader(
                  title: context.tr('accessDeniedTitle'),
                  subtitle: context.tr(
                    'accessDeniedMessage',
                    <String, Object>{'path': deniedPath},
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: EmptyState(
                      icon: Icons.lock_outline_rounded,
                      title: context.tr('accessDeniedTitle'),
                      message: context.tr(
                        'accessDeniedMessage',
                        <String, Object>{'path': deniedPath},
                      ),
                      actionLabel: context.tr('toDashboard'),
                      onAction: () => context.go('/dashboard'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
