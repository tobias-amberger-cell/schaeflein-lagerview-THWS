import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/page_section_header.dart';
import '../widgets/create_warehouse_dialog.dart';
import '../widgets/warehouse_card.dart';

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  // Hält die Sucheingabe stabil über Rebuilds hinweg.
  final TextEditingController _searchController = TextEditingController();
  // Verhindert mehrfaches Zurückschreiben des initialen Suchwerts.
  bool _didSetInitialSearch = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didSetInitialSearch) {
      return;
    }
    _searchController.text = context.read<AppState>().warehouseSearchQuery;
    _didSetInitialSearch = true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Zentrale Datenquelle für die komplette Lager-UI.
    final appState = context.watch<AppState>();
    final warehouses = appState.warehouses;
    final filteredWarehouses = appState.filteredWarehouses;
    final selectedWarehouse = appState.selectedWarehouse;
    final selectedWarehouseId = appState.selectedWarehouse?.id;
    final hasFilters = appState.hasWarehouseFilters;
    final apiError = appState.warehouseApiError;
    final isSyncing = appState.isWarehousesSyncing;
    final onlineCount = filteredWarehouses
        .where((item) => item.status == WarehouseStatus.online)
        .length;
    final needsAttentionCount = filteredWarehouses
        .where((item) =>
            item.status == WarehouseStatus.limited ||
            item.status == WarehouseStatus.maintenance)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsives Raster für mobile, tablet und desktop.
        final columns =
            (constraints.maxWidth / 340).floor().clamp(1, 3).toInt();
        // Höhere Ratio => flachere, kompaktere Karten.
        final childAspectRatio = switch (columns) {
          1 => 1.18,
          2 => 1.08,
          _ => 1.0,
        };
        // Breites Web-Layout mit dichterem Informationsraster.
        final isWebWide = kIsWeb && constraints.maxWidth >= 1100;

        if (isWebWide) {
          // Je nach Breite werden 2 bis 5 Spalten verwendet.
          final webColumns =
              (constraints.maxWidth / 320).floor().clamp(2, 5).toInt();
          // Web hat eigene Kartenproportionen für kompaktere Darstellung.
          final webCardRatio = switch (webColumns) {
            2 => 1.12,
            3 => 1.04,
            4 => 0.98,
            _ => 0.94,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageSectionHeader(
                eyebrow: 'Standorte',
                title: context.tr('warehouseTitle'),
                subtitle: context.tr(
                  'warehousesCount',
                  <String, Object>{
                    'shown': filteredWarehouses.length,
                    'all': warehouses.length,
                  },
                ),
                badges: <Widget>[
                  _HeaderBadge(
                    icon: Icons.warehouse_outlined,
                    label: '${filteredWarehouses.length}/${warehouses.length}',
                  ),
                  _HeaderBadge(
                    icon: Icons.check_circle_outline,
                    label: '${context.tr('statusOnline')}: $onlineCount',
                  ),
                  _HeaderBadge(
                    icon: Icons.priority_high_rounded,
                    label: '${context.tr('badgeAttention')}: $needsAttentionCount',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Such-, Filter- und Aktionsbereich in einem kompakten Panel.
              _WarehousesControlPanel(
                appState: appState,
                searchController: _searchController,
                hasFilters: hasFilters,
                apiError: apiError,
                onlineCount: onlineCount,
                needsAttentionCount: needsAttentionCount,
                onCreate: () => _openCreateWarehouseDialog(context),
                onSync: isSyncing
                    ? null
                    : () => context.read<AppState>().syncWarehouses(),
                isSyncing: isSyncing,
                onClearFilters: _clearFilters,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (selectedWarehouse != null) ...<Widget>[
                // Zeigt das aktive Lager plus Schnellaktionen.
                _SelectedWarehouseBanner(
                  warehouse: selectedWarehouse,
                  onOpenViewer: () => _openWarehouse(context, selectedWarehouse),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              _SectionHeader(
                title: 'Lager auswaehlen',
                subtitle: context.tr(
                  'warehousesCount',
                  <String, Object>{
                    'shown': filteredWarehouses.length,
                    'all': warehouses.length,
                  },
                ),
                kicker: 'Standorte',
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: filteredWarehouses.isEmpty
                    // Leere Trefferliste: klarer Hinweis statt leerem Grid.
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: context.tr('noWarehousesFound'),
                        message: hasFilters
                            ? context.tr('adjustFilters')
                            : context.tr('noWarehouseData'),
                      )
                    : GridView.builder(
                        // Lazy Grid bleibt performant auch bei vielen Lagern.
                        itemCount: filteredWarehouses.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: webColumns,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: webCardRatio,
                        ),
                        itemBuilder: (context, index) {
                          final warehouse = filteredWarehouses[index];
                          final isFavorite =
                              appState.isFavoriteWarehouse(warehouse.id);
                          return WarehouseCard(
                            warehouse: warehouse,
                            isSelected: selectedWarehouseId == warehouse.id,
                            isFavorite: isFavorite,
                            onTap: () => _selectWarehouse(context, warehouse),
                            onSelect: () => _selectWarehouse(context, warehouse),
                            onOpenViewer: () => _openWarehouse(context, warehouse),
                            onToggleFavorite: () => _toggleFavorite(
                              context: context,
                              warehouse: warehouse,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        }

        return ListView(
          // Auf kleineren Ansichten bleibt der komplette Inhalt in einer Scroll-Achse.
          children: <Widget>[
            PageSectionHeader(
              eyebrow: 'Standorte',
              title: context.tr('warehouseTitle'),
              subtitle: context.tr(
                'warehousesCount',
                <String, Object>{
                  'shown': filteredWarehouses.length,
                  'all': warehouses.length,
                },
              ),
              badges: <Widget>[
                _HeaderBadge(
                  icon: Icons.warehouse_outlined,
                  label: '${filteredWarehouses.length}/${warehouses.length}',
                ),
                _HeaderBadge(
                  icon: Icons.check_circle_outline,
                  label: '${context.tr('statusOnline')}: $onlineCount',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const _SectionHeader(
              title: 'Lager auswaehlen',
              subtitle: 'Standort filtern und direkt als aktives Lager setzen',
              kicker: 'Auswahl',
            ),
            const SizedBox(height: AppSpacing.sm),
            _WarehousesControlPanel(
              appState: appState,
              searchController: _searchController,
              hasFilters: hasFilters,
              apiError: apiError,
              onlineCount: onlineCount,
              needsAttentionCount: needsAttentionCount,
              onCreate: () => _openCreateWarehouseDialog(context),
              onSync: isSyncing
                  ? null
                  : () => context.read<AppState>().syncWarehouses(),
              isSyncing: isSyncing,
              onClearFilters: _clearFilters,
            ),
            const SizedBox(height: AppSpacing.sm),
            _SectionHeader(
              title: 'Ergebnisse',
              subtitle: context.tr(
                'warehousesCount',
                <String, Object>{
                  'shown': filteredWarehouses.length,
                  'all': warehouses.length,
                },
              ),
              kicker: 'Standorte',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (selectedWarehouse != null) ...<Widget>[
              _SelectedWarehouseBanner(
                warehouse: selectedWarehouse,
                onOpenViewer: () => _openWarehouse(context, selectedWarehouse),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (filteredWarehouses.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                title: context.tr('noWarehousesFound'),
                message: hasFilters
                    ? context.tr('adjustFilters')
                    : context.tr('noWarehouseData'),
              )
            else
              GridView.builder(
                // Verschachteltes Grid scrollt nicht separat, nur die äußere Liste.
                itemCount: filteredWarehouses.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: childAspectRatio,
                ),
                itemBuilder: (context, index) {
                  final warehouse = filteredWarehouses[index];
                  final isFavorite =
                      appState.isFavoriteWarehouse(warehouse.id);
                  return WarehouseCard(
                    warehouse: warehouse,
                    isSelected: selectedWarehouseId == warehouse.id,
                    isFavorite: isFavorite,
                    onTap: () => _selectWarehouse(context, warehouse),
                    onSelect: () => _selectWarehouse(context, warehouse),
                    onOpenViewer: () => _openWarehouse(context, warehouse),
                    onToggleFavorite: () => _toggleFavorite(
                      context: context,
                      warehouse: warehouse,
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  void _clearFilters() {
    // UI-Suche und State-Filter immer gemeinsam resetten.
    _searchController.clear();
    context.read<AppState>().clearWarehouseFilters();
  }

  Future<void> _openCreateWarehouseDialog(BuildContext context) async {
    // Zugriffsschutz vor dem Öffnen des Dialogs.
    final appState = context.read<AppState>();
    if (!appState.canManageWarehouses) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('warehouseCreateNoPermission')),
        ),
      );
      return;
    }
    final input = await showCreateWarehouseDialog(context);
    // Kein weiterer Ablauf bei Abbruch oder unmounted Context.
    if (!context.mounted || input == null) {
      return;
    }
    final created = await appState.createWarehouse(
      name: input.name,
      location: input.location,
      status: input.status,
      description: input.description,
      lengthM: input.lengthM,
      widthM: input.widthM,
      heightM: input.heightM,
      rackRowCount: input.rackRowCount,
      rackLengthM: input.rackLengthM,
      rackWidthM: input.rackWidthM,
      rackLevels: input.rackLevels,
      aisleWidthM: input.aisleWidthM,
      zoneNames: input.zoneNames,
    );
    if (!context.mounted) {
      return;
    }
    if (!created) {
      // API-Fehler priorisiert anzeigen, falls vorhanden.
      final apiError = appState.warehouseApiError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(apiError ?? context.tr('warehouseCreateFailed')),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'warehouseCreatedMsg',
            <String, Object>{'name': input.name},
          ),
        ),
      ),
    );
    context.go('/viewer');
  }

  void _openWarehouse(BuildContext context, Warehouse warehouse) {
    // Lager aktiv setzen und direkt in den Viewer wechseln.
    context.read<AppState>().selectWarehouse(warehouse);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('selectedWarehouseMsg', <String, Object>{'name': warehouse.name}),
        ),
      ),
    );
    context.go('/viewer');
  }

  void _selectWarehouse(BuildContext context, Warehouse warehouse) {
    // Nur aktiv setzen, ohne Seitenwechsel.
    context.read<AppState>().selectWarehouse(warehouse);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('selectedWarehouseMsg', <String, Object>{'name': warehouse.name}),
        ),
      ),
    );
  }

  void _toggleFavorite({
    required BuildContext context,
    required Warehouse warehouse,
    bool showFeedback = true,
  }) {
    // Favoriten sind rollenabhängig und können gesperrt sein.
    final appState = context.read<AppState>();
    if (!appState.canToggleFavorites) {
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('viewerRoleNoFavorites')),
          ),
        );
      }
      return;
    }
    final wasFavorite = appState.isFavoriteWarehouse(warehouse.id);
    // Toggle kann fehlschlagen, deshalb Ergebnis explizit prüfen.
    final changed = appState.toggleFavoriteWarehouse(warehouse.id);
    if (!changed) {
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('viewerRoleNoFavorites')),
          ),
        );
      }
      return;
    }
    if (!showFeedback) {
      return;
    }
    final message = wasFavorite
        ? context.tr('favoriteRemovedMsg', <String, Object>{'name': warehouse.name})
        : context.tr('favoriteAddedMsg', <String, Object>{'name': warehouse.name});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.kicker,
  });

  final String title;
  final String? subtitle;
  final String? kicker;

  @override
  Widget build(BuildContext context) {
    // Leichter, wiederverwendbarer Abschnittsheader mit optionalem Kicker.
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (kicker != null) ...<Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                kicker!.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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

class _WarehousesControlPanel extends StatelessWidget {
  const _WarehousesControlPanel({
    required this.appState,
    required this.searchController,
    required this.hasFilters,
    required this.apiError,
    required this.onlineCount,
    required this.needsAttentionCount,
    required this.onCreate,
    required this.onSync,
    required this.isSyncing,
    required this.onClearFilters,
  });

  final AppState appState;
  final TextEditingController searchController;
  final bool hasFilters;
  final String? apiError;
  final int onlineCount;
  final int needsAttentionCount;
  final VoidCallback onCreate;
  final VoidCallback? onSync;
  final bool isSyncing;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    // Zentrale Steuerbox: Suche, Filter, Kennzahlen und Aktionen.
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surfaceContainerLowest,
            colorScheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.tune_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Suche und Steuerung',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Filtere Standorte nach Name und Status, aktualisiere Daten und lege neue Lager an.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: searchController,
              // Suche direkt in den AppState zurückschreiben.
              onChanged: (value) =>
                  appState.setWarehouseSearchQuery(value.trim()),
              decoration: InputDecoration(
                hintText: context.tr('searchHint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: appState.warehouseSearchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          searchController.clear();
                          appState.setWarehouseSearchQuery('');
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              // Status-Chips als primärer Schnellfilter.
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                ChoiceChip(
                  label: Text(context.tr('all')),
                  selected: appState.warehouseStatusFilter == null,
                  onSelected: (_) {
                    appState.setWarehouseStatusFilter(null);
                  },
                ),
                ...WarehouseStatus.values.map(
                  (status) => ChoiceChip(
                    label: Text(context.tr(status.labelKey)),
                    selected: appState.warehouseStatusFilter == status,
                    onSelected: (_) {
                      appState.setWarehouseStatusFilter(status);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _FilterSummary(
              query: appState.warehouseSearchQuery,
              status: appState.warehouseStatusFilter,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                _HeaderBadge(
                  icon: Icons.check_circle_outline,
                  label: '${context.tr('statusOnline')}: $onlineCount',
                ),
                _HeaderBadge(
                  icon: Icons.priority_high_rounded,
                  label: '${context.tr('badgeAttention')}: $needsAttentionCount',
                ),
              ],
            ),
            if (hasFilters) ...<Widget>[
              // Reset-Aktion nur anzeigen, wenn auch wirklich Filter aktiv sind.
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: Text(context.tr('filtersReset')),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              // Primäraktionen für diese Seite.
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(context.tr('createWarehouse')),
                ),
                OutlinedButton.icon(
                  onPressed: onSync,
                  icon: Icon(isSyncing ? Icons.sync : Icons.sync_outlined),
                  label: Text(context.tr('warehousesSyncAction')),
                ),
              ],
            ),
            if (apiError != null) ...<Widget>[
              // API-Fehler im Kontext des Sync-Bereichs sichtbar halten.
              const SizedBox(height: AppSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    context.tr(
                      'warehousesSyncError',
                      <String, Object>{'error': apiError!},
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterSummary extends StatelessWidget {
  const _FilterSummary({
    required this.query,
    required this.status,
  });

  final String query;
  final WarehouseStatus? status;

  @override
  Widget build(BuildContext context) {
    // Kurztext für den aktuell aktiven Filterzustand.
    String label;
    final statusValue = status;
    if (query.isNotEmpty && statusValue != null) {
      label = context.tr(
        'searchFilterSummaryBoth',
        <String, Object>{
          'query': query,
          'status': context.tr(statusValue.labelKey),
        },
      );
    } else if (query.isNotEmpty) {
      label = context.tr(
        'searchFilterSummaryQuery',
        <String, Object>{'query': query},
      );
    } else if (statusValue != null) {
      label = context.tr(
        'searchFilterSummaryStatus',
        <String, Object>{'status': context.tr(statusValue.labelKey)},
      );
    } else {
      label = context.tr('noFiltersActive');
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
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
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedWarehouseBanner extends StatelessWidget {
  const _SelectedWarehouseBanner({
    required this.warehouse,
    required this.onOpenViewer,
  });

  final Warehouse warehouse;
  final VoidCallback onOpenViewer;

  @override
  Widget build(BuildContext context) {
    // Das aktuell aktive Lager inkl. schneller Folgeaktionen.
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;
        final actions = Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.end,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onOpenViewer,
              icon: const Icon(Icons.view_in_ar_outlined, size: 16),
              label: const Text('3D'),
            ),
          ],
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.check_circle_outline,
                              color: colorScheme.primary, size: 18),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Aktives Lager',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  warehouse.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      actions,
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Icon(Icons.check_circle_outline,
                          color: colorScheme.primary, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Aktives Lager',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              warehouse.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  Theme.of(context).textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      actions,
                    ],
                  ),
          ),
        );
      },
    );
  }
}
