import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/abc_analysis_bar.dart';
import '../../../../shared/widgets/page_section_header.dart';
import '../widgets/alerts_card.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/dashboard_helpers.dart';
import '../widgets/dashboard_hero.dart';
import '../widgets/operations_status_card.dart';
import '../widgets/selected_warehouse_panel.dart';
import '../widgets/tickets_card.dart';
import '../widgets/throughput_trend_card.dart';
import '../widgets/top_risk_strip.dart';

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
    final notifications = appState.notifications;
    final tickets = appState.controlTowerTickets;
    final heatmapMetric = appState.viewerHeatmapMetric;
    final allWarehouses = <Warehouse>[...appState.warehouses]
      ..sort((a, b) => a.name.compareTo(b.name));
    final topZones = topHeatmapZones(
      appState.viewerHeatmapData,
      heatmapMetric,
      maxItems: 6,
    );
    final topRiskPercent = (appState.topRiskScore.clamp(0, 1) * 100).round();
    final throughputTrendFuture = appState.loadThroughputTrend();
    final isOffline =
        appState.isWarehouseOfflineMode || appState.warehouseApiError != null;

    return RefreshIndicator(
      onRefresh: appState.syncWarehouses,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          PageSectionHeader(
            eyebrow: 'Leitstand',
            title: 'Dashboard',
            subtitle: warehouse == null
                ? 'Kein aktives Lager ausgewählt'
                : 'Aktives Lager: ${warehouse.name}',
            badges: <Widget>[
              _DashboardHeaderBadge(
                icon: Icons.warehouse_outlined,
                label:
                    '$availableCount ${availableCount == 1 ? 'Lager' : 'Lagerstandorte'}',
              ),
              _DashboardHeaderBadge(
                icon: Icons.favorite_border,
                label: '$favoriteCount Favoriten',
              ),
              _DashboardHeaderBadge(
                icon: appState.hasCriticalTopRisk
                    ? Icons.priority_high_rounded
                    : Icons.monitor_heart_outlined,
                label: 'Risiko $topRiskPercent%',
                critical: appState.hasCriticalTopRisk,
              ),
            ],
            trailing: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => context.go('/warehouses'),
                  icon: const Icon(Icons.warehouse_outlined, size: 16),
                  label: const Text('Lager'),
                ),
                FilledButton.icon(
                  onPressed: () => context.go('/viewer'),
                  icon: const Icon(Icons.view_in_ar_outlined, size: 16),
                  label: const Text('3D'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < AppBreakpoints.tablet;
              return DashboardHero(
                warehouse: warehouse,
                utilization: utilization,
                availableCount: availableCount,
                unreadNotifications: unreadNotifications,
                criticalTickets: appState.criticalControlTowerTicketCount,
                topRiskZone: appState.topRiskZoneName,
                topRiskScore: appState.topRiskScore,
                lastSyncLabel:
                    formatRelativeTime(appState.lastWarehouseSyncAt),
                isOffline: isOffline,
                isSyncing: appState.isWarehousesSyncing,
                onSync: appState.syncWarehouses,
                onOpenWarehouseList: () => context.go('/warehouses'),
                isCompact: isCompact,
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ActiveWarehouseControlRow(
            warehouses: allWarehouses,
            selectedWarehouseId: warehouse?.id,
            onSelectWarehouse: (selected) =>
                appState.selectWarehouse(selected),
            onOpenViewer: () => context.go('/viewer'),
            onOpenWarehouses: () => context.go('/warehouses'),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isSplit =
                  constraints.maxWidth >= AppBreakpoints.desktop + 120;
              final mainColumn = _buildMainColumn(
                context,
                appState: appState,
                warehouse: warehouse,
                operationsProfile: operationsProfile,
                utilization: utilization,
                abc: abc,
                notifications: notifications,
                tickets: tickets,
                topZones: topZones,
                heatmapMetric: heatmapMetric,
                throughputTrendFuture: throughputTrendFuture,
                includeWarehousePanel: !isSplit,
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
                    child: SelectedWarehousePanel(
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
    required AppState appState,
    required Warehouse? warehouse,
    required int utilization,
    required AbcAnalysis? abc,
    required operationsProfile,
    required notifications,
    required tickets,
    required List<ViewerHeatmapEntry> topZones,
    required ViewerHeatmapMetric heatmapMetric,
    required throughputTrendFuture,
    required bool includeWarehousePanel,
  }) {
    final totalSlots = warehouse?.totalStorageSlots ?? 0;
    final occupiedSlots = warehouse?.occupiedStorageSlots ?? 0;
    final freeSlots = warehouse?.freeStorageSlots ?? 0;
    final slaCurrent = operationsProfile?.slaCurrentPercent ?? 0;
    final slaTarget = operationsProfile?.slaTargetPercent ?? 0;
    final pickRate = warehouse?.pickRatePerHour ?? 0;
    final dockUtilization = operationsProfile == null
        ? null
        : (operationsProfile.dockUtilizationRatio * 100).round();
    final qualityHolds = operationsProfile?.qualityHolds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TopRiskStrip(
          zones: topZones,
          metric: heatmapMetric,
          onOpenViewer: () => context.go('/viewer'),
          onSelectZone: (zoneName) {
            appState.setViewerHeatmapVisible(true);
            appState.requestViewerZoneFocus(zoneName);
            context.go('/viewer');
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionHeader(
          title: 'Kern-KPIs',
          subtitle: 'Wichtigste Live-Kennzahlen für das aktive Lager.',
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
                    title: 'Wareneingang/Tag',
                    value: warehouse == null
                        ? '—'
                        : '${warehouse.inboundPerDay}',
                    subtitle: 'Eingehende Paletten',
                    icon: Icons.call_received_rounded,
                    iconColor: AppColors.brandPurple,
                    badgeLabel: 'Plan',
                    badgeOutlined: true,
                    onTap: () {
                      appState.setViewerHeatmapMetric(
                          ViewerHeatmapMetric.congestion);
                      appState.setViewerHeatmapVisible(true);
                      context.go('/viewer');
                    },
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: DashboardCard(
                    title: 'Warenausgang/Tag',
                    value: warehouse == null
                        ? '—'
                        : '${warehouse.throughputPerDay}',
                    subtitle: 'Sendungen pro Tag',
                    icon: Icons.local_shipping_outlined,
                    iconColor: AppColors.brandOrange,
                    badgeLabel: 'Heute',
                    badgeOutlined: true,
                    onTap: () {
                      appState.setViewerHeatmapMetric(
                          ViewerHeatmapMetric.pickRate);
                      appState.setViewerHeatmapVisible(true);
                      context.go('/viewer');
                    },
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: DashboardCard(
                    title: 'Service-Level (SLA)',
                    value:
                        operationsProfile == null ? '—' : '$slaCurrent%',
                    subtitle: operationsProfile == null
                        ? 'SLA nicht verfügbar'
                        : 'Ziel $slaTarget%',
                    icon: Icons.verified_outlined,
                    iconColor: AppColors.brandBlue,
                    badgeLabel: operationsProfile == null
                        ? '—'
                        : (slaCurrent >= slaTarget ? 'OK' : 'Risiko'),
                    badgeBackgroundColor: operationsProfile == null
                        ? null
                        : slaCurrent >= slaTarget
                            ? AppColors.successLight
                            : AppColors.errorLight,
                    badgeForegroundColor: operationsProfile == null
                        ? null
                        : slaCurrent >= slaTarget
                            ? AppColors.successDark
                            : AppColors.errorDark,
                    onTap: () =>
                        context.go('/control-tower/tickets'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: DashboardCard(
                    title: 'Auslastung',
                    value: '$utilization%',
                    subtitle: totalSlots == 0
                        ? 'Keine Kapazität gepflegt'
                        : '$occupiedSlots von $totalSlots Plätzen belegt',
                    icon: Icons.trending_up,
                    iconColor: AppColors.brandBlue,
                    badgeLabel: utilization > 85 ? 'Hoch' : 'Stabil',
                    badgeIcon: utilization > 85
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    badgeBackgroundColor: utilization > 85
                        ? AppColors.errorLight
                        : AppColors.successLight,
                    badgeForegroundColor:
                        utilization > 85 ? AppColors.errorDark : null,
                    onTap: () {
                      appState.setViewerHeatmapMetric(
                          ViewerHeatmapMetric.utilization);
                      appState.setViewerHeatmapVisible(true);
                      context.go('/viewer');
                    },
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProcessSignalRow(
          dockUtilization: dockUtilization,
          pickRate: pickRate == 0 ? null : pickRate,
          freeSlots: freeSlots,
          qualityHolds: qualityHolds,
          avgDwellMinutes: operationsProfile?.avgDwellMinutes,
          blockedSlots: operationsProfile?.blockedSlots,
          slowMovers: operationsProfile?.reservedSlots,
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final abcCard = _AbcAnalysisCard(
              warehouse: warehouse,
              abc: abc,
            );
            final trendCard = ThroughputTrendCard(
              trendFuture: throughputTrendFuture,
            );
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: abcCard),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: trendCard),
                ],
              );
            }
            return Column(
              children: <Widget>[
                abcCard,
                const SizedBox(height: AppSpacing.sm),
                trendCard,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final alertsCard = AlertsCard(items: notifications);
            final ticketsCard = TicketsCard(tickets: tickets);
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: alertsCard),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: ticketsCard),
                ],
              );
            }
            return Column(
              children: <Widget>[
                alertsCard,
                const SizedBox(height: AppSpacing.sm),
                ticketsCard,
              ],
            );
          },
        ),
        if (operationsProfile != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader(
            title: 'Betriebsstatus',
            subtitle: 'Qualität, Sicherheit und Reservierungen im Blick.',
          ),
          OperationsStatusCard(profile: operationsProfile),
        ],
        if (includeWarehousePanel) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader(
            title: 'Fokuslager',
            subtitle: 'Kapazität, SLA und Systemstatus.',
          ),
          SelectedWarehousePanel(
            warehouse: warehouse,
            operationsProfile: operationsProfile,
          ),
        ],
      ],
    );
  }
}

// ── Remaining small private widgets ─────────────────────────────────────

class _DashboardHeaderBadge extends StatelessWidget {
  const _DashboardHeaderBadge({
    required this.icon,
    required this.label,
    this.critical = false,
  });

  final IconData icon;
  final String label;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor =
        critical ? AppColors.errorDark : colorScheme.primary;
    final backgroundColor = critical
        ? AppColors.errorLight
        : colorScheme.primaryContainer.withValues(alpha: 0.6);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: foregroundColor.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foregroundColor,
                  ),
            ),
          ],
        ),
      ),
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
    final isWide =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: (isWide ? textTheme.titleLarge : textTheme.titleMedium)
              ?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.15,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _ProcessSignalRow extends StatelessWidget {
  const _ProcessSignalRow({
    required this.dockUtilization,
    required this.pickRate,
    required this.freeSlots,
    required this.qualityHolds,
    this.avgDwellMinutes,
    this.blockedSlots,
    this.slowMovers,
  });

  final int? dockUtilization;
  final int? pickRate;
  final int freeSlots;
  final int? qualityHolds;
  final int? avgDwellMinutes;
  final int? blockedSlots;
  final int? slowMovers;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _ProcessSignalTile(
        label: 'Kommissionierleistung',
        value: pickRate == null ? '—' : '$pickRate / Std',
        subtitle: 'Picks pro Stunde',
        color: AppColors.success,
        icon: Icons.speed_outlined,
      ),
      _ProcessSignalTile(
        label: 'Restkapazität',
        value: formatNumber(freeSlots),
        subtitle: 'Freie Lagerplätze',
        color: AppColors.brandBlue,
        icon: Icons.inventory_2_outlined,
      ),
      if (avgDwellMinutes != null && avgDwellMinutes! > 0)
        _ProcessSignalTile(
          label: 'Ø Durchlaufzeit',
          value: '$avgDwellMinutes Min',
          subtitle: 'Durchschnitt pro Auftrag',
          color: AppColors.brandPurple,
          icon: Icons.timer_outlined,
        )
      else
        _ProcessSignalTile(
          label: 'Tor-Auslastung',
          value: dockUtilization == null ? '—' : '$dockUtilization%',
          subtitle: 'Aktive Tore',
          color: AppColors.brandSky,
          icon: Icons.local_shipping_outlined,
        ),
      if (blockedSlots != null && blockedSlots! > 0)
        _ProcessSignalTile(
          label: 'Gesperrte Plätze',
          value: blockedSlots.toString(),
          subtitle: 'Blockiert / Qualitätshold',
          color: AppColors.error,
          icon: Icons.block_outlined,
        )
      else
        _ProcessSignalTile(
          label: 'Qualitätsholds',
          value: qualityHolds == null ? '—' : qualityHolds.toString(),
          subtitle: 'Aktive Sperrungen',
          color: AppColors.brandOrange,
          icon: Icons.verified_outlined,
        ),
    ];

    // Add slow movers as 5th tile when available
    if (slowMovers != null && slowMovers! > 0) {
      tiles.add(
        _ProcessSignalTile(
          label: 'Slow Mover',
          value: slowMovers.toString(),
          subtitle: 'Ohne Bewegung > 90 Tage',
          color: AppColors.warningDark,
          icon: Icons.hourglass_bottom_outlined,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final tileCount = tiles.length;
        final columns = maxWidth >= 1100
            ? (tileCount >= 5 ? 5 : 4)
            : maxWidth >= 860
                ? 3
                : maxWidth >= 620
                    ? 2
                    : 1;
        final tileWidth =
            (maxWidth - (AppSpacing.sm * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tiles
              .map((tile) => SizedBox(width: tileWidth, child: tile))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ProcessSignalTile extends StatelessWidget {
  const _ProcessSignalTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
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

class _AbcAnalysisCard extends StatelessWidget {
  const _AbcAnalysisCard({
    required this.warehouse,
    required this.abc,
  });

  final Warehouse? warehouse;
  final AbcAnalysis? abc;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
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
                Icon(Icons.analytics_outlined,
                    color: colorScheme.primary),
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
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                InlineKpi(
                  label: 'A-Artikel',
                  value: '${abc?.aCount ?? 0}',
                  color: AppColors.abcA,
                ),
                InlineKpi(
                  label: 'B-Artikel',
                  value: '${abc?.bCount ?? 0}',
                  color: AppColors.abcB,
                ),
                InlineKpi(
                  label: 'C-Artikel',
                  value: '${abc?.cCount ?? 0}',
                  color: AppColors.abcC,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveWarehouseControlRow extends StatelessWidget {
  const _ActiveWarehouseControlRow({
    required this.warehouses,
    required this.selectedWarehouseId,
    required this.onSelectWarehouse,
    required this.onOpenViewer,
    required this.onOpenWarehouses,
  });

  final List<Warehouse> warehouses;
  final String? selectedWarehouseId;
  final ValueChanged<Warehouse> onSelectWarehouse;
  final VoidCallback onOpenViewer;
  final VoidCallback onOpenWarehouses;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final selectorField = DropdownButtonFormField<String>(
          initialValue: selectedWarehouseId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Aktives Lager',
            prefixIcon: Icon(Icons.warehouse_outlined),
          ),
          hint: const Text('Lager auswählen'),
          items: warehouses
              .map(
                (warehouse) => DropdownMenuItem<String>(
                  value: warehouse.id,
                  child: Text(
                    warehouse.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            for (final warehouse in warehouses) {
              if (warehouse.id == value) {
                onSelectWarehouse(warehouse);
                break;
              }
            }
          },
        );

        final actions = Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onOpenViewer,
              icon: const Icon(Icons.view_in_ar_outlined, size: 18),
              label: const Text('3D Ansicht'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenWarehouses,
              icon: const Icon(Icons.warehouse_outlined, size: 18),
              label: const Text('Lagerliste'),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: colorScheme.surfaceContainerLowest
                .withValues(alpha: 0.92),
            border: Border.all(
              color:
                  colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Lager-Fokus',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    selectorField,
                    const SizedBox(height: AppSpacing.sm),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: selectorField),
                    const SizedBox(width: AppSpacing.sm),
                    actions,
                  ],
                ),
        );
      },
    );
  }
}
