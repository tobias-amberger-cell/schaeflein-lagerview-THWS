import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/warehouse.dart';
import '../../../../models/warehouse_operations_profile.dart';
import '../../../../shared/widgets/abc_analysis_bar.dart';
import '../widgets/dashboard_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  AbcAnalysis? _deriveAbcForDisplay(Warehouse? warehouse) {
    if (warehouse == null) {
      return null;
    }
    final abc = warehouse.abcAnalysis;
    if (abc.total > 0) {
      return abc;
    }
    final articleCount = warehouse.articleCount;
    if (articleCount <= 0) {
      return abc;
    }
    final aCount = (articleCount * 0.2).round();
    final bCount = (articleCount * 0.3).round();
    final cCount = (articleCount - aCount - bCount).clamp(0, articleCount);
    return AbcAnalysis(aCount: aCount, bCount: bCount, cCount: cCount);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final warehouse = appState.riskFocusWarehouse;
    final operationsProfile = warehouse == null
        ? null
        : appState.getOperationsProfile(warehouse.id);
    final utilization = warehouse?.utilizationPercent ?? 0;
    final availableCount = appState.availableWarehouseCount;
    final favoriteCount = appState.favoriteWarehouseCount;
    final unreadNotifications = appState.unreadNotificationCount;
    final abc = _deriveAbcForDisplay(warehouse);

    final quickItems = <_QuickItem>[
      _QuickItem(
        label: '3D Ansicht',
        icon: Icons.view_in_ar,
        color: const Color(0xFF2563EB),
        onTap: () => context.go('/viewer'),
      ),
      _QuickItem(
        label: 'Heatmap',
        icon: Icons.local_fire_department_outlined,
        color: const Color(0xFFEA580C),
        onTap: () => context.go('/viewer'),
      ),
      _QuickItem(
        label: 'Zonen',
        icon: Icons.grid_view_rounded,
        color: const Color(0xFF0F766E),
        onTap: () => context.go('/viewer'),
      ),
      _QuickItem(
        label: 'Lagerliste',
        icon: Icons.warehouse_outlined,
        color: const Color(0xFF4338CA),
        onTap: () => context.go('/warehouses'),
      ),
    ];

    return RefreshIndicator(
      onRefresh: appState.syncWarehouses,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 720;
              return _DashboardHero(
                warehouse: warehouse,
                utilization: utilization,
                availableCount: availableCount,
                unreadNotifications: unreadNotifications,
                onOpenWarehouseList: () => context.go('/warehouses'),
                isCompact: isCompact,
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isSplit =
                  constraints.maxWidth >= AppBreakpoints.desktop + 120;
              final mainColumn = _buildMainColumn(
                context,
                warehouse: warehouse,
                operationsProfile: operationsProfile,
                utilization: utilization,
                availableCount: availableCount,
                favoriteCount: favoriteCount,
                abc: abc,
                quickItems: quickItems,
              );
              if (!isSplit) {
                return mainColumn;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 3, child: mainColumn),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: _SelectedWarehousePanel(
                      warehouse: warehouse,
                      operationsProfile: operationsProfile,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainColumn(
    BuildContext context, {
    required Warehouse? warehouse,
    required int utilization,
    required int availableCount,
    required int favoriteCount,
    required AbcAnalysis? abc,
    required List<_QuickItem> quickItems,
    required WarehouseOperationsProfile? operationsProfile,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final totalSlots = warehouse?.totalStorageSlots ?? 0;
    final occupiedSlots = warehouse?.occupiedStorageSlots ?? 0;
    final freeSlots = warehouse?.freeStorageSlots ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _WebSummaryRow(
          availableCount: availableCount,
          favoriteCount: favoriteCount,
          utilization: utilization,
          freeSlots: freeSlots,
        ),
        const SizedBox(height: AppSpacing.md),
        _QuickActionBar(
          warehouse: warehouse,
          onOpenViewer: () => context.go('/viewer'),
          onOpenWarehouses: () => context.go('/warehouses'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _QuickCardsSection(items: quickItems),
        const SizedBox(height: AppSpacing.md),
        const _SectionHeader(
          title: 'Kennzahlen',
          subtitle: 'Status, Durchsatz und aktuelle Systemlage.',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final columns = maxWidth >= 1100
                ? 4
                : maxWidth >= 860
                    ? 3
                    : maxWidth >= 620
                        ? 2
                        : 1;
            final cardWidth =
                (maxWidth - (AppSpacing.sm * (columns - 1))) / columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                SizedBox(
                  width: cardWidth,
                  child: DashboardCard(
                    title: 'Auslastung',
                    value: '${utilization}%',
                    subtitle: totalSlots == 0
                        ? 'Keine Kapazität gepflegt'
                        : '$occupiedSlots von $totalSlots Plätzen belegt',
                    icon: Icons.trending_up,
                    iconColor: const Color(0xFF2563EB),
                    badgeLabel: utilization > 85 ? 'Hoch' : 'Stabil',
                    badgeIcon: utilization > 85
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    badgeBackgroundColor: utilization > 85
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFDCFCE7),
                    badgeForegroundColor:
                        utilization > 85 ? const Color(0xFFB91C1C) : null,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: DashboardCard(
                    title: 'Artikel aktiv',
                    value: warehouse == null
                        ? '—'
                        : _formatNumber(warehouse.articleCount),
                    subtitle: 'Aktive SKU im Lager',
                    icon: Icons.inventory_2_outlined,
                    iconColor: const Color(0xFF0F766E),
                    badgeLabel: 'Live',
                    badgeIcon: Icons.circle,
                    badgeBackgroundColor: const Color(0xFFE0F2FE),
                    badgeForegroundColor: const Color(0xFF0369A1),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: DashboardCard(
                    title: 'Inbound pro Tag',
                    value: warehouse == null
                        ? '—'
                        : '${warehouse.inboundPerDay}',
                    subtitle: 'Eingehende Paletten',
                    icon: Icons.call_received_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    badgeLabel: 'Plan',
                    badgeOutlined: true,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: DashboardCard(
                    title: 'Durchsatz',
                    value: warehouse == null
                        ? '—'
                        : '${warehouse.throughputPerDay}',
                    subtitle: 'Sendungen pro Tag',
                    icon: Icons.local_shipping_outlined,
                    iconColor: const Color(0xFFF97316),
                    badgeLabel: 'Heute',
                    badgeOutlined: true,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.analytics_outlined,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'ABC Analyse',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  warehouse == null
                      ? 'Keine Lagerauswahl aktiv.'
                      : 'Warenstruktur nach Umschlagshäufigkeit.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                AbcAnalysisBar(
                  aCount: abc?.aCount ?? 0,
                  bCount: abc?.bCount ?? 0,
                  cCount: abc?.cCount ?? 0,
                  height: 14,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    _InlineKpi(
                      label: 'A-Artikel',
                      value: '${abc?.aCount ?? 0}',
                      color: const Color(0xFF15803D),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _InlineKpi(
                      label: 'B-Artikel',
                      value: '${abc?.bCount ?? 0}',
                      color: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _InlineKpi(
                      label: 'C-Artikel',
                      value: '${abc?.cCount ?? 0}',
                      color: const Color(0xFF6B7280),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (operationsProfile != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          const _SectionHeader(
            title: 'Systemlage',
            subtitle: 'Sicherheits- und Qualitätsindikatoren.',
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _InfoChip(
                label: 'Qualitätsholds',
                value: operationsProfile.qualityHolds,
                icon: Icons.verified_outlined,
                color: const Color(0xFF0EA5E9),
              ),
              _InfoChip(
                label: 'Sicherheitsvorfälle',
                value: operationsProfile.safetyIncidentsMonth,
                icon: Icons.health_and_safety_outlined,
                color: const Color(0xFFEF4444),
              ),
              _InfoChip(
                label: 'Blockierte Slots',
                value: operationsProfile.blockedSlots,
                icon: Icons.block_outlined,
                color: const Color(0xFF9A3412),
              ),
              _InfoChip(
                label: 'Reserviert',
                value: operationsProfile.reservedSlots,
                icon: Icons.bookmark_added_outlined,
                color: const Color(0xFF4F46E5),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _formatNumber(int value) {
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)} Mio';
  }
  if (absValue >= 10000) {
    return '${(value / 1000).toStringAsFixed(1)} Tsd';
  }
  return value.toString();
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$label: $value',
            style: textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
class _WebSummaryRow extends StatelessWidget {
  const _WebSummaryRow({
    required this.availableCount,
    required this.favoriteCount,
    required this.utilization,
    required this.freeSlots,
  });

  final int availableCount;
  final int favoriteCount;
  final int utilization;
  final int freeSlots;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 1200
            ? 4
            : maxWidth >= 900
                ? 3
                : maxWidth >= 620
                    ? 2
                    : 1;
        final cardWidth =
            (maxWidth - (AppSpacing.sm * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            SizedBox(
              width: cardWidth,
              child: _WebSummaryTile(
                label: 'Verfügbar',
                value: availableCount.toString(),
                subtitle: 'Standorte aktiv',
                icon: Icons.warehouse_outlined,
                accent: const Color(0xFF2563EB),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _WebSummaryTile(
                label: 'Favoriten',
                value: favoriteCount.toString(),
                subtitle: 'Aktive Fokuslager',
                icon: Icons.favorite_outline,
                accent: const Color(0xFFEC4899),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _WebSummaryTile(
                label: 'Auslastung',
                value: '$utilization%',
                subtitle: 'Gesamtstatus',
                icon: Icons.speed_outlined,
                accent: const Color(0xFF0F766E),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _WebSummaryTile(
                label: 'Freie Plätze',
                value: _formatNumber(freeSlots),
                subtitle: 'Sofort verfügbar',
                icon: Icons.inventory_2_outlined,
                accent: const Color(0xFFF97316),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WebSummaryTile extends StatelessWidget {
  const _WebSummaryTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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

class _SelectedWarehousePanel extends StatelessWidget {
  const _SelectedWarehousePanel({
    required this.warehouse,
    required this.operationsProfile,
  });

  final Warehouse? warehouse;
  final WarehouseOperationsProfile? operationsProfile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (warehouse == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Kein Lager gewählt',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Wähle ein Lager aus der Liste, um Detailkennzahlen zu sehen.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => context.go('/warehouses'),
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                label: const Text('Zur Lagerliste'),
              ),
            ],
          ),
        ),
      );
    }

    final current = warehouse!;
    final utilization = current.utilizationPercent;
    final statusLabel = _statusLabel(current.status);
    final statusColor = _statusColor(current.status);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.warehouse_outlined, color: statusColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        current.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        current.location,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusLabel,
                style: textTheme.labelLarge?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Kapazität',
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: utilization / 100,
                minHeight: 10,
                color: statusColor,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${current.occupiedStorageSlots} von ${current.totalStorageSlots} Plätzen belegt',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            _InlineKpi(
              label: 'Zonen',
              value: current.zoneCount.toString(),
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(height: AppSpacing.sm),
            _InlineKpi(
              label: 'Artikel',
              value: _formatNumber(current.articleCount),
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(height: AppSpacing.sm),
            _InlineKpi(
              label: 'Pick/Std',
              value: current.pickRatePerHour.toString(),
              color: const Color(0xFFF97316),
            ),
            if (operationsProfile != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                'SLA',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: operationsProfile!.slaCurrentPercent / 100,
                  minHeight: 10,
                  color: const Color(0xFF16A34A),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${operationsProfile!.slaCurrentPercent}% Ziel ${operationsProfile!.slaTargetPercent}%',
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
class _QuickItem {
  const _QuickItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _QuickCardsSection extends StatelessWidget {
  const _QuickCardsSection({required this.items});

  final List<_QuickItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 1100
            ? 4
            : maxWidth >= 860
                ? 3
                : maxWidth >= 620
                    ? 2
                    : 1;
        final cardWidth =
            (maxWidth - (AppSpacing.sm * (columns - 1))) / columns;

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: items
              .map(
                (item) => SizedBox(
                  width: cardWidth,
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: item.onTap,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: item.color.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Icon(item.icon, color: item.color),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              item.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Schnellzugriff',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _QuickActionBar extends StatelessWidget {
  const _QuickActionBar({
    required this.warehouse,
    required this.onOpenViewer,
    required this.onOpenWarehouses,
  });

  final Warehouse? warehouse;
  final VoidCallback onOpenViewer;
  final VoidCallback onOpenWarehouses;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        final content = <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Schnellzugriff',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  warehouse == null
                      ? 'Wähle ein Lager, um 3D und Heatmap zu öffnen.'
                      : 'Aktives Lager: ${warehouse!.name}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: isCompact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onOpenViewer,
                icon: const Icon(Icons.view_in_ar, size: 18),
                label: const Text('3D'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenWarehouses,
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                label: const Text('Lager'),
              ),
            ],
          ),
        ];

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    content.first,
                    const SizedBox(height: AppSpacing.sm),
                    content.last,
                  ],
                )
              : Row(children: content),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.warehouse,
    required this.utilization,
    required this.availableCount,
    required this.unreadNotifications,
    required this.onOpenWarehouseList,
    required this.isCompact,
  });

  final Warehouse? warehouse;
  final int utilization;
  final int availableCount;
  final int unreadNotifications;
  final VoidCallback onOpenWarehouseList;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primaryContainer.withValues(alpha: 0.55),
            colorScheme.surfaceContainerLowest,
          ],
        ),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Dashboard',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Fokus auf das aktive Lager, Heatmap und Kennzahlen.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (!isCompact)
                  FilledButton.tonalIcon(
                    onPressed: onOpenWarehouseList,
                    icon: const Icon(Icons.warehouse_outlined, size: 18),
                    label: const Text('Lagerliste'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _HeroChip(
                  icon: Icons.warehouse_outlined,
                  label: 'Standorte',
                  value: '$availableCount',
                  color: colorScheme.primary,
                ),
                _HeroChip(
                  icon: Icons.speed_outlined,
                  label: 'Auslastung',
                  value: '$utilization%',
                  color: const Color(0xFF0F766E),
                ),
                if (unreadNotifications > 0)
                  _HeroChip(
                    icon: Icons.notifications_active_outlined,
                    label: 'Alerts',
                    value: unreadNotifications.toString(),
                    color: const Color(0xFFDC2626),
                  ),
                _HeroChip(
                  icon: Icons.location_on_outlined,
                  label: 'Aktives Lager',
                  value: warehouse?.name ?? 'Nicht gesetzt',
                  color: const Color(0xFF4338CA),
                ),
              ],
            ),
            if (isCompact) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonalIcon(
                onPressed: onOpenWarehouseList,
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                label: const Text('Lagerliste'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _InlineKpi extends StatelessWidget {
  const _InlineKpi({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

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
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$label: $value',
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

  String _statusLabel(WarehouseStatus status) {
    switch (status) {
      case WarehouseStatus.online:
        return 'Online';
      case WarehouseStatus.limited:
        return 'Eingeschränkt';
      case WarehouseStatus.maintenance:
        return 'Wartung';
    }
  }

Color _statusColor(WarehouseStatus status) {
  switch (status) {
    case WarehouseStatus.online:
      return const Color(0xFF16A34A);
    case WarehouseStatus.limited:
      return const Color(0xFFF59E0B);
    case WarehouseStatus.maintenance:
      return const Color(0xFFDC2626);
  }
}
