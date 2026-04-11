import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/user_role.dart';
import '../../../../shared/widgets/page_section_header.dart';
import '../../../../shared/widgets/section_card_header.dart';
import '../../../../shared/widgets/ssi_branding.dart';
import '../../../viewer/domain/viewer_type.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final header = PageSectionHeader(
      title: context.tr('settings'),
      subtitle: context.tr('settingsSubtitle'),
    );
    final hero = _SettingsHeroPanel(appState: appState);
    final cards = <Widget>[
      const _SectionHeader(
        title: 'Allgemein',
        subtitle: 'Benachrichtigungen und Theme',
      ),
      _buildGeneralSettingsCard(context, appState),
      _buildAutoSaveCard(context, appState),
      const _SectionHeader(
        title: 'Profil & Zugriff',
        subtitle: 'Rolle und Sprache einstellen',
      ),
      _buildRoleCard(context, appState),
      _buildLanguageCard(context, appState),
      const _SectionHeader(
        title: 'Viewer',
        subtitle: '3D-Integration und Anzeige',
      ),
      _buildViewerCard(context, appState),
      const _SectionHeader(
        title: 'Transfer',
        subtitle: 'Einstellungen exportieren oder importieren',
      ),
      _buildTransferCard(context, appState),
      const _SectionHeader(
        title: 'Automatisierung',
        subtitle: 'Auto-Eskalation und Regeln',
      ),
      _buildAutoEscalationCard(context, appState),
      const _SectionHeader(
        title: 'System',
        subtitle: 'Version und Status',
      ),
      _buildVersionCard(context),
    ];

    return Scaffold(
      appBar: AppBar(
        title: CompanyAppBarTitle(sectionTitle: context.tr('settings')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.desktop),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth >= AppBreakpoints.rail;
                if (!useTwoColumns) {
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: <Widget>[
                      header,
                      const SizedBox(height: AppSpacing.md),
                      hero,
                      const SizedBox(height: AppSpacing.md),
                      ..._withVerticalSpacing(cards),
                    ],
                  );
                }

                final leftColumnCards = <Widget>[
                  cards[0],
                  cards[1],
                  cards[2],
                  cards[3],
                  cards[4],
                  cards[5],
                  cards[6],
                ];
                final rightColumnCards = <Widget>[
                  cards[7],
                  cards[8],
                  cards[9],
                  cards[10],
                  cards[11],
                  cards[12],
                  cards[13],
                ];

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      header,
                      const SizedBox(height: AppSpacing.md),
                      hero,
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: _buildCardColumn(leftColumnCards)),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: _buildCardColumn(rightColumnCards)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardColumn(List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _withVerticalSpacing(cards),
    );
  }

  List<Widget> _withVerticalSpacing(List<Widget> items) {
    final spaced = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      if (index > 0) {
        spaced.add(const SizedBox(height: AppSpacing.md));
      }
      spaced.add(items[index]);
    }
    return spaced;
  }

  Widget _buildGeneralSettingsCard(BuildContext context, AppState appState) {
    return _ModernSettingsCard(
      child: Column(
        children: <Widget>[
          SwitchListTile(
            title: Text(context.tr('notificationsToggle')),
            subtitle: Text(context.tr('notificationsDemoSetting')),
            value: appState.notificationsEnabled,
            onChanged: appState.setNotificationsEnabled,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(context.tr('darkMode')),
            subtitle: Text(context.tr('themeSwitch')),
            value: appState.isDarkMode,
            onChanged: appState.setDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSaveCard(BuildContext context, AppState appState) {
    return _ModernSettingsCard(
      child: ListTile(
        leading: const Icon(Icons.cloud_done_outlined),
        title: Text(context.tr('settingsAutoSaveStatus')),
        subtitle: Text(
          context.tr(
            'settingsLastSavedAt',
            <String, Object>{
              'time': _formatSavedTime(
                context,
                appState.settingsLastSavedAt,
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTransferCard(BuildContext context, AppState appState) {
    return _ModernSettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionCardHeader(
              title: context.tr('settingsTransferTitle'),
              subtitle: context.tr('settingsTransferSubtitle'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _exportSettings(context, appState),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: Text(context.tr('settingsExportAction')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showImportDialog(context, appState),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(context.tr('settingsImportAction')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, AppState appState) {
    return _ModernSettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionCardHeader(
              title: context.tr('roleDemo'),
              subtitle: context.tr('roleDemoHint'),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<UserRole>(
              initialValue: appState.userRole,
              items: UserRole.values
                  .map(
                    (role) => DropdownMenuItem<UserRole>(
                      value: role,
                      child: Text(context.tr(role.labelKey)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                appState.setUserRole(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageCard(BuildContext context, AppState appState) {
    return _ModernSettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionCardHeader(title: context.tr('language')),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: appState.languageCode,
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: 'de',
                  child: Text(context.tr('languageGerman')),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Text(context.tr('languageEnglish')),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                appState.setLanguageCode(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewerCard(BuildContext context, AppState appState) {
    return _ModernSettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionCardHeader(
              title: context.tr('viewerIntegration'),
              subtitle: context.tr(appState.viewerType.descriptionKey),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ViewerType>(
              initialValue: appState.viewerType,
              items: ViewerType.values
                  .map(
                    (type) => DropdownMenuItem<ViewerType>(
                      value: type,
                      child: Text(context.tr(type.labelKey)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                appState.setViewerType(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoEscalationCard(BuildContext context, AppState appState) {
    return _ModernSettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionCardHeader(
              title: context.tr('autoEscalationSettingsTitle'),
              subtitle: context.tr('autoEscalationSettingsSubtitle'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr('autoEscalationPresetLabel'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                ...<AutoEscalationPreset>[
                  AutoEscalationPreset.conservative,
                  AutoEscalationPreset.standard,
                  AutoEscalationPreset.aggressive,
                ].map(
                  (preset) => ChoiceChip(
                    label: Text(context.tr(preset.labelKey)),
                    selected: appState.autoEscalationPreset == preset,
                    onSelected: (_) => appState.setAutoEscalationPreset(preset),
                  ),
                ),
                ChoiceChip(
                  label: Text(
                    context.tr(AutoEscalationPreset.custom.labelKey),
                  ),
                  selected:
                      appState.autoEscalationPreset == AutoEscalationPreset.custom,
                  onSelected: null,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr(
                'autoEscalationPresetCurrent',
                <String, Object>{
                  'preset': context.tr(appState.autoEscalationPreset.labelKey),
                },
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr(
                'autoEscalationFirstStepValue',
                <String, Object>{
                  'minutes': appState.autoEscalationFirstStepMinutes,
                },
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Slider(
              value: appState.autoEscalationFirstStepMinutes.toDouble(),
              min: 0,
              max: 120,
              divisions: 24,
              label: '${appState.autoEscalationFirstStepMinutes}',
              onChanged: (value) {
                appState.setAutoEscalationFirstStepMinutes(
                  value.round(),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr(
                'autoEscalationSecondStepValue',
                <String, Object>{
                  'minutes': appState.autoEscalationSecondStepMinutes,
                },
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Slider(
              value: appState.autoEscalationSecondStepMinutes.toDouble(),
              min: appState.autoEscalationFirstStepMinutes.toDouble(),
              max: 240,
              divisions: 48,
              label: '${appState.autoEscalationSecondStepMinutes}',
              onChanged: (value) {
                appState.setAutoEscalationSecondStepMinutes(
                  value.round(),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  appState.resetAutoEscalationRules();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.tr('autoEscalationResetDone'),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.restart_alt_outlined),
                label: Text(context.tr('autoEscalationResetRules')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionCard(BuildContext context) {
    return _ModernSettingsCard(
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(context.tr('appVersion')),
        subtitle: const Text(AppConstants.appVersion),
      ),
    );
  }

  String _formatSavedTime(BuildContext context, DateTime? timestamp) {
    if (timestamp == null) {
      return context.tr('settingsNeverSaved');
    }
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) {
      return context.tr('justNow');
    }
    if (diff.inMinutes < 60) {
      return context.tr('minutesAgo', <String, Object>{'count': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return context.tr('hoursAgo', <String, Object>{'count': diff.inHours});
    }
    return context.tr('daysAgo', <String, Object>{'count': diff.inDays});
  }

  Future<void> _exportSettings(BuildContext context, AppState appState) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final payload = appState.exportSettingsAsJson();
    await Clipboard.setData(ClipboardData(text: payload));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.tr('settingsExportCopied'))),
    );
  }

  Future<void> _showImportDialog(BuildContext context, AppState appState) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    var hasInput = false;
    var isValidJson = false;

    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.tr('settingsImportTitle')),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: controller,
                      maxLines: 10,
                      minLines: 6,
                      onChanged: (value) {
                        final trimmedValue = value.trim();
                        setState(() {
                          hasInput = trimmedValue.isNotEmpty;
                          isValidJson = _isValidSettingsJson(trimmedValue);
                        });
                      },
                      decoration: InputDecoration(
                        hintText: l10n.tr('settingsImportHint'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (!hasInput)
                      Text(
                        l10n.tr('settingsImportValidationHint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (hasInput && isValidJson)
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              l10n.tr('settingsImportJsonValid'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    if (hasInput && !isValidJson)
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              l10n.tr('settingsImportJsonInvalid'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton.icon(
                  onPressed: () async {
                    final clipboardData = await Clipboard.getData('text/plain');
                    final clipboardText = clipboardData?.text?.trim() ?? '';
                    if (clipboardText.isEmpty) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.tr('settingsImportClipboardEmpty'),
                          ),
                        ),
                      );
                      return;
                    }
                    controller.value = TextEditingValue(
                      text: clipboardText,
                      selection: TextSelection.collapsed(
                        offset: clipboardText.length,
                      ),
                    );
                    setState(() {
                      hasInput = true;
                      isValidJson = _isValidSettingsJson(clipboardText);
                    });
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l10n.tr('settingsImportClipboardLoaded')),
                      ),
                    );
                  },
                  icon: const Icon(Icons.content_paste_outlined),
                  label: Text(l10n.tr('settingsImportPasteFromClipboard')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.tr('cancel')),
                ),
                FilledButton(
                  onPressed: isValidJson
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: Text(l10n.tr('settingsImportApply')),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldImport == true) {
      final success = await appState.importSettingsFromJson(controller.text.trim());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(success ? 'settingsImportSuccess' : 'settingsImportFailed'),
          ),
        ),
      );
    }
    controller.dispose();
  }

  bool _isValidSettingsJson(String raw) {
    if (raw.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
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

class _SettingsHeroPanel extends StatelessWidget {
  const _SettingsHeroPanel({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            _SettingsSummaryChip(
              icon: Icons.badge_outlined,
              label: context.tr('roleDemo'),
              value: context.tr(appState.userRoleLabelKey),
            ),
            _SettingsSummaryChip(
              icon: Icons.language_outlined,
              label: context.tr('language'),
              value: appState.languageCode == 'de'
                  ? context.tr('languageGerman')
                  : context.tr('languageEnglish'),
            ),
            _SettingsSummaryChip(
              icon: Icons.view_in_ar_outlined,
              label: context.tr('viewerIntegration'),
              value: context.tr(appState.viewerType.labelKey),
            ),
            _SettingsSummaryChip(
              icon: appState.isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              label: context.tr('darkMode'),
              value: appState.isDarkMode ? 'On' : 'Off',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSummaryChip extends StatelessWidget {
  const _SettingsSummaryChip({
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

class _ModernSettingsCard extends StatelessWidget {
  const _ModernSettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}
