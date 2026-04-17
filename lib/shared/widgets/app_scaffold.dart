import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/state/app_state.dart';
import '../../models/warehouse.dart';
import 'ssi_branding.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _selectedIndexForLocation(location);
    final sectionTitle = _titleForLocation(location, l10n);
    final isProfileRoute = location.startsWith('/profile');
    final isViewerFullscreen = location.startsWith('/viewer/tour');
    final selectedWarehouse = context.select<AppState, Warehouse?>(
      (state) => state.selectedWarehouse,
    );
    final selectedWarehouseName = context.select<AppState, String?>(
      (state) => state.selectedWarehouse?.name,
    );
    final userName = context.select<AppState, String>((state) => state.userName);
    final liveRisk = context.select<AppState, ({String? zoneName, double score, bool critical})>(
      (state) => (
        zoneName: state.topRiskZoneName,
        score: state.topRiskScore,
        critical: state.hasCriticalTopRisk,
      ),
    );
    final viewerRiskSeverity = context.select<AppState, _ViewerRiskSeverity>(
      (state) {
        final score = state.topRiskScore;
        if (score >= 0.85) {
          return _ViewerRiskSeverity.critical;
        }
        if (score >= 0.65) {
          return _ViewerRiskSeverity.warning;
        }
        return _ViewerRiskSeverity.none;
      },
    );
    final criticalTicketCount =
        context.select<AppState, int>((state) => state.criticalControlTowerTicketCount);

    if (isViewerFullscreen) {
      return Scaffold(
        body: SafeArea(child: child),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= AppBreakpoints.rail;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final useWebLayout = kIsWeb && constraints.maxWidth >= 900;
        final useWebSidebar = kIsWeb && constraints.maxWidth >= 1200;

        if (useWebSidebar) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                _WebSidebar(
                  selectedIndex: selectedIndex,
                  criticalTicketCount: criticalTicketCount,
                  viewerRiskSeverity: viewerRiskSeverity,
                  selectedWarehouseName: selectedWarehouseName,
                  isProfileSelected: isProfileRoute,
                  onDestinationSelected: (index) =>
                      _onDestinationSelected(context, index),
                  onProfileTap: () => context.go('/profile'),
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _WebTopBar(
                        sectionTitle: sectionTitle,
                        location: location,
                        selectedWarehouse: selectedWarehouse,
                        hasSelectedWarehouse: selectedWarehouseName != null,
                        userName: userName,
                        liveRisk: liveRisk,
                        viewerRiskSeverity: viewerRiskSeverity,
                        criticalTicketCount: criticalTicketCount,
                        isProfileSelected: isProfileRoute,
                      ),
                      Expanded(
                        child: _AppBackdrop(
                          child: _WebBodyContainer(
                            includeTopSafeArea: false,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        if (useWebLayout) {
          return Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(72),
              child: _WebHeader(
                selectedIndex: selectedIndex,
                location: location,
                sectionTitle: sectionTitle,
                userName: userName,
                hasSelectedWarehouse: selectedWarehouseName != null,
                criticalTicketCount: criticalTicketCount,
                viewerRiskSeverity: viewerRiskSeverity,
                liveRisk: liveRisk,
                isProfileSelected: isProfileRoute,
                onDestinationSelected: (index) =>
                    _onDestinationSelected(context, index),
              ),
            ),
            body: _AppBackdrop(
              child: _WebBodyContainer(child: child),
            ),
          );
        }

        if (useNavigationRail) {
          final isExtended = constraints.maxWidth >= AppBreakpoints.desktop;
          return Scaffold(
            appBar: AppBar(
              title: CompanyAppBarTitle(sectionTitle: sectionTitle),
              toolbarHeight: 64,
              actions: <Widget>[
                _ViewerWorkflowAction(
                  location: location,
                  hasSelectedWarehouse: selectedWarehouseName != null,
                ),
                _LiveRiskAction(
                  zoneName: liveRisk.zoneName,
                  riskScore: liveRisk.score,
                  isCritical: liveRisk.critical,
                ),
                const _ProfileAction(),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.35),
                ),
              ),
            ),
            body: Row(
              children: <Widget>[
                NavigationRail(
                  extended: isExtended,
                  selectedIndex: selectedIndex,
                  labelType: isExtended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  useIndicator: true,
                  minWidth: 72,
                  minExtendedWidth: 200,
                  onDestinationSelected: (index) =>
                      _onDestinationSelected(context, index),
                  destinations: <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: _DashboardDestinationIcon(
                        isSelected: false,
                        criticalCount: criticalTicketCount,
                      ),
                      selectedIcon: _DashboardDestinationIcon(
                        isSelected: true,
                        criticalCount: criticalTicketCount,
                      ),
                      label: Text(l10n.tr('dashboard')),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.warehouse_outlined),
                      selectedIcon: Icon(Icons.warehouse),
                      label: Text(l10n.tr('warehouses')),
                    ),
                    NavigationRailDestination(
                      icon: _ViewerDestinationIcon(
                        isSelected: false,
                        severity: viewerRiskSeverity,
                      ),
                      selectedIcon: _ViewerDestinationIcon(
                        isSelected: true,
                        severity: viewerRiskSeverity,
                      ),
                      label: Text(l10n.tr('viewer')),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _AppBackdrop(
                    child: _BodyContainer(child: child),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: CompanyAppBarTitle(sectionTitle: sectionTitle),
            toolbarHeight: 64,
            actions: <Widget>[
              _ViewerWorkflowAction(
                location: location,
                hasSelectedWarehouse: selectedWarehouseName != null,
              ),
              _LiveRiskAction(
                zoneName: liveRisk.zoneName,
                riskScore: liveRisk.score,
                isCritical: liveRisk.critical,
              ),
              const _ProfileAction(),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.35),
              ),
            ),
          ),
          body: _AppBackdrop(
            child: _BodyContainer(child: child),
          ),
          bottomNavigationBar: keyboardOpen
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLowest
                          .withValues(alpha: 0.98),
                      elevation: 10,
                      shadowColor: Colors.black.withValues(alpha: 0.18),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: NavigationBarTheme(
                          data: NavigationBarThemeData(
                            height: 72,
                            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                            indicatorColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.75),
                            labelTextStyle: WidgetStateProperty.resolveWith((states) {
                              final isSelected = states.contains(WidgetState.selected);
                              return Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  );
                            }),
                          ),
                          child: NavigationBar(
                            selectedIndex: selectedIndex,
                            onDestinationSelected: (index) =>
                                _onDestinationSelected(context, index),
                            destinations: <NavigationDestination>[
                              NavigationDestination(
                                icon: _DashboardDestinationIcon(
                                  isSelected: false,
                                  criticalCount: criticalTicketCount,
                                ),
                                selectedIcon: _DashboardDestinationIcon(
                                  isSelected: true,
                                  criticalCount: criticalTicketCount,
                                ),
                                label: l10n.tr('dashboard'),
                              ),
                              NavigationDestination(
                                icon: const Icon(Icons.warehouse_outlined),
                                selectedIcon: const Icon(Icons.warehouse),
                                label: l10n.tr('warehouses'),
                              ),
                              NavigationDestination(
                                icon: _ViewerDestinationIcon(
                                  isSelected: false,
                                  severity: viewerRiskSeverity,
                                ),
                                selectedIcon: _ViewerDestinationIcon(
                                  isSelected: true,
                                  severity: viewerRiskSeverity,
                                ),
                                label: l10n.tr('viewer'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  int _selectedIndexForLocation(String location) {
    if (location.startsWith('/warehouses')) {
      return 1;
    }
    if (location.startsWith('/viewer')) {
      return 2;
    }
    if (location.startsWith('/profile')) {
      return 0;
    }
    return 0;
  }

  String _titleForLocation(String location, AppLocalizations l10n) {
    if (location.startsWith('/dashboard')) {
      return l10n.tr('dashboard');
    }
    if (location.startsWith('/warehouses')) {
      return l10n.tr('warehouses');
    }
    if (location.startsWith('/viewer')) {
      return l10n.tr('viewer');
    }
    if (location.startsWith('/profile')) {
      return l10n.tr('profile');
    }
    return l10n.tr('dashboard');
  }

  void _onDestinationSelected(BuildContext context, int index) {
    final appState = context.read<AppState>();
    switch (index) {
      case 0:
        context.go('/dashboard');
        return;
      case 1:
        context.go('/warehouses');
        return;
      case 2:
        if (appState.selectedWarehouse == null) {
          context.go('/warehouses');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('pleaseSelectWarehouse'))),
          );
          return;
        }
        context.go('/viewer');
        return;
    }
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr('profile'),
      onPressed: () => context.go('/profile'),
      icon: const Icon(Icons.person_outline),
    );
  }
}

class _ViewerWorkflowAction extends StatelessWidget {
  const _ViewerWorkflowAction({
    required this.location,
    required this.hasSelectedWarehouse,
  });

  final String location;
  final bool hasSelectedWarehouse;

  @override
  Widget build(BuildContext context) {
    final onViewer = location.startsWith('/viewer');
    final tooltip = onViewer
        ? context.tr('toWarehouseList')
        : (hasSelectedWarehouse ? context.tr('open3dView') : context.tr('warehouses'));

    return IconButton(
      tooltip: tooltip,
      onPressed: () {
        if (onViewer) {
          context.go('/warehouses');
          return;
        }
        if (hasSelectedWarehouse) {
          context.go('/viewer');
          return;
        }
        context.go('/warehouses');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('pleaseSelectWarehouse'))),
        );
      },
      icon: Icon(onViewer ? Icons.warehouse_outlined : Icons.view_in_ar_outlined),
    );
  }
}

class _LiveRiskAction extends StatelessWidget {
  const _LiveRiskAction({
    required this.zoneName,
    required this.riskScore,
    required this.isCritical,
  });

  final String? zoneName;
  final double riskScore;
  final bool isCritical;

  @override
  Widget build(BuildContext context) {
    if (zoneName == null) {
      return const SizedBox.shrink();
    }
    final riskPercent = (riskScore.clamp(0, 1) * 100).round();
    final colorScheme = Theme.of(context).colorScheme;
    final tooltip = isCritical
        ? 'Kritisches Live-Risiko: $zoneName ($riskPercent%)'
        : 'Live-Risiko: $zoneName ($riskPercent%)';

    return IconButton(
      tooltip: tooltip,
      onPressed: () {
        final appState = context.read<AppState>();
        final warehouse = appState.riskFocusWarehouse;
        final riskZone = appState.topRiskZoneName;
        if (warehouse == null || riskZone == null) {
          context.go('/dashboard');
          return;
        }
        appState.selectWarehouse(warehouse);
        appState.requestViewerZoneFocus(riskZone);
        context.go('/viewer');
        if (isCritical) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kritische Zone fokussiert: $riskZone')),
          );
        }
      },
      icon: Badge(
        isLabelVisible: true,
        backgroundColor: isCritical ? colorScheme.error : colorScheme.tertiary,
        textColor: isCritical ? colorScheme.onError : colorScheme.onTertiary,
        label: Text(isCritical ? '!' : '$riskPercent'),
        child: Icon(
          isCritical ? Icons.crisis_alert : Icons.monitor_heart_outlined,
        ),
      ),
    );
  }
}

class _AppBackdrop extends StatelessWidget {
  const _AppBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surfaceContainerLow.withValues(alpha: 0.75),
            colorScheme.surface,
            colorScheme.surfaceContainerLowest.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _BodyContainer extends StatelessWidget {
  const _BodyContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 600 ? AppSpacing.sm : AppSpacing.md;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.desktop),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: AppSpacing.md,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _WebBodyContainer extends StatelessWidget {
  const _WebBodyContainer({
    required this.child,
    this.includeTopSafeArea = true,
  });

  final Widget child;
  final bool includeTopSafeArea;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 1100 ? 20.0 : width < 1400 ? 28.0 : 36.0;
    return SafeArea(
      top: includeTopSafeArea,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.lg,
              horizontalPadding,
              AppSpacing.lg,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _WebSidebar extends StatelessWidget {
  const _WebSidebar({
    required this.selectedIndex,
    required this.criticalTicketCount,
    required this.viewerRiskSeverity,
    required this.selectedWarehouseName,
    required this.isProfileSelected,
    required this.onDestinationSelected,
    required this.onProfileTap,
  });

  final int selectedIndex;
  final int criticalTicketCount;
  final _ViewerRiskSeverity viewerRiskSeverity;
  final String? selectedWarehouseName;
  final bool isProfileSelected;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CompanyLogo(height: 26, showWordmark: true),
                  const SizedBox(width: 10),
                  Text(
                    AppConstants.appName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Navigation',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _SidebarNavItem(
                label: context.tr('dashboard'),
                selected: selectedIndex == 0,
                icon: _DashboardDestinationIcon(
                  isSelected: selectedIndex == 0,
                  criticalCount: criticalTicketCount,
                ),
                onTap: () => onDestinationSelected(0),
              ),
              const SizedBox(height: AppSpacing.xs),
              _SidebarNavItem(
                label: context.tr('warehouses'),
                selected: selectedIndex == 1,
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                onTap: () => onDestinationSelected(1),
              ),
              const SizedBox(height: AppSpacing.xs),
              _SidebarNavItem(
                label: context.tr('viewer'),
                selected: selectedIndex == 2,
                icon: _ViewerDestinationIcon(
                  isSelected: selectedIndex == 2,
                  severity: viewerRiskSeverity,
                ),
                onTap: () => onDestinationSelected(2),
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                height: 1,
              ),
              const SizedBox(height: AppSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.tr('selectedWarehouse'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Icon(
                            selectedWarehouseName == null
                                ? Icons.info_outline
                                : Icons.check_circle_outline,
                            size: 16,
                            color: selectedWarehouseName == null
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              selectedWarehouseName ??
                                  context.tr('pleaseSelectWarehouse'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: () => onDestinationSelected(1),
                        icon: const Icon(Icons.warehouse_outlined, size: 16),
                        label: Text(context.tr('warehouses')),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _SidebarNavItem(
                label: context.tr('profile'),
                selected: isProfileSelected,
                icon: const Icon(Icons.person_outline, size: 18),
                onTap: onProfileTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.7)
        : colorScheme.surface;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.4)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              IconTheme(
                data: IconThemeData(
                  size: 18,
                  color: selected ? foreground : colorScheme.onSurfaceVariant,
                ),
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: foreground,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebTopBar extends StatelessWidget {
  const _WebTopBar({
    required this.sectionTitle,
    required this.location,
    required this.selectedWarehouse,
    required this.hasSelectedWarehouse,
    required this.userName,
    required this.liveRisk,
    required this.viewerRiskSeverity,
    required this.criticalTicketCount,
    required this.isProfileSelected,
  });

  final String sectionTitle;
  final String location;
  final Warehouse? selectedWarehouse;
  final bool hasSelectedWarehouse;
  final String userName;
  final ({String? zoneName, double score, bool critical}) liveRisk;
  final _ViewerRiskSeverity viewerRiskSeverity;
  final int criticalTicketCount;
  final bool isProfileSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    sectionTitle.isEmpty ? AppConstants.appName : sectionTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sectionTitle.isEmpty
                        ? 'Operations Cockpit'
                        : 'Live-Übersicht',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              if (selectedWarehouse != null) ...<Widget>[
                const SizedBox(width: 12),
                Chip(
                  label: Text(selectedWarehouse!.name),
                  avatar: const Icon(Icons.warehouse_outlined, size: 16),
                  backgroundColor: colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              _ViewerWorkflowAction(
                location: location,
                hasSelectedWarehouse: hasSelectedWarehouse,
              ),
              _LiveRiskAction(
                zoneName: liveRisk.zoneName,
                riskScore: liveRisk.score,
                isCritical: liveRisk.critical,
              ),
              const SizedBox(width: 8),
              _WebProfileButton(
                userName: userName,
                selected: isProfileSelected,
                onTap: () => context.go('/profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebHeader extends StatelessWidget {
  const _WebHeader({
    required this.selectedIndex,
    required this.location,
    required this.sectionTitle,
    required this.userName,
    required this.hasSelectedWarehouse,
    required this.criticalTicketCount,
    required this.viewerRiskSeverity,
    required this.liveRisk,
    required this.isProfileSelected,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final String location;
  final String sectionTitle;
  final String userName;
  final bool hasSelectedWarehouse;
  final int criticalTicketCount;
  final _ViewerRiskSeverity viewerRiskSeverity;
  final ({String? zoneName, double score, bool critical}) liveRisk;
  final bool isProfileSelected;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        child: Row(
          children: <Widget>[
            CompanyLogo(height: 28, showWordmark: true),
            if (sectionTitle.trim().isNotEmpty) ...<Widget>[
              const SizedBox(width: 12),
              Text(
                sectionTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
            const SizedBox(width: 20),
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: <Widget>[
                  _WebNavItem(
                    label: context.tr('dashboard'),
                    selected: selectedIndex == 0,
                    icon: _DashboardDestinationIcon(
                      isSelected: selectedIndex == 0,
                      criticalCount: criticalTicketCount,
                    ),
                    onTap: () => onDestinationSelected(0),
                  ),
                  _WebNavItem(
                    label: context.tr('warehouses'),
                    selected: selectedIndex == 1,
                    icon: const Icon(Icons.warehouse_outlined, size: 18),
                    onTap: () => onDestinationSelected(1),
                  ),
                  _WebNavItem(
                    label: context.tr('viewer'),
                    selected: selectedIndex == 2,
                    icon: _ViewerDestinationIcon(
                      isSelected: selectedIndex == 2,
                      severity: viewerRiskSeverity,
                    ),
                    onTap: () => onDestinationSelected(2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ViewerWorkflowAction(
              location: location,
              hasSelectedWarehouse: hasSelectedWarehouse,
            ),
            _LiveRiskAction(
              zoneName: liveRisk.zoneName,
              riskScore: liveRisk.score,
              isCritical: liveRisk.critical,
            ),
            const SizedBox(width: 8),
            _WebProfileButton(
              userName: userName,
              selected: isProfileSelected,
              onTap: () => context.go('/profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebNavItem extends StatelessWidget {
  const _WebNavItem({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        );

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.7) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconTheme(
                data: IconThemeData(
                  size: 18,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                child: icon,
              ),
              const SizedBox(width: 8),
              Text(label, style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardDestinationIcon extends StatelessWidget {
  const _DashboardDestinationIcon({
    required this.isSelected,
    required this.criticalCount,
  });

  final bool isSelected;
  final int criticalCount;

  @override
  Widget build(BuildContext context) {
    final child = Icon(isSelected ? Icons.dashboard : Icons.dashboard_outlined);
    if (criticalCount <= 0) {
      return child;
    }
    return Badge(
      isLabelVisible: true,
      backgroundColor: Theme.of(context).colorScheme.error,
      textColor: Theme.of(context).colorScheme.onError,
      label: Text(criticalCount > 99 ? '99+' : '$criticalCount'),
      child: child,
    );
  }
}

enum _ViewerRiskSeverity {
  none,
  warning,
  critical,
}

class _ViewerDestinationIcon extends StatelessWidget {
  const _ViewerDestinationIcon({
    required this.isSelected,
    required this.severity,
  });

  final bool isSelected;
  final _ViewerRiskSeverity severity;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(isSelected ? Icons.view_in_ar : Icons.view_in_ar_outlined);
    if (severity == _ViewerRiskSeverity.none) {
      return icon;
    }
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = severity == _ViewerRiskSeverity.critical
        ? colorScheme.error
        : colorScheme.tertiary;
    final foregroundColor = severity == _ViewerRiskSeverity.critical
        ? colorScheme.onError
        : colorScheme.onTertiary;
    final label = severity == _ViewerRiskSeverity.critical ? '!' : '•';

    return Badge(
      isLabelVisible: true,
      backgroundColor: backgroundColor,
      textColor: foregroundColor,
      label: Text(label),
      child: icon,
    );
  }
}

class _WebProfileButton extends StatelessWidget {
  const _WebProfileButton({
    required this.userName,
    required this.selected,
    required this.onTap,
  });

  final String userName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nameParts = userName.trim().isEmpty
        ? const <String>[]
        : userName.trim().split(RegExp(r'\s+'));
    final initials = nameParts.isEmpty
        ? 'U'
        : nameParts
            .take(2)
            .map((part) => part.characters.first)
            .join()
            .toUpperCase();

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.72)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.45)
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                nameParts.isEmpty ? 'User' : nameParts.first,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? colorScheme.onPrimaryContainer : null,
                    ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

