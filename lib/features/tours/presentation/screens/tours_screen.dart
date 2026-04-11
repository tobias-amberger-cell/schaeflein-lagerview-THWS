import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/tour.dart';
import '../../../../models/warehouse.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/page_section_header.dart';

class ToursScreen extends StatefulWidget {
  const ToursScreen({super.key});

  @override
  State<ToursScreen> createState() => _ToursScreenState();
}

class _ToursScreenState extends State<ToursScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _didInitSearch = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitSearch) {
      return;
    }
    _searchController.text = context.read<AppState>().tourSearchQuery;
    _didInitSearch = true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tours = appState.filteredTours;
    final hasFilters = appState.hasTourFilters;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= AppBreakpoints.desktop
            ? 3
            : constraints.maxWidth >= AppBreakpoints.tablet
                ? 2
                : 1;
        final tileWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (AppSpacing.md * (columns - 1))) / columns;
        final estimatedHeight = columns == 1 ? 340.0 : 360.0;
        final rawAspectRatio = tileWidth / estimatedHeight;
        final childAspectRatio = rawAspectRatio < 0.85
            ? 0.85
            : rawAspectRatio > 1.9
                ? 1.9
                : rawAspectRatio;

        return ListView(
          children: <Widget>[
            PageSectionHeader(
              title: context.tr('toursTitle'),
              subtitle: context.tr(
                'toursCount',
                <String, Object>{
                  'shown': tours.length,
                  'all': appState.tours.length,
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ToursHeroPanel(
              activeTours: appState.activeToursCount,
              delayedTours: appState.delayedToursCount,
              completedTours: appState.completedToursCount,
              onOpenControlTower: () => context.go('/control-tower'),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _KpiPill(
                  icon: Icons.local_shipping_outlined,
                  label: context.tr('tourKpiActive'),
                  value: '${appState.activeToursCount}',
                ),
                _KpiPill(
                  icon: Icons.warning_amber_outlined,
                  label: context.tr('tourKpiDelayed'),
                  value: '${appState.delayedToursCount}',
                  highlight: appState.delayedToursCount > 0,
                ),
                _KpiPill(
                  icon: Icons.task_alt_outlined,
                  label: context.tr('tourKpiCompleted'),
                  value: '${appState.completedToursCount}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => appState.setTourSearchQuery(value.trim()),
                      decoration: InputDecoration(
                        hintText: context.tr('tourSearchHint'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: appState.tourSearchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  appState.setTourSearchQuery('');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        ChoiceChip(
                          label: Text(context.tr('all')),
                          selected: appState.tourStatusFilter == null,
                          onSelected: (_) => appState.setTourStatusFilter(null),
                        ),
                        ...TourStatus.values.map(
                          (status) => ChoiceChip(
                            label: Text(context.tr(status.labelKey)),
                            selected: appState.tourStatusFilter == status,
                            onSelected: (_) => appState.setTourStatusFilter(status),
                          ),
                        ),
                      ],
                    ),
                    if (hasFilters) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            appState.clearTourFilters();
                          },
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: Text(context.tr('filtersReset')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (tours.isEmpty)
              EmptyState(
                icon: Icons.route_outlined,
                title: context.tr('noToursFound'),
                message: hasFilters
                    ? context.tr('adjustFilters')
                    : context.tr('noToursData'),
              )
            else
              GridView.builder(
                itemCount: tours.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: childAspectRatio,
                ),
                itemBuilder: (context, index) {
                  final tour = tours[index];
                  final warehouse = appState.getWarehouseById(tour.warehouseId);
                  return _TourCard(
                    tour: tour,
                    warehouse: warehouse,
                    onOpenWarehouse: warehouse == null
                        ? null
                        : () => context.go('/warehouses/${warehouse.id}'),
                    onOpenViewer: warehouse == null
                        ? null
                        : () {
                            appState.selectWarehouse(warehouse);
                            context.go('/viewer');
                          },
                    onShowStops: () => _showStopsBottomSheet(context, tour),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _showStopsBottomSheet(BuildContext context, TransportTour tour) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TourStopsSheet(tour: tour),
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.tour,
    required this.warehouse,
    required this.onShowStops,
    this.onOpenWarehouse,
    this.onOpenViewer,
  });

  final TransportTour tour;
  final Warehouse? warehouse;
  final VoidCallback onShowStops;
  final VoidCallback? onOpenWarehouse;
  final VoidCallback? onOpenViewer;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(tour.status);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: statusColor.withValues(alpha: 0.24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              statusColor.withValues(alpha: 0.08),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      tour.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 2,
                      ),
                      child: Text(
                        context.tr(tour.status.labelKey),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${tour.vehicleCode} | ${tour.driverName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                warehouse?.name ?? context.tr('warehouseNotFound'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 9,
                  value: tour.progressRatio.clamp(0, 1).toDouble(),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr(
                  'tourProgressLine',
                  <String, Object>{
                    'percent': tour.progressPercent,
                    'completed': tour.completedStops,
                    'total': tour.stopCount,
                  },
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr(
                  'tourLoadLine',
                  <String, Object>{
                    'load': tour.loadFactorPercent,
                    'eta': _formatTime(tour.estimatedArrival),
                  },
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.end,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: onShowStops,
                    icon: const Icon(Icons.route_outlined),
                    label: Text(context.tr('tourStopsAction')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onOpenWarehouse,
                    icon: const Icon(Icons.warehouse_outlined),
                    label: Text(context.tr('warehouseAction')),
                  ),
                  FilledButton.icon(
                    onPressed: onOpenViewer,
                    icon: const Icon(Icons.view_in_ar_outlined),
                    label: Text(context.tr('open3d')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Color _statusColor(TourStatus status) {
    switch (status) {
      case TourStatus.planned:
        return Colors.blue.shade700;
      case TourStatus.loading:
        return Colors.indigo.shade700;
      case TourStatus.inTransit:
        return Colors.green.shade700;
      case TourStatus.delayed:
        return Colors.orange.shade800;
      case TourStatus.completed:
        return Colors.teal.shade700;
    }
  }
}

class _TourStopsSheet extends StatelessWidget {
  const _TourStopsSheet({required this.tour});

  final TransportTour tour;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr(
                'tourStopsTitle',
                <String, Object>{'code': tour.code},
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr(
                'tourStopsSubtitle',
                <String, Object>{'count': tour.stopCount},
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: maxHeight,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: tour.stops.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final stop = tour.stops[index];
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(stop.name),
                      subtitle: Text(
                        '${stop.address}\n${context.tr('tourStopEta')}: ${_formatDateTime(stop.plannedArrival)}',
                      ),
                      isThreeLine: true,
                      trailing: Text(context.tr(stop.status.labelKey)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month. $hour:$minute';
  }
}

class _KpiPill extends StatelessWidget {
  const _KpiPill({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = highlight
        ? Colors.orange.withValues(alpha: 0.14)
        : colorScheme.surface.withValues(alpha: 0.88);
    final foreground = highlight ? Colors.orange.shade800 : colorScheme.onSurface;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 126, maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
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
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      value,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: foreground,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToursHeroPanel extends StatelessWidget {
  const _ToursHeroPanel({
    required this.activeTours,
    required this.delayedTours,
    required this.completedTours,
    required this.onOpenControlTower,
  });

  final int activeTours;
  final int delayedTours;
  final int completedTours;
  final VoidCallback onOpenControlTower;

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
            colorScheme.primary.withValues(alpha: 0.14),
            colorScheme.tertiary.withValues(alpha: 0.1),
            colorScheme.surface,
          ],
        ),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _HeroTourChip(
                  icon: Icons.local_shipping_outlined,
                  label: context.tr('tourKpiActive'),
                  value: '$activeTours',
                ),
                _HeroTourChip(
                  icon: Icons.warning_amber_outlined,
                  label: context.tr('tourKpiDelayed'),
                  value: '$delayedTours',
                ),
                _HeroTourChip(
                  icon: Icons.task_alt_outlined,
                  label: context.tr('tourKpiCompleted'),
                  value: '$completedTours',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: onOpenControlTower,
              icon: const Icon(Icons.hub_outlined),
              label: Text(context.tr('openControlTower')),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTourChip extends StatelessWidget {
  const _HeroTourChip({
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 124, maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.86),
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
              Expanded(
                child: Column(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
