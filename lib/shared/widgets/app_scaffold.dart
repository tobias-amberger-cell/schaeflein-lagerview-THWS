import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/state/app_state.dart';
import '../../models/warehouse.dart';
import 'ssi_branding.dart';

class AppScaffold extends StatefulWidget {
  const AppScaffold({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  bool _webSidebarCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _selectedIndexForLocation(location);
    final sectionTitle = _titleForLocation(location, l10n);
    final isProfileRoute = location.startsWith('/profile');
    final isViewerFullscreen = location.startsWith('/viewer/tour');
    final selectedWarehouse = context.select<AppState, Warehouse?>(
      (state) => state.riskFocusWarehouse,
    );
    final selectedWarehouseName = context.select<AppState, String?>(
      (state) => state.riskFocusWarehouse?.name,
    );
    const showDataSelectors = true;
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
    const criticalTicketCount = 0;

    if (isViewerFullscreen) {
      return Scaffold(
        body: SafeArea(child: widget.child),
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
                  collapsed: _webSidebarCollapsed,
                  onToggleCollapsed: () {
                    setState(() {
                      _webSidebarCollapsed = !_webSidebarCollapsed;
                    });
                  },
                  onDestinationSelected: (index) =>
                      _onDestinationSelected(context, index),
                  onProfileTap: () => context.go('/profile'),
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _WebTopBar(
                        sectionTitle: sectionTitle,
                        showDataSelectors: false,
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
                            child: widget.child,
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
                showDataSelectors: showDataSelectors,
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
              child: _WebBodyContainer(child: widget.child),
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
                if (showDataSelectors) ...<Widget>[
                  const _DashboardHeaderFilters(compact: true),
                  const SizedBox(width: 6),
                ],
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
                    child: _BodyContainer(child: widget.child),
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
              if (showDataSelectors) ...<Widget>[
                const _DashboardHeaderFilters(compact: true),
                const SizedBox(width: 6),
              ],
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
            child: _BodyContainer(child: widget.child),
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

  bool _isDashboardLocation(String location) {
    return location == '/' || location.startsWith('/dashboard');
  }

  String _titleForLocation(String location, AppLocalizations l10n) {
    if (_isDashboardLocation(location)) {
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

class _AppBackdrop extends StatelessWidget {
  const _AppBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
            colorScheme.surface,
            colorScheme.surfaceContainerLowest.withValues(alpha: 0.94),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -140,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      colorScheme.primary.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -120,
            bottom: -180,
            child: IgnorePointer(
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      colorScheme.secondary.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _BodyContainer extends StatelessWidget {
  const _BodyContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 600
        ? AppSpacing.sm
        : width < 1200
            ? AppSpacing.md
            : 20.0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: AppSpacing.md,
        ),
        child: SizedBox(
          width: double.infinity,
          child: child,
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
    final horizontalPadding = width < 1000
        ? 16.0
        : width < 1300
            ? 24.0
            : width < 1700
                ? 32.0
                : 44.0;
    return SafeArea(
      top: includeTopSafeArea,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.lg,
          horizontalPadding,
          AppSpacing.lg,
        ),
        child: SizedBox(
          width: double.infinity,
          child: child,
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
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onDestinationSelected,
    required this.onProfileTap,
  });

  final int selectedIndex;
  final int criticalTicketCount;
  final _ViewerRiskSeverity viewerRiskSeverity;
  final String? selectedWarehouseName;
  final bool isProfileSelected;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sidebarWidth = collapsed ? 84.0 : 260.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: sidebarWidth,
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
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 10 : 18,
            vertical: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 150;
                  return Row(
                    children: <Widget>[
                      if (!narrow) ...<Widget>[
                        CompanyLogo(height: 26, showWordmark: !collapsed),
                        if (!collapsed) ...<Widget>[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppConstants.appName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: collapsed
                            ? 'Navigation erweitern'
                            : 'Navigation einklappen',
                        onPressed: onToggleCollapsed,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          collapsed
                              ? Icons.menu_open_rounded
                              : Icons.menu_rounded,
                          size: 18,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (!collapsed)
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
                compact: collapsed,
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
                compact: collapsed,
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                onTap: () => onDestinationSelected(1),
              ),
              const SizedBox(height: AppSpacing.xs),
              _SidebarNavItem(
                label: context.tr('viewer'),
                selected: selectedIndex == 2,
                compact: collapsed,
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
              if (!collapsed)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.md,
                      bottom: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _SidebarFilterHamburger(),
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
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),
              if (!collapsed) const SizedBox(height: AppSpacing.xs),
              _SidebarNavItem(
                label: context.tr('profile'),
                selected: isProfileSelected,
                compact: collapsed,
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

class _SidebarFilterHamburger extends StatefulWidget {
  const _SidebarFilterHamburger();

  @override
  State<_SidebarFilterHamburger> createState() =>
      _SidebarFilterHamburgerState();
}

class _SidebarFilterHamburgerState extends State<_SidebarFilterHamburger> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    const panelBackground = Color(0xFFD9DDE3);
    const panelBorder = Color(0xFFB3B9C2);
    const fieldBackground = Color(0xFFF3F4F6);
    const sliderColor = Color(0xFF005AA4);
    const labelColor = Color(0xFF1F324D);
    const hintColor = Color(0xFF8A94A5);
    final selectedHall = appState.dashboardSelectedHalls.isEmpty
        ? null
        : appState.dashboardSelectedHalls.first;
    final selectedAbc = appState.dashboardSelectedAbcClasses.isEmpty
        ? null
        : appState.dashboardSelectedAbcClasses.first;
    final utilizationRange = RangeValues(
      appState.dashboardUtilizationFilterMin,
      appState.dashboardUtilizationFilterMax,
    );
    final throughputDays = appState.dashboardKpiHorizonDays.toDouble();
    final topArticles = appState.dashboardTopArticlesLimit.toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: panelBackground,
        border: Border.all(color: panelBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.menu_rounded,
                    size: 18,
                    color: labelColor.withValues(alpha: 0.86),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Filter',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: hintColor,
                  ),
                ],
              ),
            ),
            if (_expanded) ...<Widget>[
              const SizedBox(height: 14),
              _filterLabelRow(
                context,
                label: 'Halle',
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedHall,
                hint: Text(
                  'Choose options',
                  style: textTheme.titleMedium?.copyWith(color: hintColor),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                decoration: _dropdownDecoration(fieldBackground),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: '', child: Text('Alle')),
                  DropdownMenuItem<String>(value: 'Halle 1', child: Text('Halle 1')),
                  DropdownMenuItem<String>(value: 'Halle 2', child: Text('Halle 2')),
                  DropdownMenuItem<String>(value: 'Halle 3', child: Text('Halle 3')),
                ],
                onChanged: (value) {
                  appState.setDashboardSelectedHalls(
                    value == null || value.isEmpty
                        ? const <String>[]
                        : <String>[value],
                  );
                },
              ),
              const SizedBox(height: 14),
              _filterLabelRow(
                context,
                label: 'ABC-Klasse',
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedAbc,
                hint: Text(
                  'Choose options',
                  style: textTheme.titleMedium?.copyWith(color: hintColor),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                decoration: _dropdownDecoration(fieldBackground),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: '', child: Text('Alle')),
                  DropdownMenuItem<String>(value: 'A', child: Text('A')),
                  DropdownMenuItem<String>(value: 'B', child: Text('B')),
                  DropdownMenuItem<String>(value: 'C', child: Text('C')),
                ],
                onChanged: (value) {
                  appState.setDashboardSelectedAbcClasses(
                    value == null || value.isEmpty
                        ? const <String>[]
                        : <String>[value],
                  );
                },
              ),
              const SizedBox(height: 14),
              _filterLabelRow(
                context,
                label: 'Auslastung (%)',
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        utilizationRange.start.round().toString(),
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: sliderColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        utilizationRange.end.round().toString(),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: sliderColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: sliderColor,
                  inactiveTrackColor: sliderColor.withValues(alpha: 0.25),
                  thumbColor: sliderColor,
                  overlayColor: sliderColor.withValues(alpha: 0.15),
                  rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
                ),
                child: RangeSlider(
                  min: 0,
                  max: 150,
                  divisions: 150,
                  values: utilizationRange,
                  onChanged: (value) {
                    appState.setDashboardUtilizationFilter(
                      min: value.start,
                      max: value.end,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Checkbox(
                    value: appState.dashboardOnlyOccupied,
                    onChanged: (value) {
                      appState.setDashboardOnlyOccupied(value ?? false);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Nur belegte Plaetze',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: labelColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(
                height: 1,
                color: panelBorder.withValues(alpha: 0.65),
              ),
              const SizedBox(height: 14),
              _singleSliderRow(
                context,
                label: 'Durchsatz-Zeitraum (Tage)',
                value: throughputDays.round().toString(),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: sliderColor,
                  inactiveTrackColor: sliderColor.withValues(alpha: 0.25),
                  thumbColor: sliderColor,
                  overlayColor: sliderColor.withValues(alpha: 0.15),
                ),
                child: Slider(
                  min: 7,
                  max: 180,
                  divisions: 173,
                  value: throughputDays,
                  onChanged: (value) {
                    appState.setDashboardKpiHorizonDays(value.round());
                  },
                ),
              ),
              const SizedBox(height: 10),
              _singleSliderRow(
                context,
                label: 'Top-Artikel anzeigen',
                value: topArticles.round().toString(),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: sliderColor,
                  inactiveTrackColor: sliderColor.withValues(alpha: 0.25),
                  thumbColor: sliderColor,
                  overlayColor: sliderColor.withValues(alpha: 0.15),
                ),
                child: Slider(
                  min: 5,
                  max: 100,
                  divisions: 95,
                  value: topArticles,
                  onChanged: (value) {
                    appState.setDashboardTopArticlesLimit(value.round());
                  },
                ),
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                color: panelBorder.withValues(alpha: 0.65),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(Color fillColor) {
    return InputDecoration(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF005AA4), width: 1.3),
      ),
    );
  }

  Widget _filterLabelRow(
    BuildContext context, {
    required String label,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: textTheme.titleMedium?.copyWith(
              color: const Color(0xFF1F324D),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Icon(
          Icons.help_outline_rounded,
          size: 18,
          color: const Color(0xFF6D7380),
        ),
      ],
    );
  }

  Widget _singleSliderRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1F324D),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 24, maxWidth: 42),
          child: FittedBox(
            alignment: Alignment.centerRight,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.labelLarge?.copyWith(
                color: const Color(0xFF8A94A5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final Widget icon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.82)
        : colorScheme.surfaceContainerLowest.withValues(alpha: 0.35);
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    final item = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.45)
                : colorScheme.outlineVariant.withValues(alpha: 0.26),
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: 11,
          ),
          child: Row(
            children: <Widget>[
              IconTheme(
                data: IconThemeData(
                  size: 18,
                  color: selected ? foreground : colorScheme.onSurfaceVariant,
                ),
                child: icon,
              ),
              if (!compact) ...<Widget>[
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
            ],
          ),
        ),
      ),
    );
    if (!compact) {
      return item;
    }
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 350),
      child: item,
    );
  }
}

class _WebTopBar extends StatelessWidget {
  const _WebTopBar({
    required this.sectionTitle,
    required this.showDataSelectors,
    required this.selectedWarehouse,
    required this.hasSelectedWarehouse,
    required this.userName,
    required this.liveRisk,
    required this.viewerRiskSeverity,
    required this.criticalTicketCount,
    required this.isProfileSelected,
  });

  final String sectionTitle;
  final bool showDataSelectors;
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
      color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Center(
                  child: Text(
                    sectionTitle.isEmpty ? AppConstants.appName : sectionTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showDataSelectors) ...<Widget>[
                        const _DashboardHeaderFilters(compact: false),
                        const SizedBox(width: 12),
                      ],
                      _WebProfileButton(
                        userName: userName,
                        selected: isProfileSelected,
                        onTap: () => context.go('/profile'),
                      ),
                    ],
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

class _WebHeader extends StatelessWidget {
  const _WebHeader({
    required this.selectedIndex,
    required this.showDataSelectors,
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
  final bool showDataSelectors;
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
      color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.95),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.34),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
            if (showDataSelectors) ...<Widget>[
              const _DashboardHeaderFilters(compact: true),
              const SizedBox(width: 8),
            ],
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

class _DashboardHeaderFilters extends StatelessWidget {
  const _DashboardHeaderFilters({required this.compact});

  final bool compact;

  Future<void> _pickDatabase(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'API-Quelle oben auswaehlen. Die Daten werden danach automatisch neu geladen.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isSyncing = appState.isWarehousesSyncing;
    final hasError = (appState.warehouseApiError ?? '').trim().isNotEmpty;
    final isConnected = !hasError && appState.warehouses.isNotEmpty;
    final periodFieldWidth = compact ? 180.0 : 200.0;
    final colorScheme = Theme.of(context).colorScheme;

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;
    if (isSyncing) {
      statusColor = colorScheme.primary;
      statusIcon = Icons.sync_rounded;
      statusText = context.tr('dbStatusLoading');
    } else if (isConnected) {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_outline_rounded;
      statusText = context.tr('dbStatusConnected');
    } else {
      statusColor = AppColors.warningDark;
      statusIcon = Icons.error_outline_rounded;
      statusText = context.tr('dbStatusError');
    }

    final statusBadge = Tooltip(
      message: statusText,
      waitDuration: const Duration(milliseconds: 250),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: isSyncing
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: statusColor,
                ),
              )
            : Icon(statusIcon, size: 16, color: statusColor),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        statusBadge,
        const SizedBox(width: 8),
        SizedBox(
          width: periodFieldWidth,
          child: DropdownButtonFormField<int>(
            initialValue: appState.dashboardKpiHorizonDays,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Zeitraum',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(value: 7, child: Text('7 Tage')),
              DropdownMenuItem<int>(value: 30, child: Text('30 Tage')),
              DropdownMenuItem<int>(value: 90, child: Text('90 Tage')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              appState.setDashboardKpiHorizonDays(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        compact
            ? IconButton(
                tooltip: isSyncing ? 'Daten werden geladen' : 'API Info',
                onPressed: isSyncing ? null : () => _pickDatabase(context),
                icon: isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open_rounded),
              )
            : OutlinedButton.icon(
                onPressed: isSyncing ? null : () => _pickDatabase(context),
                icon: isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.storage_outlined, size: 18),
                label: Text(
                  isSyncing
                      ? 'Laedt...'
                      : 'API Modus',
                ),
              ),
      ],
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
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.76)
              : colorScheme.surfaceContainerLowest.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.42)
                : colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
              : colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.45)
                : colorScheme.outlineVariant.withValues(alpha: 0.32),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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


