import 'dart:async';
import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../shared/widgets/app_flat_data_table.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/order_volume_point.dart';
import '../../../../models/pick_activity_heatmap.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse.dart';
import '../../../../models/warehouse_trend.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/dashboard_helpers.dart';
import '../widgets/order_volume_card.dart';
import '../widgets/pick_activity_heatmap_card.dart';
import '../widgets/abc_adjustment_panel.dart';
import '../widgets/floor_replenishment_panel.dart';
import '../widgets/putaway_candidates_panel.dart';
import '../widgets/relocation_candidates_panel.dart';
import '../widgets/retrieval_candidates_panel.dart';
import '../widgets/replenishment_candidates_panel.dart';
import '../../../viewer/presentation/widgets/glb_3d_viewer.dart';

double _resolveWrapItemWidth({
  required double maxWidth,
  required int columns,
  required double spacing,
}) {
  // Defensive Berechnung fÃƒÂ¼r Wrap-Kartenbreiten:
  // verhindert ungÃƒÂ¼ltige Werte bei sehr kleinen oder unendlichen Constraints.
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return 1;
  }
  final safeColumns = columns < 1 ? 1 : columns;
  final spacingTotal = spacing * (safeColumns - 1);
  final availableWidth = maxWidth - spacingTotal;
  if (!availableWidth.isFinite || availableWidth <= 0) {
    return maxWidth;
  }
  final rawWidth = availableWidth / safeColumns;
  if (!rawWidth.isFinite || rawWidth <= 0) {
    return maxWidth;
  }
  return rawWidth.clamp(1.0, maxWidth).toDouble();
}

String _deEn(
  BuildContext context, {
  required String de,
  required String en,
}) {
  return Localizations.localeOf(context).languageCode == 'en' ? en : de;
}

String _hallForRackNumber(int rackNumber) {
  if (rackNumber >= 1 && rackNumber <= 16) {
    return 'Halle 1';
  }
  if (rackNumber >= 17 && rackNumber <= 32) {
    return 'Halle 2';
  }
  return 'Halle 3';
}

bool _isOccupiedStorageStatus(String rawStatus) {
  final value = rawStatus.trim().toLowerCase();
  return value == 'belegt' ||
      value == 'occupied' ||
      value == 'voll' ||
      value == 'full' ||
      value.contains('belegt') ||
      value.contains('occupied') ||
      value.contains('voll') ||
      value.contains('full');
}

List<WarehouseStorageLocation> _applyDashboardStorageFilters({
  required List<WarehouseStorageLocation> samples,
  required AppState appState,
  required Warehouse? warehouse,
}) {
  if (samples.isEmpty) {
    return samples;
  }
  final minUtil = appState.dashboardUtilizationFilterMin;
  final maxUtil = appState.dashboardUtilizationFilterMax;
  if (warehouse != null &&
      (minUtil > 0 || maxUtil < 150) &&
      (warehouse.utilizationPercent < minUtil ||
          warehouse.utilizationPercent > maxUtil)) {
    return const <WarehouseStorageLocation>[];
  }

  final selectedHalls = appState.dashboardSelectedHalls;
  final selectedAbc = appState.dashboardSelectedAbcClasses;
  final onlyOccupied = appState.dashboardOnlyOccupied;
  return samples.where((sample) {
    if (selectedHalls.isNotEmpty &&
        !selectedHalls.contains(_hallForRackNumber(sample.rackNumber))) {
      return false;
    }
    final abc = sample.abcClass.trim().toUpperCase();
    if (selectedAbc.isNotEmpty && !selectedAbc.contains(abc)) {
      return false;
    }
    if (onlyOccupied && !_isOccupiedStorageStatus(sample.status)) {
      return false;
    }
    return true;
  }).toList(growable: false);
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  // Schwelle fÃƒÂ¼r "Ladenhueter" bzw. Slow-Mover-Logik.
  static const int _slowMoverDaysThreshold = 90;
  static const int _slowMoverStaleDaysThreshold = 120;
  static const int _slowMoverCriticalDaysThreshold = 180;

  AbcAnalysis? _deriveAbcForDisplay(Warehouse? warehouse) {
    // Falls keine belastbare ABC-Analyse vorliegt, erzeugen wir eine
    // sinnvolle NÃƒÂ¤herung aus der Artikelanzahl (20/30/50), um UI-LÃƒÂ¼cken zu vermeiden.
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

  List<WarehouseStorageLocation> _slowMoverSamples(
    List<WarehouseStorageLocation> samples, {
    int minDays = _slowMoverDaysThreshold,
  }) {
    // Nach InaktivitÃƒÂ¤t filtern und dann nach Relevanz sortieren:
    // 1) lÃƒÂ¤ngste InaktivitÃƒÂ¤t, 2) geringste Bewegungen, 3) Code.
    final filtered = samples
        .where((sample) => (sample.daysSinceMovement ?? -1) >= minDays)
        .toList(growable: false);
    final sorted = [...filtered]
      ..sort((a, b) {
        final byDays = (b.daysSinceMovement ?? 0).compareTo(
          a.daysSinceMovement ?? 0,
        );
        if (byDays != 0) {
          return byDays;
        }
        final byMoves = (a.movements30d ?? 0).compareTo(b.movements30d ?? 0);
        if (byMoves != 0) {
          return byMoves;
        }
        return a.displayCode.compareTo(b.displayCode);
      });
    return sorted;
  }

  int _slowMoverArticleCount(List<WarehouseStorageLocation> samples) {
    // ZÃƒÂ¤hlt eindeutige Artikel, nicht reine Lagerpositionen.
    final articleIds = <String>{};
    for (final sample in samples) {
      final id = sample.articleId.trim();
      if (id.isNotEmpty) {
        articleIds.add(id);
      }
    }
    return articleIds.length;
  }

  @override
  Widget build(BuildContext context) {
    // Alle Header-/KPI-Daten kommen zentral aus dem AppState.
    final appState = context.watch<AppState>();
    final warehouse = appState.riskFocusWarehouse;
    if (warehouse != null) {
      unawaited(
        appState.ensureStorageLocationsLoadedForWarehouse(
          warehouse.id,
          limit: 120,
        ),
      );
      unawaited(
        appState.ensureOrderVolumeTrendLoaded(
          days: appState.dashboardKpiHorizonDays,
        ),
      );
      unawaited(appState.ensurePickActivityHeatmapLoaded());
      unawaited(appState.ensureRelocationCandidatesLoaded());
      unawaited(appState.ensureReplenishmentCandidatesLoaded());
      unawaited(
        appState.ensureAbcArticlesLoadedForWarehouse(
          warehouseId: warehouse.id,
          limit: 100000,
        ),
      );
      // Slot-Daten (inkl. MAX_LHM / IST_LHM / FREE_CAPACITY) auch ausserhalb
      // des ABC-Tabs vorladen, damit Free Capacity / Smart Relocation direkt
      // gefuellt sind.
      unawaited(
        appState.ensureAbcSlotsLoadedForWarehouse(
          warehouseId: warehouse.id,
          limit: 20000,
        ),
      );
    }
    final operationsProfile = warehouse == null
        ? null
        : appState.getOperationsProfile(warehouse.id);
    final utilization = warehouse?.utilizationPercent ?? 0;
    final abc = _deriveAbcForDisplay(warehouse);
    final heatmapMetric = appState.viewerHeatmapMetric;
    final topZones = topHeatmapZones(
      appState.viewerHeatmapData,
      heatmapMetric,
      maxItems: 6,
    );
    return _buildMainColumn(
      context,
      appState: appState,
      warehouse: warehouse,
      operationsProfile: operationsProfile,
      utilization: utilization,
      abc: abc,
      topZones: topZones,
    );
  }

  Widget _buildMainColumn(
    BuildContext context, {
    required AppState appState,
    required Warehouse? warehouse,
    required int utilization,
    required AbcAnalysis? abc,
    required operationsProfile,
    required List<ViewerHeatmapEntry> topZones,
  }) {
    // Werte einmal zentral vorbereiten, damit Karten/Widgets nur noch rendern.
    final baseTotalSlots = warehouse?.totalStorageSlots ?? 0;
    final baseOccupiedSlots = warehouse?.occupiedStorageSlots ?? 0;
    final slaCurrent = operationsProfile?.slaCurrentPercent ?? 0;
    final slaTarget = operationsProfile?.slaTargetPercent ?? 0;
    final pickRate = warehouse?.pickRatePerHour ?? 0;
    final dockUtilization = operationsProfile == null
        ? null
        : (operationsProfile.dockUtilizationRatio * 100).round();
    final inboundVsOutbound = warehouse == null
        ? null
        : warehouse.inboundPerDay - warehouse.throughputPerDay;
    final qualityHolds = operationsProfile?.qualityHolds;
    final allStorageSamples = warehouse == null
        ? const <WarehouseStorageLocation>[]
        : appState.getStorageLocationsForWarehouse(warehouse.id);
    final storageSamples = _applyDashboardStorageFilters(
      samples: allStorageSamples,
      appState: appState,
      warehouse: warehouse,
    );
    final hasActiveDashboardFilters =
        appState.hasDashboardStorageFilters ||
        appState.hasDashboardUtilizationFilter;
    final filteredTotalSlots = hasActiveDashboardFilters &&
            allStorageSamples.isNotEmpty
        ? storageSamples.length
        : baseTotalSlots;
    final filteredOccupiedSlots = hasActiveDashboardFilters &&
            allStorageSamples.isNotEmpty
        ? storageSamples.where((sample) => _isOccupiedStorageStatus(sample.status)).length
        : baseOccupiedSlots;
    final filteredFreeSlots = (filteredTotalSlots - filteredOccupiedSlots)
        .clamp(0, filteredTotalSlots)
        .toInt();
    final filteredUtilization = filteredTotalSlots <= 0
        ? 0
        : ((filteredOccupiedSlots / filteredTotalSlots) * 100).round();
    final slowMoverSamples = _slowMoverSamples(storageSamples);
    final slowMoverPositions = slowMoverSamples.length;
    final slowMoverArticles = _slowMoverArticleCount(slowMoverSamples);
    final slowMoverMaxIdleDays = slowMoverSamples.isEmpty
        ? null
        : (slowMoverSamples.first.daysSinceMovement ?? 0);
    final slowMoverSharePercent = filteredTotalSlots <= 0
        ? null
        : ((slowMoverPositions / filteredTotalSlots) * 100).round();
    final hasSlaRisk = operationsProfile != null && slaCurrent < slaTarget;
    final hasCapacityRisk = filteredUtilization >= 85;
    final hasSlowMovers = slowMoverPositions > 0;
    final hasCongestionRisk = topZones.any(
      (zone) => zone.valueFor(ViewerHeatmapMetric.congestion) >= 0.75,
    );
    final hasInboundBacklog =
        inboundVsOutbound != null && inboundVsOutbound > 120;
    final hasHighPickLoad = pickRate >= 550;
    bool isFreeStatus(WarehouseStorageLocation candidate) {
      final value = candidate.status.trim().toLowerCase();
      return value == 'frei' ||
          value == 'free' ||
          value == 'leer' ||
          value.contains('frei') ||
          value.contains('free');
    }

    bool isBlockedStatus(WarehouseStorageLocation candidate) {
      final value = candidate.status.trim().toLowerCase();
      return value == 'gesperrt' ||
          value == 'blocked' ||
          value.contains('sperr') ||
          value.contains('block');
    }

    const putawayFloorLevelThreshold = 2;
    const putawayReserveLevelThreshold = 3;
    final putawayFreeSlots = storageSamples
        .where(isFreeStatus)
        .toList(growable: false);
    final putawayFastLaneSlots = putawayFreeSlots
        .where(
          (candidate) =>
              (candidate.abcClass == 'A' || candidate.abcClass == 'B') &&
              candidate.levelNumber <= putawayFloorLevelThreshold,
        )
        .toList(growable: false)
      ..sort(
        (a, b) =>
            a.levelNumber != b.levelNumber
                ? a.levelNumber.compareTo(b.levelNumber)
                : a.displayCode.compareTo(b.displayCode),
      );
    final putawayReserveSlots = putawayFreeSlots
        .where(
          (candidate) =>
              candidate.abcClass == 'C' &&
              candidate.levelNumber >= putawayReserveLevelThreshold,
        )
        .toList(growable: false)
      ..sort(
        (a, b) =>
            a.levelNumber != b.levelNumber
                ? b.levelNumber.compareTo(a.levelNumber)
                : a.displayCode.compareTo(b.displayCode),
      );
    final putawayBlockedSlots = storageSamples
        .where(isBlockedStatus)
        .toList(growable: false)
      ..sort((a, b) => a.displayCode.compareTo(b.displayCode));
    final putawayCandidateCount =
        putawayFastLaneSlots.length + putawayReserveSlots.length;
    final hasPutawaySignals =
        hasInboundBacklog ||
            putawayBlockedSlots.isNotEmpty ||
            (hasInboundBacklog && putawayFastLaneSlots.isEmpty);
    final replenishmentForFloor = appState.replenishmentCandidates;
    const floorLevelThreshold = 1;
    final floorUrgentCandidates = replenishmentForFloor.urgentPlaces
        .where((candidate) => candidate.levelNumber <= floorLevelThreshold)
        .toList(growable: false);
    final floorOverdueCandidates = replenishmentForFloor.overduePlaces
        .where((candidate) => candidate.levelNumber <= floorLevelThreshold)
        .toList(growable: false);
    final floorMediumCandidates = replenishmentForFloor.mediumPlaces
        .where((candidate) => candidate.levelNumber <= floorLevelThreshold)
        .toList(growable: false);
    final floorCandidateCount = floorUrgentCandidates.length +
        floorOverdueCandidates.length +
        floorMediumCandidates.length;
    final hasFloorSignals =
        floorUrgentCandidates.isNotEmpty ||
            floorOverdueCandidates.isNotEmpty ||
            hasSlaRisk ||
            hasHighPickLoad;
    final cShareRatio = (abc == null || abc.total <= 0)
        ? null
        : (abc.cCount / abc.total);
    final abcArticles = warehouse == null
        ? const <WarehouseAbcArticleSummary>[]
        : appState.getAbcArticlesForWarehouse(warehouse.id);
    const abcPromotePickThreshold = 35;
    const abcDemotePickThreshold = 8;
    const abcDemoteIdleDaysThreshold = 90;
    final abcPromoteCandidates = abcArticles
        .where(
          (entry) =>
              entry.abcClass.trim().toUpperCase() == 'C' &&
              entry.movements30d >= abcPromotePickThreshold,
        )
        .toList(growable: false);
    final abcDemoteCandidates = abcArticles
        .where(
          (entry) =>
              entry.abcClass.trim().toUpperCase() == 'A' &&
              (entry.movements30d <= abcDemotePickThreshold ||
                  entry.maxIdleDays >= abcDemoteIdleDaysThreshold),
        )
        .toList(growable: false);
    final abcReviewCandidates = abcArticles
        .where(
          (entry) =>
              entry.abcClass.trim().toUpperCase() == 'B' &&
              (entry.movements30d >= abcPromotePickThreshold ||
                  entry.maxIdleDays >= abcDemoteIdleDaysThreshold),
        )
        .toList(growable: false);
    final abcCandidateCount = abcPromoteCandidates.length + abcDemoteCandidates.length;
    final hasAbcActionSignals =
        (cShareRatio ?? 0) >= 0.55 || abcCandidateCount > 0;
    final openSlowMoverDetails = warehouse == null
        ? null
        : () {
            // Ãƒâ€“ffnet Lager-Detailansicht mit vorbelegtem Idle-Day-Filter.
            appState.selectWarehouse(warehouse);
            appState.setViewerHeatmapMetric(ViewerHeatmapMetric.utilization);
            appState.setViewerHeatmapVisible(true);
            context.go('/viewer');
          };
    final openWarehouseDetails = warehouse == null
        ? null
        : () {
            appState.selectWarehouse(warehouse);
            context.go('/viewer');
          };

    final actionItems = <_OperationalActionItem>[
      () {
        final relocation = appState.relocationCandidates;
        final hasRelocationData = !relocation.isEmpty;
        final relocateRecommended =
            hasCapacityRisk || hasCongestionRisk || relocation.hotC > 0;
        final reasonParts = <String>[];
        if (hasCapacityRisk || hasCongestionRisk) {
          reasonParts.add(context.tr('umlagernReasonCapacity'));
        }
        if (relocation.hotC > 0) {
          reasonParts.add(
            context.tr('umlagernReasonHotC', <String, Object>{
              'n': relocation.hotC,
              'threshold': relocation.highPickThreshold,
            }),
          );
        }
        if (relocation.unusedA > 0) {
          reasonParts.add(
            context.tr('umlagernReasonUnusedA', <String, Object>{
              'n': relocation.unusedA,
            }),
          );
        }
        final reason = reasonParts.isEmpty
            ? context.tr('umlagernReasonOk')
            : context.tr('umlagernReasonRecommended', <String, Object>{
                'parts': reasonParts.join(' - '),
              });

        return _OperationalActionItem(
          id: 'relocate',
          title: _deEn(context, de: 'Umlagern', en: 'Relocate'),
          description:
              _deEn(
                context,
                de: 'Belegte Bereiche entlasten und Pickwege stabilisieren.',
                en: 'Relieve overloaded areas and stabilize picking routes.',
              ),
          explanation: _deEn(
            context,
            de: 'Diese Aktion verschiebt stark genutzte Artikel in besser erreichbare Bereiche und entzerrt Engpaesse. Ziel ist weniger Wegzeit pro Pick und ein gleichmaessigerer Materialfluss.',
            en: 'This action moves heavily picked items to better-accessible areas and reduces bottlenecks. The goal is lower travel time per pick and smoother material flow.',
          ),
          whenToRun: _deEn(
            context,
            de: 'Wenn Auslastung/Stau hoch ist oder Pick-Hotspots haeufig eskalieren.',
            en: 'When utilization/congestion is high or pick hotspots escalate frequently.',
          ),
          whatHappens: _deEn(
            context,
            de: 'Das System priorisiert konkrete Umlager-Kandidaten und fokussiert sie im Viewer.',
            en: 'The system prioritizes concrete relocation candidates and focuses them in the viewer.',
          ),
          detailPoints: <String>[
            _deEn(
              context,
              de: 'WMS-Zonen mit hoher Auslastung und Stau priorisieren.',
              en: 'Prioritize WMS zones with high utilization and congestion.',
            ),
            _deEn(
              context,
              de: 'Artikel mit hoher Pickfrequenz naeher an Kommissionierpunkten platzieren.',
              en: 'Move high-pick items closer to picking points.',
            ),
            _deEn(
              context,
              de: '3D-Heatmap fuer Engpassflaechen und Wegeabgleich nutzen.',
              en: 'Use the 3D heatmap to validate bottlenecks and routes.',
            ),
          ],
          checklist: <String>[
            _deEn(
              context,
              de: 'Hotspots aus Heatmap pruefen (Stau/Auslastung).',
              en: 'Review heatmap hotspots first (congestion/utilization).',
            ),
            _deEn(
              context,
              de: 'Nur A/B-Artikel mit hoher Pickfrequenz zuerst bewegen.',
              en: 'Move high-pick A/B items first.',
            ),
            _deEn(
              context,
              de: 'Zielflaechen vorab auf freie Kapazitaet pruefen.',
              en: 'Validate free capacity in target zones before moving.',
            ),
            _deEn(
              context,
              de: 'Umlagerung in kleinen Wellen statt Komplettumbau fahren.',
              en: 'Run relocations in small waves, not one big bang.',
            ),
            _deEn(
              context,
              de: 'Nach jeder Welle KPI-Check: Picks/h, Wegzeit, Fehlerquote.',
              en: 'After each wave, check KPIs: picks/h, travel time, error rate.',
            ),
          ],
          reason: reason,
          recommended: relocateRecommended,
          icon: Icons.swap_horiz_rounded,
          onExecute: warehouse == null
              ? null
              : () => appState.ensureRelocationCandidatesLoaded(
                    force: true,
                    limit: 24,
                  ),
          executeLabel: _deEn(context, de: 'Umlagerung starten', en: 'Start relocation'),
          executeDoneLabel: _deEn(context, de: 'Umlagerung geplant', en: 'Relocation planned'),
          executeSummary: relocation.total > 0
              ? _deEn(
                  context,
                  de: 'Priorisiert ${relocation.hotC} Hot-C, ${relocation.highLevelA} High-Level-A und ${relocation.unusedA} ungenutzte A-Plaetze.',
                  en: 'Prioritized ${relocation.hotC} hot-C, ${relocation.highLevelA} high-level-A, and ${relocation.unusedA} unused A slots.',
                )
              : _deEn(
                  context,
                  de: 'Keine kritischen Umlager-Kandidaten erkannt.',
                  en: 'No critical relocation candidates detected.',
                ),
          executeCount: relocation.total,
          onPressed: warehouse == null
              ? null
              : () {
                  appState.selectWarehouse(warehouse);
                  appState.setViewerHeatmapMetric(
                    ViewerHeatmapMetric.congestion,
                  );
                  appState.setViewerHeatmapVisible(true);
                  context.go('/viewer');
                },
          extra: RelocationCandidatesPanel(
            summary: relocation,
            isLoading: warehouse != null && !hasRelocationData,
            onCandidateTap: warehouse == null
                ? null
                : (candidate) {
                    appState.selectWarehouse(warehouse);
                    appState.requestViewerStorageFocus(
                      rack: candidate.rackNumber,
                      level: candidate.levelNumber,
                      slot: candidate.slotNumber,
                    );
                    context.go('/viewer');
                  },
          ),
        );
      }(),
      () {
        final replenishment = appState.replenishmentCandidates;
        final hasReplenishmentData = !replenishment.isEmpty;
        final replenishRecommended =
            hasHighPickLoad || hasSlaRisk || replenishment.urgent > 0;
        final reasonParts = <String>[];
        if (replenishment.urgent > 0) {
          reasonParts.add(
            context.tr('einlagernReasonUrgent', <String, Object>{
              'n': replenishment.urgent,
            }),
          );
        }
        if (replenishment.overdue > 0) {
          reasonParts.add(
            context.tr('einlagernReasonOverdue', <String, Object>{
              'n': replenishment.overdue,
              'days': replenishment.overdueDays,
            }),
          );
        }
        final reason = reasonParts.isEmpty
            ? context.tr('einlagernReasonOk')
            : context.tr('einlagernReasonRecommended', <String, Object>{
                'parts': reasonParts.join(' - '),
              });

        return _OperationalActionItem(
          id: 'putaway_replenishment',
          title: _deEn(context, de: 'Einlagern / Replenishment', en: 'Putaway / Replenishment'),
          description: _deEn(
            context,
            de: 'Nachschub aus Reserve in aktive Pickzonen anfordern.',
            en: 'Request replenishment from reserve to active picking zones.',
          ),
          explanation: _deEn(
            context,
            de: 'Hiermit stellst du sicher, dass aktive Pickplaetze nicht leer laufen. Der Fokus liegt auf schnell drehenden Artikeln, damit Kommissionierung und SLA stabil bleiben.',
            en: 'This keeps active pick slots from running empty. Focus is on fast movers to keep picking throughput and SLA stable.',
          ),
          whenToRun: _deEn(
            context,
            de: 'Wenn Pickplaetze leer laufen oder SLA unter Druck geraet.',
            en: 'When pick slots run empty or SLA comes under pressure.',
          ),
          whatHappens: _deEn(
            context,
            de: 'Replenishment-Kandidaten werden nach Dringlichkeit geordnet und direkt ansteuerbar gemacht.',
            en: 'Replenishment candidates are sorted by urgency and made directly actionable.',
          ),
          detailPoints: <String>[
            _deEn(
              context,
              de: 'Mindestbestaende auf aktiven Pickplaetzen gegenpruefen.',
              en: 'Validate min stock on active pick locations.',
            ),
            _deEn(
              context,
              de: 'Replenishment-Ticket fuer betroffene Artikelgruppen erzeugen.',
              en: 'Create replenishment tickets for affected item groups.',
            ),
            _deEn(
              context,
              de: 'Nachschub nach Prioritaet, Reichweite und Schichtbedarf starten.',
              en: 'Trigger replenishment by priority, coverage, and shift demand.',
            ),
          ],
          reason: reason,
          recommended: replenishRecommended,
          icon: Icons.inventory_2_outlined,
          onPressed: openWarehouseDetails,
          extra: ReplenishmentCandidatesPanel(
            summary: replenishment,
            isLoading: warehouse != null && !hasReplenishmentData,
            onCandidateTap: warehouse == null
                ? null
                : (candidate) {
                    appState.selectWarehouse(warehouse);
                    appState.requestViewerStorageFocus(
                      rack: candidate.rackNumber,
                      level: candidate.levelNumber,
                      slot: candidate.slotNumber,
                    );
                    context.go('/viewer');
                  },
          ),
        );
      }(),
      _OperationalActionItem(
        id: 'retrieval_cleanup',
        title: _deEn(context, de: 'Auslagern / Bereinigung', en: 'Retrieval / Cleanup'),
        description:
            _deEn(
              context,
              de: 'Langlieger und veraltete Bestaende zur Bereinigung markieren.',
              en: 'Mark slow movers and stale stock for cleanup.',
            ),
        explanation: _deEn(
          context,
          de: 'Die Aktion identifiziert Flaechenblocker mit geringer Bewegung. Dadurch entsteht Platz fuer aktive Sortimente und die Lagerstruktur bleibt schlank.',
          en: 'The action identifies low-movement stock that blocks capacity. This frees space for active assortments and keeps layout lean.',
        ),
        whenToRun: _deEn(
          context,
          de: 'Wenn Langlieger-Anteil steigt oder Flaeche fuer aktive Artikel fehlt.',
          en: 'When slow-mover share rises or active assortments need more space.',
        ),
        whatHappens: _deEn(
          context,
          de: 'Langlieger werden nach Kritikalitaet gruppiert und zur Bereinigung markiert.',
          en: 'Slow movers are grouped by criticality and marked for cleanup.',
        ),
        detailPoints: <String>[
          _deEn(
            context,
            de: 'Ladenhueter ueber Idle-Day-Grenze kennzeichnen.',
            en: 'Flag slow movers above the idle-days threshold.',
          ),
          _deEn(
            context,
            de: 'Umschlagarme Bestaende fuer Auslagerung oder Klaerung markieren.',
            en: 'Mark low-turnover stock for retrieval or clarification.',
          ),
          _deEn(
            context,
            de: 'Lagerflaeche fuer aktive Sortimente freigeben.',
            en: 'Free up space for active assortments.',
          ),
        ],
        checklist: <String>[
          _deEn(
            context,
            de: 'Kritische Langlieger priorisieren (sehr hohe Idle-Days).',
            en: 'Prioritize critical slow movers (very high idle days).',
          ),
          _deEn(
            context,
            de: 'Artikel mit geringer Bewegung fuer Auslagerung vormerken.',
            en: 'Flag low-movement items for retrieval.',
          ),
          _deEn(
            context,
            de: 'Mengen-/Qualitaetsklaerung mit Fachbereich abstimmen.',
            en: 'Align quantity/quality clarification with operations.',
          ),
          _deEn(
            context,
            de: 'Freigewordene Plaetze fuer A/B-Sortiment reservieren.',
            en: 'Reserve freed slots for A/B assortments.',
          ),
          _deEn(
            context,
            de: 'Nach Bereinigung Flachlager- und Stau-KPIs neu bewerten.',
            en: 'Re-check floor-space and congestion KPIs after cleanup.',
          ),
        ],
        reason: () {
          final reasonParts = <String>[];
          final criticalSlowMovers = slowMoverSamples
              .where(
                (sample) =>
                    (sample.daysSinceMovement ?? 0) >=
                    _slowMoverCriticalDaysThreshold,
              )
              .length;
          if (criticalSlowMovers > 0) {
            reasonParts.add(
              context.tr('auslagernReasonCritical', <String, Object>{
                'n': criticalSlowMovers,
                'days': _slowMoverCriticalDaysThreshold,
              }),
            );
          }
          if ((slowMoverSharePercent ?? 0) >= 8) {
            reasonParts.add(
              context.tr('auslagernReasonShare', <String, Object>{
                'n': slowMoverSharePercent ?? 0,
              }),
            );
          }
          return reasonParts.isEmpty
              ? context.tr('auslagernReasonOk')
              : context.tr('auslagernReasonRecommended', <String, Object>{
                  'parts': reasonParts.join(' - '),
                });
        }(),
        recommended: hasSlowMovers || (slowMoverSharePercent ?? 0) >= 8,
        icon: Icons.delete_sweep_outlined,
        onPressed: hasSlowMovers ? openSlowMoverDetails : openWarehouseDetails,
        onExecute: hasSlowMovers || warehouse != null
            ? () async {
                if (hasSlowMovers) {
                  openSlowMoverDetails?.call();
                } else {
                  openWarehouseDetails?.call();
                }
              }
            : null,
        executeLabel: _deEn(context, de: 'Auslagerung starten', en: 'Start retrieval'),
        executeDoneLabel: _deEn(context, de: 'Auslagerung markiert', en: 'Retrieval marked'),
        executeSummary: hasSlowMovers
            ? _deEn(
                context,
                de: 'Priorisiert $slowMoverPositions Langlieger auf $slowMoverArticles Artikeln (max. ${slowMoverMaxIdleDays ?? 0} Tage ohne Bewegung).',
                en: 'Prioritized $slowMoverPositions slow-mover slots across $slowMoverArticles items (max. ${slowMoverMaxIdleDays ?? 0} days without movement).',
              )
            : _deEn(
                context,
                de: 'Keine kritischen Auslager-Kandidaten erkannt.',
                en: 'No critical retrieval candidates detected.',
              ),
        executeCount: slowMoverPositions,
        extra: RetrievalCandidatesPanel(
          samples: slowMoverSamples,
          idleDaysThreshold: _slowMoverDaysThreshold,
          staleDaysThreshold: _slowMoverStaleDaysThreshold,
          criticalDaysThreshold: _slowMoverCriticalDaysThreshold,
          onCandidateTap: warehouse == null
              ? null
              : (candidate) {
                  appState.selectWarehouse(warehouse);
                  appState.requestViewerStorageFocus(
                    rack: candidate.rackNumber,
                    level: candidate.levelNumber,
                    slot: candidate.slotNumber,
                  );
                  context.go('/viewer');
                },
        ),
      ),
      _OperationalActionItem(
        id: 'abc_adjust',
        title: _deEn(context, de: 'ABC-Klassen anpassen', en: 'Adjust ABC classes'),
        description:
            _deEn(
              context,
              de: 'Artikelklassifizierung nach aktueller Umschlagrate pruefen.',
              en: 'Review item classification against current turnover.',
            ),
        explanation: _deEn(
          context,
          de: 'ABC-Klassen werden mit realen Bewegungsdaten abgeglichen. So passen Pickplatzqualitaet, Nachschubprioritaet und Stellplatznutzung wieder zum aktuellen Nachfrageprofil.',
          en: 'ABC classes are aligned with actual movement data. This keeps slot quality, replenishment priority, and space usage aligned with current demand.',
        ),
        whenToRun: _deEn(
          context,
          de: 'Wenn C-Anteil hoch bleibt oder Bewegungsmuster sich sichtbar verschieben.',
          en: 'When C-share stays elevated or movement patterns shift visibly.',
        ),
        whatHappens: _deEn(
          context,
          de: 'Artikel mit Fehlklassifizierung werden als Hoch-/Runterstufungs-Kandidaten vorgeschlagen.',
          en: 'Misclassified items are proposed as promotion/demotion candidates.',
        ),
        detailPoints: <String>[
          _deEn(
            context,
            de: 'ABC-Anteile mit Bewegungsdaten und Reichweiten abgleichen.',
            en: 'Align ABC shares with movement data and coverage.',
          ),
          _deEn(
            context,
            de: 'A/B/C-Artikel fuer Pickplaetze und Nachschubstrategie neu zuordnen.',
            en: 'Reassign A/B/C items for pick-face and replenishment strategy.',
          ),
          _deEn(
            context,
            de: 'Saisonartikel und Ausreisser separat bewerten.',
            en: 'Evaluate seasonal items and outliers separately.',
          ),
        ],
        reason: () {
          final reasonParts = <String>[];
          if (abcPromoteCandidates.isNotEmpty) {
            reasonParts.add(
              context.tr('abcAdjustReasonPromote', <String, Object>{
                'n': abcPromoteCandidates.length,
                'picks': abcPromotePickThreshold,
              }),
            );
          }
          if (abcDemoteCandidates.isNotEmpty) {
            reasonParts.add(
              context.tr('abcAdjustReasonDemote', <String, Object>{
                'n': abcDemoteCandidates.length,
                'picks': abcDemotePickThreshold,
                'days': abcDemoteIdleDaysThreshold,
              }),
            );
          }
          if ((cShareRatio ?? 0) >= 0.55) {
            reasonParts.add(context.tr('abcAdjustReasonCShare'));
          }
          return reasonParts.isEmpty
              ? context.tr('abcAdjustReasonOk')
              : context.tr('abcAdjustReasonRecommended', <String, Object>{
                  'parts': reasonParts.join(' - '),
                });
        }(),
        recommended: hasAbcActionSignals,
        icon: Icons.analytics_outlined,
        onPressed: openWarehouseDetails,
        onExecute: warehouse == null
            ? null
            : () => appState.ensureAbcArticlesLoadedForWarehouse(
                  warehouseId: warehouse.id,
                  limit: 100000,
                ),
        executeLabel: context.tr('abcAdjustExecuteLabel'),
        executeDoneLabel: context.tr('abcAdjustExecuteDoneLabel'),
        executeSummary: abcArticles.isEmpty
            ? context.tr('abcAdjustExecuteSummaryEmpty')
            : context.tr('abcAdjustExecuteSummary', <String, Object>{
                'total': abcCandidateCount,
                'promote': abcPromoteCandidates.length,
                'demote': abcDemoteCandidates.length,
                'review': abcReviewCandidates.length,
              }),
        executeCount: abcCandidateCount,
        extra: AbcAdjustmentPanel(
          summaries: abcArticles,
          promotePickThreshold: abcPromotePickThreshold,
          demotePickThreshold: abcDemotePickThreshold,
          demoteIdleDaysThreshold: abcDemoteIdleDaysThreshold,
        ),
      ),
      _OperationalActionItem(
        id: 'floor_replenishment_strategy',
        title: _deEn(context, de: 'Nachschub-Strategie Bodenplaetze', en: 'Floor replenishment strategy'),
        description:
            _deEn(
              context,
              de: 'Floor-Picking Nachschubgrenzen und Min/Max-Level anpassen.',
              en: 'Adjust floor-picking replenishment limits and min/max levels.',
            ),
        explanation: _deEn(
          context,
          de: 'Diese Steuerung optimiert die Bodenplaetze, auf denen operativ am meisten gepickt wird. Damit sinken Leerlaufzeiten und dringende Nachschuebe werden frueher erkannt.',
          en: 'This control optimizes floor slots with the highest operational pick load. It reduces empty-slot delays and flags urgent replenishment earlier.',
        ),
        whenToRun: _deEn(
          context,
          de: 'Wenn Bodenplaetze ueberfaellig leer sind oder Picks in Peaks ansteigen.',
          en: 'When floor slots remain overdue-empty or picks spike during peaks.',
        ),
        whatHappens: _deEn(
          context,
          de: 'Bodenplatz-Kandidaten werden als dringend, ueberfaellig oder naechste Welle markiert.',
          en: 'Floor-slot candidates are marked as urgent, overdue, or next wave.',
        ),
        detailPoints: <String>[
          _deEn(
            context,
            de: 'Min/Max-Level je Bodenplatz und Schichtbedarf neu setzen.',
            en: 'Reset min/max levels per floor slot and shift demand.',
          ),
          _deEn(
            context,
            de: 'Nachschubfenster nach Peak-Zeiten staffeln.',
            en: 'Stagger replenishment windows by peak times.',
          ),
          _deEn(
            context,
            de: 'Picking-Hotspots ueber Heatmap direkt ueberwachen.',
            en: 'Monitor pick hotspots directly via heatmap.',
          ),
        ],
        reason: () {
          final reasonParts = <String>[];
          if (floorOverdueCandidates.isNotEmpty) {
            reasonParts.add(
              context.tr('floorReplenishmentReasonOverdue', <String, Object>{
                'n': floorOverdueCandidates.length,
              }),
            );
          }
          if (floorUrgentCandidates.isNotEmpty) {
            reasonParts.add(
              context.tr('floorReplenishmentReasonUrgent', <String, Object>{
                'n': floorUrgentCandidates.length,
              }),
            );
          }
          if (hasHighPickLoad) {
            reasonParts.add(context.tr('floorReplenishmentReasonPeakLoad'));
          }
          return reasonParts.isEmpty
              ? context.tr('floorReplenishmentReasonOk')
              : context.tr(
                  'floorReplenishmentReasonRecommended',
                  <String, Object>{'parts': reasonParts.join(' - ')},
                );
        }(),
        recommended: hasFloorSignals,
        icon: Icons.inventory_2_outlined,
        onPressed: warehouse == null
            ? null
            : () {
                appState.selectWarehouse(warehouse);
                appState.setViewerHeatmapMetric(ViewerHeatmapMetric.pickRate);
                appState.setViewerHeatmapVisible(true);
                context.go('/viewer');
              },
        onExecute: warehouse == null
            ? null
            : () => appState.ensureReplenishmentCandidatesLoaded(
                  force: true,
                  limit: 24,
                ),
        executeLabel: context.tr('floorReplenishmentExecuteLabel'),
        executeDoneLabel: context.tr('floorReplenishmentExecuteDoneLabel'),
        executeSummary: floorCandidateCount > 0
            ? context.tr(
                'floorReplenishmentExecuteSummary',
                <String, Object>{
                  'total': floorCandidateCount,
                  'urgent': floorUrgentCandidates.length,
                  'overdue': floorOverdueCandidates.length,
                  'medium': floorMediumCandidates.length,
                },
              )
            : context.tr('floorReplenishmentExecuteSummaryEmpty'),
        executeCount: floorCandidateCount,
        extra: FloorReplenishmentPanel(
          urgent: floorUrgentCandidates,
          overdue: floorOverdueCandidates,
          medium: floorMediumCandidates,
          floorLevelThreshold: floorLevelThreshold,
          isLoading: warehouse != null && replenishmentForFloor.isEmpty,
          onCandidateTap: warehouse == null
              ? null
              : (candidate) {
                  appState.selectWarehouse(warehouse);
                  appState.requestViewerStorageFocus(
                    rack: candidate.rackNumber,
                    level: candidate.levelNumber,
                    slot: candidate.slotNumber,
                  );
                  context.go('/viewer');
                },
        ),
      ),
      _OperationalActionItem(
        id: 'putaway_strategy',
        title: _deEn(context, de: 'Einlager-Strategie', en: 'Putaway strategy'),
        description:
            _deEn(
              context,
              de: 'Wareneingang nach Zonen-/Kapazitaetsregeln neu priorisieren.',
              en: 'Re-prioritize inbound putaway by zone and capacity rules.',
            ),
        explanation: _deEn(
          context,
          de: 'Die Einlagerlogik verteilt eingehende Ware auf passende Zielplaetze (Fast-Lane/Reserve) statt nur erstbeste freie Positionen zu nutzen. Das verbessert Durchsatz und spaetere Pickwege.',
          en: 'Putaway logic routes inbound stock to fitting target slots (fast lane/reserve) instead of first-free placement. This improves throughput and later picking routes.',
        ),
        whenToRun: _deEn(
          context,
          de: 'Wenn Wareneingang den Ausgang ueberholt oder Fast-Lane-Plaetze knapp werden.',
          en: 'When inbound outpaces outbound or fast-lane slots become scarce.',
        ),
        whatHappens: _deEn(
          context,
          de: 'Freie Zielplaetze werden nach Fast-Lane/Reserve klassifiziert und gesperrte Plaetze markiert.',
          en: 'Free target slots are classified into fast-lane/reserve and blocked slots are flagged.',
        ),
        detailPoints: <String>[
          _deEn(
            context,
            de: 'Wareneingang nach freien Kapazitaeten und Wegzeit steuern.',
            en: 'Route inbound by free capacity and travel time.',
          ),
          _deEn(
            context,
            de: 'Schnelldreher direkt in aktive Zonen einlagern.',
            en: 'Put fast movers directly into active zones.',
          ),
          _deEn(
            context,
            de: 'Einlagerung gegen Durchsatz und SLA rueckpruefen.',
            en: 'Validate putaway against throughput and SLA.',
          ),
        ],
        reason: () {
          final reasonParts = <String>[];
          if (hasInboundBacklog) {
            reasonParts.add(context.tr('putawayReasonInboundBacklog'));
          }
          if (hasInboundBacklog && putawayFastLaneSlots.isEmpty) {
            reasonParts.add(context.tr('putawayReasonNoFastLane'));
          }
          if (putawayBlockedSlots.isNotEmpty) {
            reasonParts.add(
              context.tr('putawayReasonBlockedSlots', <String, Object>{
                'n': putawayBlockedSlots.length,
              }),
            );
          }
          return reasonParts.isEmpty
              ? context.tr('putawayReasonOk')
              : context.tr('putawayReasonRecommended', <String, Object>{
                  'parts': reasonParts.join(' - '),
                });
        }(),
        recommended: hasPutawaySignals,
        icon: Icons.move_down_outlined,
        onPressed: openWarehouseDetails,
        onExecute: warehouse == null
            ? null
            : () async {
                await appState.syncWarehouses();
                await appState.ensureStorageLocationsLoadedForWarehouse(
                  warehouse.id,
                  limit: 180,
                );
              },
        executeLabel: context.tr('putawayExecuteLabel'),
        executeDoneLabel: context.tr('putawayExecuteDoneLabel'),
        executeSummary: putawayCandidateCount > 0
            ? context.tr('putawayExecuteSummary', <String, Object>{
                'total': putawayCandidateCount,
                'fast': putawayFastLaneSlots.length,
                'reserve': putawayReserveSlots.length,
                'blocked': putawayBlockedSlots.length,
              })
            : context.tr('putawayExecuteSummaryEmpty'),
        executeCount: putawayCandidateCount,
        extra: PutawayCandidatesPanel(
          fastLaneSlots: putawayFastLaneSlots,
          reserveSlots: putawayReserveSlots,
          blockedSlots: putawayBlockedSlots,
          floorLevelThreshold: putawayFloorLevelThreshold,
          reserveLevelThreshold: putawayReserveLevelThreshold,
          onCandidateTap: warehouse == null
              ? null
              : (candidate) {
                  appState.selectWarehouse(warehouse);
                  appState.requestViewerStorageFocus(
                    rack: candidate.rackNumber,
                    level: candidate.levelNumber,
                    slot: candidate.slotNumber,
                  );
                  context.go('/viewer');
                },
        ),
      ),
      _OperationalActionItem(
        id: 'resources_adjust',
        title: _deEn(context, de: 'Ressourcen hoch/runter', en: 'Scale resources'),
        description: _deEn(
          context,
          de: 'Staplerfahrer und Kommissionierer lastabhaengig planen.',
          en: 'Plan forklift and picking staff based on live load.',
        ),
        explanation: _deEn(
          context,
          de: 'Diese Aktion uebersetzt Lastsignale (SLA, Pickdruck, Rueckstau) in Personalsteuerung. So kannst du frueh hoch- oder runterfahren, bevor Servicelevel kippen.',
          en: 'This action translates load signals (SLA, pick pressure, backlog) into staffing decisions. It helps scale up or down before service levels degrade.',
        ),
        whenToRun: _deEn(
          context,
          de: 'Wenn SLA-Druck, Kapazitaetsengpass oder Lastspitzen sichtbar werden.',
          en: 'When SLA pressure, capacity bottlenecks, or load peaks become visible.',
        ),
        whatHappens: _deEn(
          context,
          de: 'Das Team bekommt eine klare Prioritaet, ob Personal hoch- oder runtergefahren werden sollte.',
          en: 'The team gets a clear recommendation on whether staffing should scale up or down.',
        ),
        detailPoints: <String>[
          _deEn(
            context,
            de: 'Personal je Schicht nach Live-Last und SLA-Lage ausrichten.',
            en: 'Align shift staffing with live load and SLA status.',
          ),
          _deEn(
            context,
            de: 'Spitzenzeiten fuer Stapler und Picking separat planen.',
            en: 'Plan separate peak windows for forklift and picking.',
          ),
          _deEn(
            context,
            de: 'Offene Tickets und Rueckstaende in der Disposition beruecksichtigen.',
            en: 'Include open tickets and backlog in dispatch planning.',
          ),
        ],
        reason: hasSlaRisk || hasCapacityRisk || hasHighPickLoad
            ? _deEn(context, de: 'Empfohlen: Lastspitzen beeinflussen SLA/Kapazitaet.', en: 'Recommended: load peaks are affecting SLA/capacity.')
            : _deEn(context, de: 'Optional: aktueller Personalbedarf stabil.', en: 'Optional: current staffing demand is stable.'),
        recommended: hasSlaRisk || hasCapacityRisk || hasHighPickLoad,
        icon: Icons.groups_2_outlined,
        onPressed: openWarehouseDetails,
      ),
    ];

    final tabs = <_DashboardTab>[
      _DashboardTab(
        label: _deEn(context, de: 'Massnahmen', en: 'Actions'),
        icon: Icons.checklist_rounded,
        children: <Widget>[_OperationalActionsCard(items: actionItems)],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'KPIs', en: 'KPIs'),
        icon: Icons.speed_rounded,
        children: <Widget>[
          _DashboardKpiSection(
            showSectionHeader: false,
            warehouse: warehouse,
            appState: appState,
            horizonDays: appState.dashboardKpiHorizonDays,
            storageSamples: storageSamples,
            utilization: filteredUtilization,
            totalSlots: filteredTotalSlots,
            occupiedSlots: filteredOccupiedSlots,
            freeSlots: filteredFreeSlots,
            inboundVsOutbound: inboundVsOutbound,
            pickRate: pickRate,
            dockUtilization: dockUtilization,
            qualityHolds: qualityHolds,
            slowMoverPositions: slowMoverPositions,
            slowMoverArticles: slowMoverArticles,
            slowMoverMaxIdleDays: slowMoverMaxIdleDays,
            slowMoverSharePercent: slowMoverSharePercent,
            openSlowMoverDetails: openSlowMoverDetails,
          ),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'ABC', en: 'ABC'),
        icon: Icons.analytics_outlined,
        children: <Widget>[
          _AbcAnalysisCard(
            showHeader: false,
            warehouse: warehouse,
            abc: abc,
          ),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: '3D-Modell', en: '3D model'),
        icon: Icons.view_in_ar_outlined,
        children: <Widget>[
          _Dashboard3DModelCard(
            modelPath: warehouse == null
                ? null
                : appState.getExternalModelPathForWarehouse(warehouse.id),
          ),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'Auftragsvolumen', en: 'Order volume'),
        icon: Icons.show_chart_rounded,
        children: <Widget>[
          OrderVolumeCard(
            points: appState.orderVolumeTrend,
            isLoading: warehouse != null && appState.orderVolumeTrend.isEmpty,
          ),
          const SizedBox(height: AppSpacing.md),
          _OrderVolumeTableCard(points: appState.orderVolumeTrend),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'Pick-Heatmap', en: 'Pick heatmap'),
        icon: Icons.grid_on_rounded,
        children: <Widget>[
          PickActivityHeatmapCard(
            heatmap: appState.pickActivityHeatmap,
            isLoading:
                warehouse != null && appState.pickActivityHeatmap.isEmpty,
          ),
          const SizedBox(height: AppSpacing.md),
          _PickActivityTableCard(heatmap: appState.pickActivityHeatmap),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'Top-Artikel', en: 'Top items'),
        icon: Icons.inventory_2_outlined,
        children: <Widget>[
          _TopArticlesCard(
            items: warehouse == null
                ? const <WarehouseAbcArticleSummary>[]
                : appState.getAbcArticlesForWarehouse(warehouse.id),
          ),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'Free Capacity', en: 'Free capacity'),
        icon: Icons.unarchive_outlined,
        children: <Widget>[
          _FreeCapacityCard(
            slots: warehouse == null
                ? const <WarehouseAbcSlotSummary>[]
                : appState.getAbcSlotsForWarehouse(warehouse.id),
          ),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'Smart Relocation', en: 'Smart relocation'),
        icon: Icons.swap_horiz_rounded,
        children: <Widget>[
          _SmartRelocationCard(
            slots: warehouse == null
                ? const <WarehouseAbcSlotSummary>[]
                : appState.getAbcSlotsForWarehouse(warehouse.id),
          ),
        ],
      ),
      _DashboardTab(
        label: _deEn(context, de: 'Durchsatz', en: 'Throughput'),
        icon: Icons.timeline_rounded,
        children: <Widget>[
          _ThroughputTrendTabCard(
            future: appState.loadThroughputTrend(
              days: appState.dashboardKpiHorizonDays,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ThroughputTrendTableCard(
            future: appState.loadThroughputTrend(
              days: appState.dashboardKpiHorizonDays,
            ),
          ),
        ],
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DashboardHeaderStrip(warehouse: warehouse),
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 0,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: <Widget>[
                for (final tab in tabs)
                  Tab(icon: Icon(tab.icon, size: 18), text: tab.label),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final tab in tabs)
                  RefreshIndicator(
                    onRefresh: appState.syncWarehouses,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: tab.children,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTab {
  const _DashboardTab({
    required this.label,
    required this.icon,
    required this.children,
  });

  final String label;
  final IconData icon;
  final List<Widget> children;
}

class _Dashboard3DModelCard extends StatelessWidget {
  const _Dashboard3DModelCard({required this.modelPath});

  final String? modelPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = modelPath?.trim() ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 520,
        child: path.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.view_in_ar_outlined,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _deEn(
                          context,
                          de: 'Kein 3D-Modell verfuegbar.',
                          en: 'No 3D model available.',
                        ),
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : Glb3DViewer(modelPath: path),
      ),
    );
  }
}

class _TopArticlesCard extends StatelessWidget {
  const _TopArticlesCard({required this.items});

  final List<WarehouseAbcArticleSummary> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Card(
        elevation: 0,
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            _deEn(
              context,
              de: 'Keine Artikel-Bewegungsdaten verfuegbar.',
              en: 'No item movement data available.',
            ),
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final sorted = [...items]
      ..sort((a, b) => b.movements30d.compareTo(a.movements30d));
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
                Expanded(
                  child: Text(
                    _deEn(
                      context,
                      de: 'Top-Artikel nach Bewegungen',
                      en: 'Top items by movements',
                    ),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoIconButton(
                  title: _deEn(
                    context,
                    de: 'Top-Artikel nach Bewegungen',
                    en: 'Top items by movements',
                  ),
                  body: _deEn(
                    context,
                    de: 'Welche Artikel werden am haeufigsten bewegt? Die Tabelle zeigt fuer jeden Artikel: Nummer, Bezeichnung, ABC-Klasse, Picks der letzten 30 Tage, Anzahl Lagerplaetze und maximale Inaktivitaet in Tagen.',
                    en: 'Which items move the most? The table shows each item number, description, ABC class, picks in the last 30 days, number of slots, and maximum idle days.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _deEn(
                context,
                de: 'Sortiert nach Bewegungen der letzten 30 Tage.',
                en: 'Sorted by movements in the last 30 days.',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFlatDataTable(
              minWidth: 980,
              columns: const <DataColumn2>[
                DataColumn2(label: Text('ARTIKEL'), size: ColumnSize.L),
                DataColumn2(label: Text('BEZEICHNUNG'), size: ColumnSize.L),
                DataColumn2(label: Text('ABC'), size: ColumnSize.S),
                DataColumn2(
                  label: Text('BEWEGUNGEN_30T'),
                  numeric: true,
                  size: ColumnSize.M,
                ),
                DataColumn2(
                  label: Text('PLAETZE'),
                  numeric: true,
                  size: ColumnSize.S,
                ),
                DataColumn2(
                  label: Text('MAX_IDLE_T'),
                  numeric: true,
                  size: ColumnSize.S,
                ),
              ],
              rows: sorted.map((item) {
                return DataRow(
                  cells: <DataCell>[
                    DataCell(Text(item.articleId)),
                    DataCell(
                      Text(
                        item.articleDescription.isEmpty
                            ? '-'
                            : item.articleDescription,
                      ),
                    ),
                    DataCell(Text(item.abcClass)),
                    DataCell(Text('${item.movements30d}')),
                    DataCell(Text('${item.slotCount}')),
                    DataCell(Text('${item.maxIdleDays}')),
                  ],
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeaderStrip extends StatelessWidget {
  const _DashboardHeaderStrip({required this.warehouse});

  final Warehouse? warehouse;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final w = warehouse;
    final totalSlots = w?.totalStorageSlots ?? 0;
    final occupied = w?.occupiedStorageSlots ?? 0;
    final free = w?.freeStorageSlots ?? 0;
    final utilPct = w?.utilizationPercent ?? 0;
    final overloaded = w?.overloadedStorageSlots ?? 0;
    final articleCount = w?.articleCount ?? 0;
    final subtitle = w == null
        ? _deEn(
            context,
            de: 'Keine Lagerauswahl aktiv.',
            en: 'No warehouse selected.',
          )
        : _deEn(
            context,
            de: 'Lager ${w.location} — Live-Auswertung aus warehouse.db',
            en: 'Warehouse ${w.location} — live evaluation from warehouse.db',
          );
    final tiles = <_HeaderKpiTile>[
      _HeaderKpiTile(
        label: _deEn(context, de: 'Stellplaetze', en: 'Slots'),
        value: _formatThousands(totalSlots),
        info: _deEn(
          context,
          de: 'Wie viele Lagerplaetze gibt es im Lager insgesamt? Gezaehlt werden alle eingerichteten Stellplaetze.',
          en: 'How many storage slots exist in the warehouse in total? All configured slots are counted.',
        ),
      ),
      _HeaderKpiTile(
        label: _deEn(context, de: 'Belegt', en: 'Occupied'),
        value: _formatThousands(occupied),
        info: _deEn(
          context,
          de: 'Wie viele Lagerplaetze sind aktuell mit Ware belegt? Gezaehlt werden alle Plaetze, auf denen mindestens eine Palette oder Ladeeinheit steht.',
          en: 'How many slots currently hold stock? Counted are all slots with at least one pallet or load unit on them.',
        ),
      ),
      _HeaderKpiTile(
        label: _deEn(context, de: 'Frei', en: 'Free'),
        value: _formatThousands(free),
        info: _deEn(
          context,
          de: 'Wie viele Lagerplaetze stehen aktuell zur Verfuegung? Stellplaetze abzueglich der belegten. Enthaelt leere wie auch reservierte oder gesperrte Plaetze.',
          en: 'How many slots are currently available? Total slots minus occupied. Includes empty as well as reserved or blocked slots.',
        ),
      ),
      _HeaderKpiTile(
        label: _deEn(context, de: 'Ø Auslastung', en: 'Avg utilization'),
        value: '$utilPct %',
        info: _deEn(
          context,
          de: 'Wie voll ist das Lager im Durchschnitt? Anteil der belegten an allen Stellplaetzen in Prozent. Ein Grobindikator fuer den Fuellgrad; sagt nichts darueber aus, ob einzelne Bereiche ueberlastet sind.',
          en: 'How full is the warehouse on average? Share of occupied vs total slots as a percentage. A rough fill indicator; says nothing about local bottlenecks.',
        ),
      ),
      _HeaderKpiTile(
        label: _deEn(context, de: 'Ueberlastet (>100 %)', en: 'Overloaded (>100 %)'),
        value: _formatThousands(overloaded),
        valueColor: overloaded > 0 ? AppColors.warningDark : null,
        info: _deEn(
          context,
          de: 'An wie vielen Plaetzen steht mehr Ware als eigentlich Platz haette? Diese Plaetze sollten geprueft und entlastet werden. Beruecksichtigt nur Plaetze mit hinterlegter Kapazitaet.',
          en: 'How many slots hold more stock than they were designed for? These slots should be reviewed and relieved. Only slots with a configured capacity are counted.',
        ),
      ),
      _HeaderKpiTile(
        label: _deEn(context, de: 'Artikel', en: 'Items'),
        value: _formatThousands(articleCount),
        info: _deEn(
          context,
          de: 'Wie viele verschiedene Artikel waren in den letzten 6 Monaten in Bewegung? Artikel ohne jegliche Bewegung in diesem Zeitraum sind nicht mitgezaehlt.',
          en: 'How many distinct items moved in the last 6 months? Items with no movement at all in that period are excluded.',
        ),
      ),
    ];
    return Material(
      color: colorScheme.surface,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              w?.name ?? 'Schaeflein LagerView',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                const minTileWidth = 140.0;
                final maxColumns = (constraints.maxWidth / minTileWidth)
                    .floor()
                    .clamp(1, tiles.length);
                final tileWidth =
                    (constraints.maxWidth - (maxColumns - 1) * AppSpacing.sm) /
                        maxColumns;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final tile in tiles)
                      SizedBox(width: tileWidth, child: tile),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderKpiTile extends StatelessWidget {
  const _HeaderKpiTile({
    required this.label,
    required this.value,
    this.valueColor,
    this.info,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? info;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (info != null) ...<Widget>[
              const SizedBox(width: 2),
              Tooltip(
                message: info!,
                preferBelow: false,
                waitDuration: const Duration(milliseconds: 200),
                child: InkResponse(
                  onTap: () => _showKpiInfoDialog(
                    context,
                    title: label,
                    body: info!,
                  ),
                  radius: 14,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? colorScheme.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _InfoIconButton extends StatelessWidget {
  const _InfoIconButton({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: const Icon(Icons.info_outline_rounded, size: 18),
      tooltip: title,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: colorScheme.onSurfaceVariant,
      onPressed: () =>
          _showKpiInfoDialog(context, title: title, body: body),
    );
  }
}

Future<void> _showKpiInfoDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final textTheme = Theme.of(ctx).textTheme;
      return AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(Icons.info_outline_rounded,
                size: 20, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(body, style: textTheme.bodyMedium),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_deEn(ctx, de: 'Schliessen', en: 'Close')),
          ),
        ],
      );
    },
  );
}

String _formatThousands(int value) {
  final str = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(str[i]);
  }
  return buffer.toString();
}

class _FreeCapacityCard extends StatelessWidget {
  const _FreeCapacityCard({required this.slots});

  final List<WarehouseAbcSlotSummary> slots;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    if (slots.isEmpty) {
      return _emptyCard(
        context,
        title: _deEn(context, de: 'Free Capacity', en: 'Free capacity'),
        message: _deEn(
          context,
          de: 'Keine Platz-Daten geladen.',
          en: 'No slot data loaded.',
        ),
      );
    }
    final filtered = slots
        .where((s) => s.freeCapacity > 0)
        .toList(growable: false)
      ..sort((a, b) => b.freeCapacity.compareTo(a.freeCapacity));
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
                Expanded(
                  child: Text(
                    _deEn(context, de: 'Free Capacity', en: 'Free capacity'),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoIconButton(
                  title: _deEn(context, de: 'Free Capacity', en: 'Free capacity'),
                  body: _deEn(
                    context,
                    de: 'Wo ist im Lager noch Platz? Die Tabelle zeigt Lagerplaetze, auf denen mehr Ware hinpasst, als gerade dort steht. Sortiert nach groesster freier Kapazitaet. Hilfreich, um beim Einlagern schnell ein passendes Ziel zu finden.',
                    en: 'Where is there still space in the warehouse? The table shows slots that can hold more than they currently do, sorted by largest free capacity first. Useful for finding a good putaway target quickly.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _deEn(
                context,
                de: 'Plaetze mit Restkapazitaet sortiert nach MAX_LHM - IST_LHM.',
                en: 'Slots with remaining capacity sorted by MAX_LHM - IST_LHM.',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (filtered.isEmpty)
              Text(
                _deEn(
                  context,
                  de: 'Keine Plaetze mit Restkapazitaet > 0.',
                  en: 'No slots with remaining capacity > 0.',
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              AppFlatDataTable(
                minWidth: 820,
                columns: const <DataColumn2>[
                  DataColumn2(label: Text('PLATZ_ID'), size: ColumnSize.M),
                  DataColumn2(label: Text('HALLE'), size: ColumnSize.S),
                  DataColumn2(label: Text('REGAL'), numeric: true, size: ColumnSize.S),
                  DataColumn2(label: Text('FACH'), numeric: true, size: ColumnSize.S),
                  DataColumn2(label: Text('EBENE'), numeric: true, size: ColumnSize.S),
                  DataColumn2(label: Text('MAX_LHM'), numeric: true, size: ColumnSize.S),
                  DataColumn2(label: Text('IST_LHM'), numeric: true, size: ColumnSize.S),
                  DataColumn2(label: Text('FREE_CAPACITY'), numeric: true, size: ColumnSize.S),
                  DataColumn2(label: Text('UTILIZATION'), numeric: true, size: ColumnSize.S),
                ],
                rows: filtered.map((s) {
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(Text(s.placeId)),
                      DataCell(Text(_hallForRegal(s.regal))),
                      DataCell(Text(s.regal)),
                      DataCell(Text(s.fach)),
                      DataCell(Text(s.ebene)),
                      DataCell(Text(_formatNum(s.maxLhm))),
                      DataCell(Text(_formatNum(s.istLhm))),
                      DataCell(Text(_formatNum(s.freeCapacity))),
                      DataCell(Text(s.utilizationPct.toStringAsFixed(0))),
                    ],
                  );
                }).toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmartRelocationCard extends StatefulWidget {
  const _SmartRelocationCard({required this.slots});

  final List<WarehouseAbcSlotSummary> slots;

  @override
  State<_SmartRelocationCard> createState() => _SmartRelocationCardState();
}

class _SmartRelocationCardState extends State<_SmartRelocationCard> {
  double _count = 10;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.slots.isEmpty) {
      return _emptyCard(
        context,
        title: _deEn(context, de: 'Smart Relocation', en: 'Smart relocation'),
        message: _deEn(
          context,
          de: 'Keine Platz-Daten geladen.',
          en: 'No slot data loaded.',
        ),
      );
    }
    final overloaded = widget.slots
        .where((s) => s.utilizationPct > 100)
        .toList(growable: false)
      ..sort((a, b) => b.utilizationPct.compareTo(a.utilizationPct));
    final free = widget.slots
        .where((s) => s.freeCapacity > 0)
        .toList(growable: false)
      ..sort((a, b) => b.freeCapacity.compareTo(a.freeCapacity));
    final n = _count.toInt();
    final pairs = <(WarehouseAbcSlotSummary, WarehouseAbcSlotSummary)>[];
    final limit = [n, overloaded.length, free.length]
        .reduce((a, b) => a < b ? a : b);
    for (var i = 0; i < limit; i++) {
      pairs.add((overloaded[i], free[i]));
    }
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
                Expanded(
                  child: Text(
                    _deEn(context, de: 'Smart Relocation', en: 'Smart relocation'),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoIconButton(
                  title: _deEn(
                    context,
                    de: 'Smart Relocation',
                    en: 'Smart relocation',
                  ),
                  body: _deEn(
                    context,
                    de: 'Konkrete Umlagerungs-Vorschlaege: Ware von ueberlasteten Plaetzen (mehr Ware als Platz) auf Plaetze mit freier Kapazitaet bewegen. Jede Zeile ist ein Paar aus Quellplatz und vorgeschlagenem Zielplatz. Mit dem Schieberegler steuerst du, wie viele Vorschlaege angezeigt werden.',
                    en: 'Concrete relocation suggestions: move stock from overloaded slots (more stock than capacity) to slots with free space. Each row is a pair of source and proposed target slot. The slider controls how many suggestions are shown.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _deEn(
                context,
                de: 'Fuer jeden ueberlasteten Platz (UTILIZATION > 100 %) ein Vorschlag, wohin ausgelagert werden kann (FREE_CAPACITY > 0).',
                en: 'For each overloaded slot (UTILIZATION > 100 %), a suggestion where to relocate (FREE_CAPACITY > 0).',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Text(
                  _deEn(context, de: 'Anzahl Vorschlaege', en: 'Suggestions'),
                  style: textTheme.labelMedium,
                ),
                Expanded(
                  child: Slider(
                    value: _count,
                    min: 5,
                    max: 50,
                    divisions: 9,
                    label: '${_count.toInt()}',
                    onChanged: (v) => setState(() => _count = v),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${_count.toInt()}',
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (pairs.isEmpty)
              Text(
                _deEn(
                  context,
                  de: 'Keine ueberlasteten oder keine freien Plaetze.',
                  en: 'No overloaded or no free slots.',
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              AppFlatDataTable(
                minWidth: 880,
                columns: const <DataColumn2>[
                  DataColumn2(label: Text('von_PLATZ'), size: ColumnSize.M),
                  DataColumn2(label: Text('von (R/F/E)'), size: ColumnSize.S),
                  DataColumn2(
                      label: Text('von_Auslastung_%'),
                      numeric: true,
                      size: ColumnSize.S),
                  DataColumn2(label: Text('nach_PLATZ'), size: ColumnSize.M),
                  DataColumn2(label: Text('nach (R/F/E)'), size: ColumnSize.S),
                  DataColumn2(
                      label: Text('nach_freie_LHM'),
                      numeric: true,
                      size: ColumnSize.S),
                ],
                rows: pairs.map((pair) {
                  final src = pair.$1;
                  final tgt = pair.$2;
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(Text(src.placeId)),
                      DataCell(Text('${src.regal}/${src.fach}/${src.ebene}')),
                      DataCell(
                          Text(src.utilizationPct.toStringAsFixed(0))),
                      DataCell(Text(tgt.placeId)),
                      DataCell(Text('${tgt.regal}/${tgt.fach}/${tgt.ebene}')),
                      DataCell(Text(_formatNum(tgt.freeCapacity))),
                    ],
                  );
                }).toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThroughputTrendTableCard extends StatelessWidget {
  const _ThroughputTrendTableCard({required this.future});

  final Future<List<WarehouseTrendPoint>> future;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
                Expanded(
                  child: Text(
                    _deEn(
                      context,
                      de: 'Bewegungen pro Tag (Tabelle)',
                      en: 'Movements per day (table)',
                    ),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoIconButton(
                  title: _deEn(
                    context,
                    de: 'Bewegungen (Tabelle)',
                    en: 'Movements (table)',
                  ),
                  body: _deEn(
                    context,
                    de: 'Dieselben Bewegungen wie im Diagramm oberhalb, nur tabellarisch. Eine Zeile pro Tag, sortiert vom neuesten zum aeltesten. Mit der Veraenderung im Vergleich zum Mittelwert.',
                    en: 'Same daily movements as the chart above, in tabular form. One row per day, sorted from newest to oldest. With deviation from the average.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _deEn(
                context,
                de: 'Neueste zuerst. Der Pfeil zeigt die Abweichung vom Mittelwert.',
                en: 'Newest first. The arrow shows the deviation from the average.',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FutureBuilder<List<WarehouseTrendPoint>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final points = snapshot.data ?? const <WarehouseTrendPoint>[];
                if (points.isEmpty) {
                  return Text(
                    _deEn(
                      context,
                      de: 'Keine Bewegungsdaten gefunden.',
                      en: 'No movement data found.',
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                final sorted = [...points]
                  ..sort((a, b) => b.date.compareTo(a.date));
                final avg = points.fold<int>(0, (s, p) => s + p.value) /
                    points.length;
                return AppFlatDataTable(
                  minWidth: 520,
                  columns: const <DataColumn2>[
                    DataColumn2(label: Text('DATUM'), size: ColumnSize.M),
                    DataColumn2(label: Text('WOCHENTAG'), size: ColumnSize.S),
                    DataColumn2(
                      label: Text('BEWEGUNGEN'),
                      numeric: true,
                      size: ColumnSize.S,
                    ),
                    DataColumn2(
                      label: Text('Δ Ø'),
                      numeric: true,
                      size: ColumnSize.S,
                    ),
                  ],
                  rows: sorted.map((p) {
                    final delta = p.value - avg;
                    final deltaSign = delta > 0.5
                        ? '+'
                        : (delta < -0.5 ? '−' : '±');
                    final deltaTxt = '$deltaSign${delta.abs().toStringAsFixed(0)}';
                    return DataRow(
                      cells: <DataCell>[
                        DataCell(Text(_formatDate(p.date))),
                        DataCell(Text(_weekdayLabel(context, p.date.weekday % 7))),
                        DataCell(Text(_formatThousands(p.value))),
                        DataCell(Text(deltaTxt)),
                      ],
                    );
                  }).toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ThroughputTrendTabCard extends StatelessWidget {
  const _ThroughputTrendTabCard({required this.future});

  final Future<List<WarehouseTrendPoint>> future;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
                Expanded(
                  child: Text(
                    _deEn(context, de: 'Bewegungen pro Tag', en: 'Movements per day'),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoIconButton(
                  title: _deEn(
                    context,
                    de: 'Durchsatz (Bewegungen / Tag)',
                    en: 'Throughput (movements / day)',
                  ),
                  body: _deEn(
                    context,
                    de: 'Wie viele Lagerbewegungen gab es pro Tag? Die Linie zeigt die taeglichen Picks im gewaehlten Zeitraum. Die gestrichelte Linie ist der Durchschnitt, der hervorgehobene Punkt der Tag mit dem hoechsten Aufkommen. Den Zeitraum kannst du oben ueber den Filter "Durchsatz-Zeitraum" anpassen.',
                    en: 'How many warehouse movements happened per day? The line shows daily picks in the selected window. The dashed line is the average; the highlighted point is the peak day. Use the "Throughput window" filter above to change the period.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _deEn(
                context,
                de: 'Zeitraum aus dem Filter oben. Quelle: df_tpa_6mon_ber03_schlg_rti3.',
                en: 'Time range from the filter above. Source: df_tpa_6mon_ber03_schlg_rti3.',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FutureBuilder<List<WarehouseTrendPoint>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 280,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final points = snapshot.data ?? const <WarehouseTrendPoint>[];
                if (points.isEmpty) {
                  return Text(
                    _deEn(
                      context,
                      de: 'Keine Bewegungsdaten gefunden.',
                      en: 'No movement data found.',
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return _MovementsLineChart(points: points);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementsLineChart extends StatelessWidget {
  const _MovementsLineChart({required this.points});

  final List<WarehouseTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxValue = points
        .map((p) => p.value)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, 1 << 30);
    final minValue =
        points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    final avg = points.fold<int>(0, (sum, p) => sum + p.value) / points.length;
    final peak = points.reduce((a, b) => a.value >= b.value ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            _ChartStat(
              label: _deEn(context, de: 'Mittelwert / Tag', en: 'Avg / day'),
              value: avg.toStringAsFixed(0),
            ),
            _ChartStat(
              label: _deEn(context, de: 'Spitze', en: 'Peak'),
              value: _formatThousands(peak.value),
              hint:
                  '${peak.date.day.toString().padLeft(2, '0')}.${peak.date.month.toString().padLeft(2, '0')}.${peak.date.year}',
            ),
            _ChartStat(
              label: _deEn(context, de: 'Tiefstand', en: 'Low'),
              value: _formatThousands(minValue),
            ),
            _ChartStat(
              label: _deEn(context, de: 'Datenpunkte', en: 'Points'),
              value: '${points.length}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 280,
          child: CustomPaint(
            painter: _LineChartPainter(
              points: points,
              maxValue: maxValue,
              avg: avg,
              lineColor: colorScheme.primary,
              gridColor: colorScheme.outlineVariant.withValues(alpha: 0.35),
              avgColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              fillTop: colorScheme.primary.withValues(alpha: 0.22),
              fillBottom: colorScheme.primary.withValues(alpha: 0.0),
              peakColor: colorScheme.primary,
              labelStyle: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ) ??
                  const TextStyle(fontSize: 10),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _ChartStat extends StatelessWidget {
  const _ChartStat({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.maxValue,
    required this.avg,
    required this.lineColor,
    required this.gridColor,
    required this.avgColor,
    required this.fillTop,
    required this.fillBottom,
    required this.peakColor,
    required this.labelStyle,
  });

  final List<WarehouseTrendPoint> points;
  final int maxValue;
  final double avg;
  final Color lineColor;
  final Color gridColor;
  final Color avgColor;
  final Color fillTop;
  final Color fillBottom;
  final Color peakColor;
  final TextStyle labelStyle;

  static const double _leftPad = 44;
  static const double _rightPad = 12;
  static const double _topPad = 14;
  static const double _bottomPad = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - _leftPad - _rightPad;
    final chartH = size.height - _topPad - _bottomPad;
    if (chartW <= 0 || chartH <= 0 || points.isEmpty) {
      return;
    }

    final niceMax = _niceMax(maxValue);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Horizontale Gridlines + Y-Achsen-Labels (4 Stufen).
    for (var i = 0; i <= 4; i++) {
      final y = _topPad + chartH * i / 4;
      _drawDashedLine(
        canvas,
        Offset(_leftPad, y),
        Offset(_leftPad + chartW, y),
        gridPaint,
        dashWidth: 3,
        dashGap: 4,
      );
      final v = (niceMax * (4 - i) / 4).round();
      final tp = TextPainter(
        text: TextSpan(text: _formatThousands(v), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_leftPad - tp.width - 6, y - tp.height / 2));
    }

    // Punkte als (x,y) berechnen.
    final coords = <Offset>[];
    if (points.length == 1) {
      coords.add(
        Offset(
          _leftPad + chartW / 2,
          _topPad + chartH * (1 - points.first.value / niceMax),
        ),
      );
    } else {
      final stepX = chartW / (points.length - 1);
      for (var i = 0; i < points.length; i++) {
        final x = _leftPad + stepX * i;
        final y = _topPad + chartH * (1 - points[i].value / niceMax);
        coords.add(Offset(x, y));
      }
    }

    // Glatte Linie via Catmull-Rom -> Bezier.
    final linePath = _smoothPath(coords);

    // Verlauf unter der Linie.
    final fillPath = Path.from(linePath)
      ..lineTo(coords.last.dx, _topPad + chartH)
      ..lineTo(coords.first.dx, _topPad + chartH)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[fillTop, fillBottom],
      ).createShader(Rect.fromLTWH(_leftPad, _topPad, chartW, chartH));
    canvas.drawPath(fillPath, fillPaint);

    // Mittelwert-Linie (gestrichelt).
    final avgY = _topPad + chartH * (1 - avg / niceMax);
    _drawDashedLine(
      canvas,
      Offset(_leftPad, avgY),
      Offset(_leftPad + chartW, avgY),
      Paint()
        ..color = avgColor
        ..strokeWidth = 1,
      dashWidth: 4,
      dashGap: 4,
    );
    final avgTp = TextPainter(
      text: TextSpan(
        text: 'Ø ${avg.toStringAsFixed(0)}',
        style: labelStyle.copyWith(
          color: avgColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    avgTp.paint(
      canvas,
      Offset(_leftPad + chartW - avgTp.width - 2, avgY - avgTp.height - 2),
    );

    // Linie.
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Peak-Punkt markieren.
    final peakIndex = _indexOfMax();
    final peakOffset = coords[peakIndex];
    canvas.drawCircle(
      peakOffset,
      5,
      Paint()..color = peakColor.withValues(alpha: 0.18),
    );
    canvas.drawCircle(peakOffset, 3, Paint()..color = peakColor);
    canvas.drawCircle(
      peakOffset,
      3,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // X-Achse: ca. 5 Tick-Labels gleichmaessig verteilt.
    final tickCount = points.length < 6 ? points.length : 5;
    for (var i = 0; i < tickCount; i++) {
      final idx = (i * (points.length - 1) / (tickCount - 1)).round().clamp(
            0,
            points.length - 1,
          );
      final x = coords[idx].dx;
      final date = points[idx].date;
      final txt =
          '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
      final tp = TextPainter(
        text: TextSpan(text: txt, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - tp.width / 2).clamp(
        _leftPad - 4,
        _leftPad + chartW - tp.width + 4,
      );
      tp.paint(canvas, Offset(dx, _topPad + chartH + 8));
    }
  }

  Path _smoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length < 3) {
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      return path;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[0] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      const t = 0.5; // Catmull-Rom-Spannung.
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) * t / 3,
        p1.dy + (p2.dy - p0.dy) * t / 3,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) * t / 3,
        p2.dy - (p3.dy - p1.dy) * t / 3,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    required double dashWidth,
    required double dashGap,
  }) {
    final total = (to - from).distance;
    final dir = (to - from) / total;
    var traveled = 0.0;
    while (traveled < total) {
      final segEnd = (traveled + dashWidth).clamp(0.0, total);
      canvas.drawLine(from + dir * traveled, from + dir * segEnd, paint);
      traveled += dashWidth + dashGap;
    }
  }

  int _indexOfMax() {
    var maxIdx = 0;
    var maxVal = points.first.value;
    for (var i = 1; i < points.length; i++) {
      if (points[i].value > maxVal) {
        maxVal = points[i].value;
        maxIdx = i;
      }
    }
    return maxIdx;
  }

  /// Rundet maxValue auf eine "nette" Y-Achsen-Spitze (z.B. 87 -> 100, 432 -> 500).
  int _niceMax(int v) {
    if (v <= 0) return 1;
    final magnitude = math.pow(10, v.toString().length - 1).toInt();
    final normalized = v / magnitude;
    final niceStep = normalized <= 1
        ? 1
        : normalized <= 2
            ? 2
            : normalized <= 5
                ? 5
                : 10;
    return niceStep * magnitude;
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.points != points ||
      old.maxValue != maxValue ||
      old.avg != avg ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor ||
      old.avgColor != avgColor ||
      old.fillTop != fillTop ||
      old.fillBottom != fillBottom ||
      old.peakColor != peakColor;
}

String _formatNum(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class _OrderVolumeTableCard extends StatelessWidget {
  const _OrderVolumeTableCard({required this.points});

  final List<OrderVolumePoint> points;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return _emptyCard(
        context,
        title: _deEn(
          context,
          de: 'Auftragsvolumen-Tabelle',
          en: 'Order volume table',
        ),
        message: _deEn(
          context,
          de: 'Keine Auftragsdaten verfuegbar.',
          en: 'No order data available.',
        ),
      );
    }
    final sorted = [...points]..sort((a, b) => b.date.compareTo(a.date));
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
                Expanded(
                  child: Text(
                    _deEn(context, de: 'Auftragsvolumen pro Tag', en: 'Order volume by day'),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoIconButton(
                  title: _deEn(
                    context,
                    de: 'Auftragsvolumen pro Tag',
                    en: 'Order volume by day',
                  ),
                  body: _deEn(
                    context,
                    de: 'Wie viel Auftragsvolumen kommt pro Tag rein? Die Tabelle zeigt fuer jeden Tag: Anzahl der Auftraege, Anzahl der Auftragspositionen und die insgesamt bestellte Menge. Sortiert nach Datum, neueste zuerst.',
                    en: 'How much order volume comes in per day? For each day the table shows: number of orders, number of order lines, and total requested quantity. Sorted by date, newest first.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _deEn(
                context,
                de: 'Neueste zuerst. Quelle: df_order_6mon_schlg_rti3.',
                en: 'Most recent first. Source: df_order_6mon_schlg_rti3.',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFlatDataTable(
              minWidth: 640,
              columns: const <DataColumn2>[
                DataColumn2(label: Text('DATUM'), size: ColumnSize.M),
                DataColumn2(
                  label: Text('AUFTRAEGE'),
                  numeric: true,
                  size: ColumnSize.S,
                ),
                DataColumn2(
                  label: Text('POSITIONEN'),
                  numeric: true,
                  size: ColumnSize.S,
                ),
                DataColumn2(
                  label: Text('MENGE'),
                  numeric: true,
                  size: ColumnSize.S,
                ),
              ],
              rows: sorted.map((p) {
                return DataRow(
                  cells: <DataCell>[
                    DataCell(Text(_formatDate(p.date))),
                    DataCell(Text('${p.orders}')),
                    DataCell(Text('${p.positions}')),
                    DataCell(Text('${p.quantity}')),
                  ],
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickActivityTableCard extends StatelessWidget {
  const _PickActivityTableCard({required this.heatmap});

  final PickActivityHeatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    if (heatmap.cells.isEmpty) {
      return _emptyCard(
        context,
        title: _deEn(
          context,
          de: 'Pick-Aktivitaet (Tabelle)',
          en: 'Pick activity (table)',
        ),
        message: _deEn(
          context,
          de: 'Keine Pick-Daten verfuegbar.',
          en: 'No pick data available.',
        ),
      );
    }
    final sorted = [...heatmap.cells]
      ..sort((a, b) {
        final byPicks = b.picks.compareTo(a.picks);
        if (byPicks != 0) return byPicks;
        if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
        return a.hour.compareTo(b.hour);
      });
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
                Expanded(
                  child: Text(
                    _deEn(
                      context,
                      de: 'Pick-Aktivitaet nach Wochentag & Stunde',
                      en: 'Pick activity by weekday & hour',
                    ),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoIconButton(
                  title: _deEn(
                    context,
                    de: 'Pick-Aktivitaet (Tabelle)',
                    en: 'Pick activity (table)',
                  ),
                  body: _deEn(
                    context,
                    de: 'Wann wird im Lager am meisten gepickt? Die Tabelle gruppiert alle Picks nach Wochentag und Tagesstunde, sortiert nach Haeufigkeit. So siehst du auf einen Blick die Spitzenzeiten. Dieselben Daten wie die Heatmap oberhalb, nur als Liste.',
                    en: 'When does most of the picking happen? The table groups all picks by weekday and hour, sorted by frequency. You can immediately see peak times. Same data as the heatmap above, just as a list.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _deEn(
                context,
                de: 'Sortiert nach Picks. Quelle: df_tpa_6mon_ber03_schlg_rti3.',
                en: 'Sorted by picks. Source: df_tpa_6mon_ber03_schlg_rti3.',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFlatDataTable(
              minWidth: 560,
              columns: const <DataColumn2>[
                DataColumn2(label: Text('WOCHENTAG'), size: ColumnSize.M),
                DataColumn2(
                  label: Text('STUNDE'),
                  numeric: true,
                  size: ColumnSize.S,
                ),
                DataColumn2(
                  label: Text('PICKS'),
                  numeric: true,
                  size: ColumnSize.S,
                ),
              ],
              rows: sorted.map((cell) {
                return DataRow(
                  cells: <DataCell>[
                    DataCell(Text(_weekdayLabel(context, cell.weekday))),
                    DataCell(
                      Text('${cell.hour.toString().padLeft(2, '0')}:00'),
                    ),
                    DataCell(Text('${cell.picks}')),
                  ],
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _emptyCard(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final textTheme = Theme.of(context).textTheme;
  final colorScheme = Theme.of(context).colorScheme;
  return Card(
    elevation: 0,
    color: colorScheme.surfaceContainer,
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
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d.$m.${date.year}';
}

String _weekdayLabel(BuildContext context, int weekday) {
  // SQLite-strftime('%w'): 0 = Sonntag .. 6 = Samstag.
  const de = <String>['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  const en = <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  if (weekday < 0 || weekday > 6) return '?';
  return _deEn(context, de: de[weekday], en: en[weekday]);
}

// Remaining small private widgets

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Einheitlicher Abschnittstitel fÃƒÂ¼r visuelle Struktur im Dashboard.
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: (isWide ? textTheme.titleLarge : textTheme.titleMedium)
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.15),
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

class _DashboardStreamlitFilterBar extends StatefulWidget {
  const _DashboardStreamlitFilterBar();

  @override
  State<_DashboardStreamlitFilterBar> createState() =>
      _DashboardStreamlitFilterBarState();
}

class _DashboardStreamlitFilterBarState
    extends State<_DashboardStreamlitFilterBar> {
  static const List<String> _hallOptions = <String>[
    'Halle 1',
    'Halle 2',
    'Halle 3',
  ];
  static const List<String> _abcOptions = <String>['A', 'B', 'C'];

  final Set<String> _selectedHalls = <String>{};
  final Set<String> _selectedAbc = <String>{};
  RangeValues _utilizationRange = const RangeValues(0, 150);
  bool _onlyOccupied = false;
  int _days = 30;
  int _topArticles = 25;

  int get _activeFilterCount {
    var count = 0;
    if (_selectedHalls.isNotEmpty) {
      count++;
    }
    if (_selectedAbc.isNotEmpty) {
      count++;
    }
    if (_utilizationRange.start > 0 || _utilizationRange.end < 150) {
      count++;
    }
    if (_onlyOccupied) {
      count++;
    }
    if (_days != 30) {
      count++;
    }
    if (_topArticles != 25) {
      count++;
    }
    return count;
  }

  void _toggleHall(String hall) {
    setState(() {
      if (_selectedHalls.contains(hall)) {
        _selectedHalls.remove(hall);
      } else {
        _selectedHalls.add(hall);
      }
    });
  }

  void _toggleAbc(String abc) {
    setState(() {
      if (_selectedAbc.contains(abc)) {
        _selectedAbc.remove(abc);
      } else {
        _selectedAbc.add(abc);
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _selectedHalls.clear();
      _selectedAbc.clear();
      _utilizationRange = const RangeValues(0, 150);
      _onlyOccupied = false;
      _days = 30;
      _topArticles = 25;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primaryContainer.withValues(alpha: 0.42),
            colorScheme.surfaceContainerLowest,
            colorScheme.surface,
          ],
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _deEn(
                          context,
                          de: 'Filter',
                          en: 'Filters',
                        ),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _deEn(
                          context,
                          de: 'Streamlit-Stil direkt unter der Navigation',
                          en: 'Streamlit-style controls under navigation',
                        ),
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _deEn(
                      context,
                      de: 'Aktiv: $_activeFilterCount',
                      en: 'Active: $_activeFilterCount',
                    ),
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _FilterBlock(
                  title: _deEn(context, de: 'Halle', en: 'Hall'),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: _hallOptions
                        .map(
                          (hall) => FilterChip(
                            label: Text(hall),
                            selected: _selectedHalls.contains(hall),
                            onSelected: (_) => _toggleHall(hall),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                _FilterBlock(
                  title: _deEn(context, de: 'ABC-Klasse', en: 'ABC class'),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: _abcOptions
                        .map(
                          (abc) => FilterChip(
                            label: Text(abc),
                            selected: _selectedAbc.contains(abc),
                            onSelected: (_) => _toggleAbc(abc),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _FilterBlock(
              title: _deEn(context, de: 'Auslastung (%)', en: 'Utilization (%)'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  RangeSlider(
                    min: 0,
                    max: 150,
                    divisions: 30,
                    values: _utilizationRange,
                    labels: RangeLabels(
                      _utilizationRange.start.round().toString(),
                      _utilizationRange.end.round().toString(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _utilizationRange = value;
                      });
                    },
                  ),
                  Text(
                    _deEn(
                      context,
                      de: '${_utilizationRange.start.round()}% bis ${_utilizationRange.end.round()}%',
                      en: '${_utilizationRange.start.round()}% to ${_utilizationRange.end.round()}%',
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _FilterBlock(
                  title: _deEn(context, de: 'Durchsatz-Zeitraum', en: 'Throughput window'),
                  child: SizedBox(
                    width: 220,
                    child: Slider(
                      min: 7,
                      max: 180,
                      divisions: 173,
                      value: _days.toDouble(),
                      label: '$_days',
                      onChanged: (value) {
                        setState(() {
                          _days = value.round();
                        });
                      },
                    ),
                  ),
                ),
                _FilterBlock(
                  title: _deEn(context, de: 'Top-Artikel', en: 'Top items'),
                  child: SizedBox(
                    width: 220,
                    child: Slider(
                      min: 5,
                      max: 100,
                      divisions: 19,
                      value: _topArticles.toDouble(),
                      label: _topArticles.toString(),
                      onChanged: (value) {
                        setState(() {
                          _topArticles = value.round();
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SwitchListTile.adaptive(
              value: _onlyOccupied,
              contentPadding: EdgeInsets.zero,
              title: Text(_deEn(context, de: 'Nur belegte Plaetze', en: 'Only occupied slots')),
              subtitle: Text(
                _deEn(
                  context,
                  de: 'Optik wie im Streamlit-Sidebar-Filter',
                  en: 'Matches the Streamlit sidebar look',
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _onlyOccupied = value;
                });
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(_deEn(context, de: 'Zuruecksetzen', en: 'Reset')),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _deEn(
                            context,
                            de: 'Filter-Design aktiv. Daten-Logik folgt im naechsten Schritt.',
                            en: 'Filter design active. Data logic can be wired next.',
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(_deEn(context, de: 'Anwenden', en: 'Apply')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBlock extends StatelessWidget {
  const _FilterBlock({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

enum _KpiGroupFilter { all, flow, capacity }

class _DashboardKpiSection extends StatefulWidget {
  const _DashboardKpiSection({
    this.showSectionHeader = true,
    required this.warehouse,
    required this.appState,
    required this.horizonDays,
    required this.storageSamples,
    required this.utilization,
    required this.totalSlots,
    required this.occupiedSlots,
    required this.freeSlots,
    required this.inboundVsOutbound,
    required this.pickRate,
    required this.dockUtilization,
    required this.qualityHolds,
    required this.slowMoverPositions,
    required this.slowMoverArticles,
    required this.slowMoverMaxIdleDays,
    required this.slowMoverSharePercent,
    required this.openSlowMoverDetails,
  });

  final bool showSectionHeader;
  final Warehouse? warehouse;
  final AppState appState;
  final int horizonDays;
  final List<WarehouseStorageLocation> storageSamples;
  final int utilization;
  final int totalSlots;
  final int occupiedSlots;
  final int freeSlots;
  final int? inboundVsOutbound;
  final int pickRate;
  final int? dockUtilization;
  final int? qualityHolds;
  final int slowMoverPositions;
  final int slowMoverArticles;
  final int? slowMoverMaxIdleDays;
  final int? slowMoverSharePercent;
  final VoidCallback? openSlowMoverDetails;

  @override
  State<_DashboardKpiSection> createState() => _DashboardKpiSectionState();
}

class _DashboardKpiSectionState extends State<_DashboardKpiSection> {
  _KpiGroupFilter _groupFilter = _KpiGroupFilter.all;

  @override
  Widget build(BuildContext context) {
    final warehouse = widget.warehouse;
    final showFlow =
        _groupFilter == _KpiGroupFilter.all ||
        _groupFilter == _KpiGroupFilter.flow;
    final showCapacity =
        _groupFilter == _KpiGroupFilter.all ||
        _groupFilter == _KpiGroupFilter.capacity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.showSectionHeader)
          _SectionHeader(
            title: _deEn(context, de: 'Kern-KPIs', en: 'Core KPIs'),
            subtitle: _deEn(
              context,
              de: 'Filtere die Kennzahlen nach Schwerpunkt und Zeitraum.',
              en: 'Filter KPIs by focus and timeframe.',
            ),
          ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            ChoiceChip(
              label: Text(_deEn(context, de: 'Alle', en: 'All')),
              selected: _groupFilter == _KpiGroupFilter.all,
              onSelected: (_) =>
                  setState(() => _groupFilter = _KpiGroupFilter.all),
            ),
            ChoiceChip(
              label: Text(_deEn(context, de: 'Warenfluss', en: 'Flow')),
              selected: _groupFilter == _KpiGroupFilter.flow,
              onSelected: (_) =>
                  setState(() => _groupFilter = _KpiGroupFilter.flow),
            ),
            ChoiceChip(
              label: Text(_deEn(context, de: 'Kapazitaet', en: 'Capacity')),
              selected: _groupFilter == _KpiGroupFilter.capacity,
              onSelected: (_) =>
                  setState(() => _groupFilter = _KpiGroupFilter.capacity),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _deEn(
            context,
            de: 'Zeitraum aktiv: ${widget.horizonDays} Tage. Die KPIs zeigen aktuell Live-/Ist-Werte.',
            en: 'Active timeframe: ${widget.horizonDays} days. KPIs show current live/actual values.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final fallbackWidth =
                MediaQuery.sizeOf(context).width - (AppSpacing.md * 2);
            final maxWidth =
                constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : fallbackWidth;
            final visibleCount = (showFlow ? 2 : 0) + (showCapacity ? 1 : 0);
            final columns = maxWidth >= 1100
                ? visibleCount.clamp(1, 3)
                : maxWidth >= 700
                ? 2
                : 1;
            final cardWidth = _resolveWrapItemWidth(
              maxWidth: maxWidth,
              columns: columns,
              spacing: AppSpacing.sm,
            );
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                if (showFlow)
                  SizedBox(
                    width: cardWidth,
                    child: DashboardCard(
                      title: _deEn(context, de: 'Wareneingang/Tag', en: 'Inbound/day'),
                      value: warehouse == null
                          ? '-'
                          : '${warehouse.inboundPerDay}',
                      subtitle: _deEn(context, de: 'Eingehende Paletten', en: 'Incoming pallets'),
                      details: warehouse == null
                          ? const <String>[]
                          : <String>[
                              if (widget.inboundVsOutbound != null)
                                _deEn(
                                  context,
                                  de: 'Saldo zu Ausgang: ${widget.inboundVsOutbound! >= 0 ? '+' : ''}${formatNumber(widget.inboundVsOutbound!)} /Tag',
                                  en: 'Delta vs outbound: ${widget.inboundVsOutbound! >= 0 ? '+' : ''}${formatNumber(widget.inboundVsOutbound!)} /day',
                                ),
                              _deEn(
                                context,
                                de: 'Pickrate: ${formatNumber(widget.pickRate)}/h',
                                en: 'Pick rate: ${formatNumber(widget.pickRate)}/h',
                              ),
                              if (widget.dockUtilization != null)
                                _deEn(
                                  context,
                                  de: 'Torauslastung: ${widget.dockUtilization}%',
                                  en: 'Dock utilization: ${widget.dockUtilization}%',
                                ),
                            ],
                      icon: Icons.call_received_rounded,
                      iconColor: AppColors.brandPurple,
                      badgeLabel: _deEn(context, de: 'Live', en: 'Live'),
                      badgeOutlined: true,
                      onTap: () {
                        widget.appState.setViewerHeatmapMetric(
                          ViewerHeatmapMetric.congestion,
                        );
                        widget.appState.setViewerHeatmapVisible(true);
                        context.go('/viewer');
                      },
                    ),
                  ),
                if (showFlow)
                  SizedBox(
                    width: cardWidth,
                    child: DashboardCard(
                      title: _deEn(context, de: 'Warenausgang/Tag', en: 'Outbound/day'),
                      value: warehouse == null
                          ? '-'
                          : '${warehouse.throughputPerDay}',
                      subtitle: _deEn(context, de: 'Sendungen pro Tag', en: 'Shipments per day'),
                      details: warehouse == null
                          ? const <String>[]
                          : <String>[
                              _deEn(
                                context,
                                de: 'Freie Plaetze: ${formatNumber(widget.freeSlots)}',
                                en: 'Free slots: ${formatNumber(widget.freeSlots)}',
                              ),
                              if (widget.dockUtilization != null)
                                _deEn(
                                  context,
                                  de: 'Torauslastung: ${widget.dockUtilization}%',
                                  en: 'Dock utilization: ${widget.dockUtilization}%',
                                ),
                            ],
                      icon: Icons.local_shipping_outlined,
                      iconColor: AppColors.brandOrange,
                      badgeLabel: _deEn(context, de: 'Live', en: 'Live'),
                      badgeOutlined: true,
                      onTap: () {
                        widget.appState.setViewerHeatmapMetric(
                          ViewerHeatmapMetric.pickRate,
                        );
                        widget.appState.setViewerHeatmapVisible(true);
                        context.go('/viewer');
                      },
                    ),
                  ),
                if (showCapacity)
                  SizedBox(
                    width: cardWidth,
                    child: DashboardCard(
                      title: _deEn(context, de: 'Auslastung', en: 'Utilization'),
                      value: '${widget.utilization}%',
                      subtitle: widget.totalSlots == 0
                          ? _deEn(context, de: 'Keine Kapazitaet gepflegt', en: 'No capacity configured')
                          : _deEn(
                              context,
                              de: '${widget.occupiedSlots} von ${widget.totalSlots} Plaetzen belegt',
                              en: '${widget.occupiedSlots} of ${widget.totalSlots} slots occupied',
                            ),
                      details: <String>[
                        _deEn(
                          context,
                          de: 'Freie Plaetze: ${formatNumber(widget.freeSlots)}',
                          en: 'Free slots: ${formatNumber(widget.freeSlots)}',
                        ),
                        if (widget.qualityHolds != null)
                          _deEn(
                            context,
                            de: 'Qualitaetssperren: ${widget.qualityHolds}',
                            en: 'Quality holds: ${widget.qualityHolds}',
                          ),
                      ],
                      icon: Icons.trending_up,
                      iconColor: AppColors.brandBlue,
                      badgeLabel: widget.utilization > 85
                          ? _deEn(context, de: 'Hoch', en: 'High')
                          : _deEn(context, de: 'Stabil', en: 'Stable'),
                      badgeOutlined: true,
                      onTap: () {
                        widget.appState.setViewerHeatmapMetric(
                          ViewerHeatmapMetric.utilization,
                        );
                        widget.appState.setViewerHeatmapVisible(true);
                        context.go('/viewer');
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AbcAnalysisCard extends StatefulWidget {
  const _AbcAnalysisCard({
    required this.warehouse,
    required this.abc,
    this.showHeader = true,
  });

  final bool showHeader;
  final Warehouse? warehouse;
  final AbcAnalysis? abc;

  @override
  State<_AbcAnalysisCard> createState() => _AbcAnalysisCardState();
}

class _AbcAnalysisCardState extends State<_AbcAnalysisCard> {
  final TextEditingController _articleSearchController =
      TextEditingController();
  String _articleSearchQuery = '';
  bool _showAllSlots = false;

  @override
  void dispose() {
    _articleSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ABC-Analyse mit Zeitraumsauswahl (Datenbasis derzeit Momentaufnahme).
    final appState = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final topArticlesLimit = appState.dashboardTopArticlesLimit;
    final selectedHalls = appState.dashboardSelectedHalls;
    final selectedAbcClasses = appState.dashboardSelectedAbcClasses;
    final abc = widget.abc;
    final warehouse = widget.warehouse;
    if (warehouse != null) {
      unawaited(
        appState.ensureAbcArticlesLoadedForWarehouse(
          warehouseId: warehouse.id,
          limit: 10000,
        ),
      );
      unawaited(
        appState.ensureAbcSlotsLoadedForWarehouse(
          warehouseId: warehouse.id,
          limit: 20000,
        ),
      );
    }
    final allStorageSamples = warehouse == null
        ? const <WarehouseStorageLocation>[]
        : appState.getStorageLocationsForWarehouse(warehouse.id);
    final storageSamples = _applyDashboardStorageFilters(
      samples: allStorageSamples,
      appState: appState,
      warehouse: warehouse,
    );
    final dbArticleSummaries = warehouse == null
        ? const <_AbcArticleSummary>[]
        : _mapDbAbcArticleSummaries(
            appState.getAbcArticlesForWarehouse(warehouse.id),
          );
    final articleSummariesBase = dbArticleSummaries.isNotEmpty
        ? dbArticleSummaries
        : _buildArticleSummaries(storageSamples);
    final articleSummaries = selectedAbcClasses.isEmpty
        ? articleSummariesBase
        : articleSummariesBase
            .where((entry) => selectedAbcClasses.contains(entry.abcClass))
            .toList(growable: false);
    final slotSummariesBase = warehouse == null
        ? const <WarehouseAbcSlotSummary>[]
        : appState.getAbcSlotsForWarehouse(warehouse.id);
    final slotSummaries = slotSummariesBase.where((entry) {
      if (selectedHalls.isNotEmpty && !selectedHalls.contains(entry.halle)) {
        return false;
      }
      final abcClass = entry.abcClass.trim().toUpperCase();
      if (selectedAbcClasses.isNotEmpty &&
          !selectedAbcClasses.contains(abcClass)) {
        return false;
      }
      return true;
    }).toList(growable: false);
    final aArticles = _sortedArticlesForClass(articleSummaries, 'A');
    final bArticles = _sortedArticlesForClass(articleSummaries, 'B');
    final cArticles = _sortedArticlesForClass(articleSummaries, 'C');
    final hasSearch = _articleSearchQuery.trim().isNotEmpty;
    final filteredSlots = _filterSlotsByQuery(slotSummaries, _articleSearchQuery);
    final visibleSlots = _showAllSlots
        ? filteredSlots
        : filteredSlots.take(topArticlesLimit).toList(growable: false);
    // Bar + Labels muessen mit der Artikelliste konsistent sein. Wenn echte
    // Artikel-Klassifizierung vorliegt, daraus zaehlen - sonst auf die
    // Platz-basierte Verteilung (warehouse.abcAnalysis) zurueckfallen.
    final hasArticleData = articleSummaries.isNotEmpty;
    final aCount = hasArticleData ? aArticles.length : (abc?.aCount ?? 0);
    final bCount = hasArticleData ? bArticles.length : (abc?.bCount ?? 0);
    final cCount = hasArticleData ? cArticles.length : (abc?.cCount ?? 0);
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
            if (widget.showHeader) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.analytics_outlined, color: colorScheme.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _deEn(context, de: 'ABC Analyse', en: 'ABC analysis'),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _InfoIconButton(
                    title: _deEn(context, de: 'ABC Analyse', en: 'ABC analysis'),
                    body: _deEn(
                      context,
                      de: 'Welche Artikel und Plaetze sind wie wichtig? Die ABC-Analyse teilt nach Bewegungshaeufigkeit in drei Klassen: A = die wenigen Renner, die etwa 80 % aller Bewegungen ausmachen. B = mittelschnelle Artikel/Plaetze (naechste ~15 %). C = der lange Schwanz, der zusammen nur ~5 % der Bewegungen erzeugt. Die Tabelle unten zeigt dir je Platz die berechnete ABC-Klasse und die im System hinterlegte Klasse zum Vergleich. Hilfreich, um Schnelldreher in optimalen Lagen zu platzieren.',
                      en: 'Which items and slots matter most? ABC analysis splits things by movement frequency into three classes: A = the few fast movers that drive roughly 80 % of all activity. B = medium movers (next ~15 %). C = the long tail (~5 % of activity). The table below shows each slot with its calculated ABC class next to the master class for comparison. Useful for placing fast movers in optimal positions.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
                Text(
                  warehouse == null
                    ? _deEn(context, de: 'Keine Lagerauswahl aktiv.', en: 'No warehouse selected.')
                    : _deEn(context, de: 'Warenstruktur nach Umschlagshaeufigkeit.', en: 'Stock structure by turnover frequency.'),
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
            ] else ...<Widget>[
              Align(
                alignment: Alignment.topRight,
                child: _InfoIconButton(
                  title: _deEn(context, de: 'ABC Analyse', en: 'ABC analysis'),
                  body: _deEn(
                    context,
                    de: 'Zwei Sichten: 1) Artikel-ABC = Klassifizierung aus Bewegungen (df_tpa). 2) Platz-ABC = vorhandene Stamm-Klassifizierung der Lagerplaetze (PLATZ.ABC_KLASSE). Die Slot-Tabelle berechnet zusaetzlich ABC_CALC anhand der kumulativen ANZ_PICKS-Verteilung (A = bis 80 %, B = bis 95 %, C = Rest). Suchfeld filtert PLATZ_ID, Artikel, Bezeichnung, Halle und Regal.',
                    en: 'Two views: 1) Item-ABC = classification derived from movements (df_tpa). 2) Slot-ABC = master classification of slots (PLATZ.ABC_KLASSE). The slot table also computes ABC_CALC from the cumulative ANZ_PICKS distribution (A = up to 80 %, B = up to 95 %, C = rest). Search filters by PLATZ_ID, item, description, hall and rack.',
                  ),
                ),
              ),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 640;
                final hasSlotAbc = abc != null && abc.total > 0;
                final articleTile = _AbcDonutTile(
                  title: _deEn(context, de: 'Artikel je ABC-Klasse', en: 'Items by ABC class'),
                  subtitle: _deEn(
                    context,
                    de: 'Pareto aus den Bewegungen.',
                    en: 'Pareto from movements.',
                  ),
                  aCount: aCount,
                  bCount: bCount,
                  cCount: cCount,
                );
                final slotTile = hasSlotAbc
                    ? _AbcDonutTile(
                        title: _deEn(context, de: 'Plaetze je ABC-Klasse', en: 'Slots by ABC class'),
                        subtitle: _deEn(
                          context,
                          de: 'Stamm-Klassifizierung der Lagerplaetze.',
                          en: 'Master classification of slots.',
                        ),
                        aCount: abc.aCount,
                        bCount: abc.bCount,
                        cCount: abc.cCount,
                      )
                    : null;
                if (slotTile == null) {
                  return articleTile;
                }
                if (stacked) {
                  return Column(
                    children: <Widget>[
                      articleTile,
                      const SizedBox(height: AppSpacing.sm),
                      slotTile,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: articleTile),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: slotTile),
                  ],
                );
              },
            ),
            // Sichten oben sind bewusst paarweise: Artikel-ABC (Pareto aus
            // Bewegungen) vs. Platz-ABC (Stamm-Klassifizierung). Sie koennen
            // unterschiedlich aussehen, weil Plaetze fest klassifiziert sind
            // und Artikel sich bewegen.
            const SizedBox(height: AppSpacing.md),
            Text(
              _deEn(context, de: 'Plaetze nach Pick-Volumen', en: 'Slots by pick volume'),
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _articleSearchController,
              onChanged: (value) {
                setState(() {
                  _articleSearchQuery = value;
                });
              },
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                labelText:
                    _deEn(context, de: 'Platz / Artikel suchen', en: 'Search slot / item'),
                hintText:
                    _deEn(context, de: 'z. B. 032003400 oder Regal 20', en: 'e.g. 032003400 or rack 20'),
                suffixIcon: hasSearch
                    ? IconButton(
                        tooltip: _deEn(context, de: 'Suche leeren', en: 'Clear search'),
                        onPressed: () {
                          _articleSearchController.clear();
                          setState(() {
                            _articleSearchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (hasSearch)
              Text(
                _deEn(
                  context,
                  de: '${filteredSlots.length} Treffer fuer "${_articleSearchQuery.trim()}"',
                  en: '${filteredSlots.length} matches for "${_articleSearchQuery.trim()}"',
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            if (hasSearch) const SizedBox(height: AppSpacing.xs),
            if (slotSummaries.isEmpty)
              Text(
                _deEn(
                  context,
                  de: 'Keine Platz-ABC-Daten in warehouse.db gefunden.',
                  en: 'No slot ABC data found in warehouse.db.',
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else if (filteredSlots.isEmpty)
              Text(
                _deEn(
                  context,
                  de: 'Keine Treffer.',
                  en: 'No matches.',
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else ...<Widget>[
              _AbcSlotFlatTable(items: visibleSlots),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _showAllSlots || filteredSlots.length <= topArticlesLimit
                          ? _deEn(
                              context,
                              de: 'Alle ${filteredSlots.length} Plaetze nach Picks',
                              en: 'All ${filteredSlots.length} slots by picks',
                            )
                          : _deEn(
                              context,
                              de: 'Top $topArticlesLimit von ${filteredSlots.length} Plaetzen',
                              en: 'Top $topArticlesLimit of ${filteredSlots.length} slots',
                            ),
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (filteredSlots.length > topArticlesLimit)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showAllSlots = !_showAllSlots;
                        });
                      },
                      icon: Icon(
                        _showAllSlots
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                      ),
                        label: Text(
                          _showAllSlots
                              ? _deEn(
                                  context,
                                  de: 'Nur Top $topArticlesLimit',
                                  en: 'Top $topArticlesLimit only',
                                )
                            : _deEn(
                                context,
                                de: 'Alle ${filteredSlots.length} anzeigen',
                                en: 'Show all ${filteredSlots.length}',
                              ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_AbcArticleSummary> _buildArticleSummaries(
    List<WarehouseStorageLocation> samples,
  ) {
    final byArticle = <String, _AbcArticleAggregate>{};
    for (final sample in samples) {
      final articleId = sample.articleId.trim();
      if (articleId.isEmpty) {
        continue;
      }
      final aggregate = byArticle.putIfAbsent(
        articleId,
        _AbcArticleAggregate.new,
      );
      aggregate.slotCount += 1;
      aggregate.movements30d += sample.movements30d ?? 0;
      final idleDays = sample.daysSinceMovement ?? 0;
      if (idleDays > aggregate.maxIdleDays) {
        aggregate.maxIdleDays = idleDays;
      }
      final abcClass = sample.abcClass.trim().toUpperCase();
      if (abcClass == 'A' || abcClass == 'B' || abcClass == 'C') {
        aggregate.classVotes[abcClass] =
            (aggregate.classVotes[abcClass] ?? 0) + 1;
      }
    }

    return byArticle.entries
        .map((entry) {
          final aggregate = entry.value;
          return _AbcArticleSummary(
            articleId: entry.key,
            abcClass: _resolveAbcClass(aggregate),
            slotCount: aggregate.slotCount,
            movements30d: aggregate.movements30d,
            maxIdleDays: aggregate.maxIdleDays,
          );
        })
        .toList(growable: false);
  }

  List<_AbcArticleSummary> _mapDbAbcArticleSummaries(
    List<WarehouseAbcArticleSummary> items,
  ) {
    if (items.isEmpty) {
      return const <_AbcArticleSummary>[];
    }
    return items
        .where((item) => item.articleId.trim().isNotEmpty)
        .map(
          (item) => _AbcArticleSummary(
            articleId: item.articleId.trim(),
            abcClass: _normalizeAbcClass(item.abcClass),
            slotCount: item.slotCount,
            movements30d: item.movements30d,
            maxIdleDays: item.maxIdleDays,
          ),
        )
        .toList(growable: false);
  }

  String _normalizeAbcClass(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized == 'A' || normalized == 'B' || normalized == 'C') {
      return normalized;
    }
    return 'C';
  }

  String _resolveAbcClass(_AbcArticleAggregate aggregate) {
    if (aggregate.classVotes.isNotEmpty) {
      var bestClass = 'C';
      var bestVotes = -1;
      for (final entry in aggregate.classVotes.entries) {
        if (entry.value > bestVotes) {
          bestVotes = entry.value;
          bestClass = entry.key;
        }
      }
      return bestClass;
    }
    if (aggregate.movements30d >= 40) {
      return 'A';
    }
    if (aggregate.movements30d >= 10) {
      return 'B';
    }
    return 'C';
  }

  List<_AbcArticleSummary> _sortedArticlesForClass(
    List<_AbcArticleSummary> input,
    String abcClass,
  ) {
    final filtered = input
        .where((entry) => entry.abcClass == abcClass)
        .toList(growable: false);
    final sorted = [...filtered];
    if (abcClass == 'C') {
      sorted.sort((a, b) {
        final byMove = a.movements30d.compareTo(b.movements30d);
        if (byMove != 0) {
          return byMove;
        }
        final byIdle = b.maxIdleDays.compareTo(a.maxIdleDays);
        if (byIdle != 0) {
          return byIdle;
        }
        return a.articleId.compareTo(b.articleId);
      });
      return sorted;
    }
    sorted.sort((a, b) {
      final byMove = b.movements30d.compareTo(a.movements30d);
      if (byMove != 0) {
        return byMove;
      }
      final bySlots = b.slotCount.compareTo(a.slotCount);
      if (bySlots != 0) {
        return bySlots;
      }
      return a.articleId.compareTo(b.articleId);
    });
    return sorted;
  }

  List<WarehouseAbcSlotSummary> _filterSlotsByQuery(
    List<WarehouseAbcSlotSummary> input,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return input;
    }
    return input.where((entry) {
      return entry.placeId.toLowerCase().contains(normalized) ||
          entry.articleId.toLowerCase().contains(normalized) ||
          entry.articleDescription.toLowerCase().contains(normalized) ||
          entry.halle.toLowerCase().contains(normalized) ||
          entry.regal.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }
}

class _AbcArticleAggregate {
  int slotCount = 0;
  int movements30d = 0;
  int maxIdleDays = 0;
  final Map<String, int> classVotes = <String, int>{};
}

class _AbcArticleSummary {
  const _AbcArticleSummary({
    required this.articleId,
    required this.abcClass,
    required this.slotCount,
    required this.movements30d,
    required this.maxIdleDays,
  });

  final String articleId;
  final String abcClass;
  final int slotCount;
  final int movements30d;
  final int maxIdleDays;
}

String _hallForRegal(String regalStr) {
  final regal = int.tryParse(regalStr.trim()) ?? 0;
  if (regal >= 1 && regal <= 16) return 'Halle 1';
  if (regal >= 17 && regal <= 32) return 'Halle 2';
  return 'Halle 3';
}

class _AbcSlotFlatTable extends StatelessWidget {
  const _AbcSlotFlatTable({required this.items});

  final List<WarehouseAbcSlotSummary> items;

  @override
  Widget build(BuildContext context) {
    return AppFlatDataTable(
      minWidth: 1180,
      columns: const <DataColumn2>[
        DataColumn2(label: Text('ARTIKEL'), size: ColumnSize.M),
        DataColumn2(label: Text('BEZEICHNUNG'), size: ColumnSize.L),
        DataColumn2(label: Text('ABC_KLASSE'), size: ColumnSize.S),
        DataColumn2(label: Text('PLATZ_ID'), size: ColumnSize.M),
        DataColumn2(label: Text('HALLE'), size: ColumnSize.S),
        DataColumn2(label: Text('REGAL'), numeric: true, size: ColumnSize.S),
        DataColumn2(label: Text('FACH'), numeric: true, size: ColumnSize.S),
        DataColumn2(label: Text('EBENE'), numeric: true, size: ColumnSize.S),
        DataColumn2(
            label: Text('ANZ_PICKS'), numeric: true, size: ColumnSize.S),
        DataColumn2(
          label: Text('CUMULATIVE_%'),
          numeric: true,
          size: ColumnSize.S,
        ),
        DataColumn2(label: Text('ABC_CALC'), size: ColumnSize.S),
      ],
      rows: items.map((item) {
        return DataRow(
          cells: <DataCell>[
            DataCell(Text(item.articleId.isEmpty ? '-' : item.articleId)),
            DataCell(
              Text(
                item.articleDescription.isEmpty
                    ? '-'
                    : item.articleDescription,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(Text(item.abcClass.isEmpty ? '-' : item.abcClass)),
            DataCell(Text(item.placeId)),
            DataCell(Text(_hallForRegal(item.regal))),
            DataCell(Text(item.regal)),
            DataCell(Text(item.fach)),
            DataCell(Text(item.ebene)),
            DataCell(Text('${item.anzPicks}')),
            DataCell(Text(item.cumulativePct.toStringAsFixed(4))),
            DataCell(Text(item.abcCalc)),
          ],
        );
      }).toList(growable: false),
    );
  }
}

class _AbcDonutTile extends StatelessWidget {
  const _AbcDonutTile({
    required this.title,
    required this.subtitle,
    required this.aCount,
    required this.bCount,
    required this.cCount,
  });

  final String title;
  final String subtitle;
  final int aCount;
  final int bCount;
  final int cCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _AbcDonutBody(aCount: aCount, bCount: bCount, cCount: cCount),
        ],
      ),
    );
  }
}

class _AbcDonutBody extends StatelessWidget {
  const _AbcDonutBody({
    required this.aCount,
    required this.bCount,
    required this.cCount,
  });

  final int aCount;
  final int bCount;
  final int cCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = aCount + bCount + cCount;
    final segments = <_AbcDonutSegment>[
      _AbcDonutSegment(label: 'A', value: aCount, color: AppColors.abcA),
      _AbcDonutSegment(label: 'B', value: bCount, color: AppColors.abcB),
      _AbcDonutSegment(label: 'C', value: cCount, color: AppColors.abcC),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 280;
        final donut = SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _AbcDonutPainter(
              segments: segments,
              trackColor:
                  colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _formatThousands(total),
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _deEn(context, de: 'gesamt', en: 'total'),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final seg in segments)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _AbcLegendRow(segment: seg, total: total),
              ),
          ],
        );
        if (stacked) {
          return Column(
            children: <Widget>[
              donut,
              const SizedBox(height: AppSpacing.sm),
              Align(alignment: Alignment.centerLeft, child: legend),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            donut,
            const SizedBox(width: AppSpacing.md),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _AbcDonutSegment {
  const _AbcDonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _AbcDonutPainter extends CustomPainter {
  _AbcDonutPainter({
    required this.segments,
    required this.trackColor,
  });

  final List<_AbcDonutSegment> segments;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<int>(0, (s, seg) => s + seg.value);
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = size.shortestSide * 0.18;
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Hintergrund-Ring.
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (total <= 0) return;

    // Segmente — Lueckenabstand fuer modernen Look.
    const gapDeg = 3.0;
    final segCount = segments.where((s) => s.value > 0).length;
    final gapRad = (math.pi / 180) * gapDeg;
    final totalGap = segCount > 1 ? gapRad * segCount : 0;
    final available = math.pi * 2 - totalGap;
    var start = -math.pi / 2 + (segCount > 1 ? gapRad / 2 : 0);
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = (seg.value / total) * available;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      start += sweep + gapRad;
    }
  }

  @override
  bool shouldRepaint(covariant _AbcDonutPainter old) =>
      old.segments != segments || old.trackColor != trackColor;
}

class _AbcLegendRow extends StatelessWidget {
  const _AbcLegendRow({required this.segment, required this.total});

  final _AbcDonutSegment segment;
  final int total;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final pct = total <= 0 ? 0 : ((segment.value / total) * 100).round();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: segment.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            segment.label,
            style: textTheme.labelLarge?.copyWith(
              color: segment.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _formatThousands(segment.value),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$pct %',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OperationalActionItem {
  const _OperationalActionItem({
    required this.id,
    required this.title,
    required this.description,
    this.explanation,
    this.whenToRun,
    this.whatHappens,
    required this.detailPoints,
    this.checklist = const <String>[],
    required this.reason,
    required this.recommended,
    required this.icon,
    required this.onPressed,
    this.extra,
    this.onExecute,
    this.executeLabel = 'Aktion starten',
    this.executeDoneLabel = 'Aktion geplant',
    this.executeSummary,
    this.executeCount = 0,
  });

  final String id;
  final String title;
  final String description;
  final String? explanation;
  final String? whenToRun;
  final String? whatHappens;
  final List<String> detailPoints;
  final List<String> checklist;
  final String reason;
  final bool recommended;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Optionaler Block fuer datenbasierte Empfehlungen (z. B. konkrete Umlager-
  /// Kandidaten aus der DB). Wird im aufgeklappten Detail-Bereich gezeigt.
  final Widget? extra;

  /// Optionaler Start direkt im Dashboard (ohne Seitenwechsel).
  final Future<void> Function()? onExecute;
  final String executeLabel;
  final String executeDoneLabel;
  final String? executeSummary;
  final int executeCount;
}

class _OperationalActionsCard extends StatefulWidget {
  const _OperationalActionsCard({required this.items});

  final List<_OperationalActionItem> items;

  @override
  State<_OperationalActionsCard> createState() =>
      _OperationalActionsCardState();
}

class _OperationalActionsCardState extends State<_OperationalActionsCard> {
  int _selectedTabIndex = 0;
  final Set<String> _executedItemIds = <String>{};
  final Set<String> _executingItemIds = <String>{};

  String _tabLabel(_OperationalActionItem item) {
    final slashIndex = item.title.indexOf('/');
    if (slashIndex > 0) {
      return item.title.substring(0, slashIndex).trim();
    }
    return item.title;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final selectedIndex = _selectedTabIndex.clamp(0, items.length - 1).toInt();
    final selectedItem = items[selectedIndex];
    final isExecuted = _executedItemIds.contains(selectedItem.id);
    final isExecuting = _executingItemIds.contains(selectedItem.id);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
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
            Text(
              _deEn(context, de: 'Steueraktionen', en: 'Control actions'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _deEn(
                context,
                de: 'Als Registerkarten aufgebaut: pro Massnahme eine eigene Ansicht.',
                en: 'Built as tabs: one dedicated view per action.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List<Widget>.generate(items.length, (index) {
                  final item = items[index];
                  final selected = index == selectedIndex;
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == items.length - 1 ? 0 : AppSpacing.xs,
                    ),
                    child: ChoiceChip(
                      avatar: Icon(item.icon, size: 16),
                      label: Text(_tabLabel(item)),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _selectedTabIndex = index;
                      }),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selectedItem.recommended
                      ? AppColors.warningBorder
                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: selectedItem.recommended
                                ? AppColors.warningLight
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            selectedItem.icon,
                            size: 18,
                            color: selectedItem.recommended
                                ? AppColors.warningDark
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                selectedItem.title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selectedItem.description,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _ActionStateBadge(
                          recommended: selectedItem.recommended,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      selectedItem.reason,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selectedItem.recommended
                            ? AppColors.warningDark
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        StatusPill(
                          icon: selectedItem.recommended
                              ? Icons.priority_high_rounded
                              : Icons.tune_rounded,
                          label: selectedItem.recommended
                              ? _deEn(context, de: 'Prioritaet hoch', en: 'High priority')
                              : _deEn(context, de: 'Prioritaet normal', en: 'Normal priority'),
                          backgroundColor: selectedItem.recommended
                              ? AppColors.warningLight
                              : colorScheme.surfaceContainerHighest,
                          foregroundColor: selectedItem.recommended
                              ? AppColors.warningDark
                              : colorScheme.onSurfaceVariant,
                          borderColor: selectedItem.recommended
                              ? AppColors.warningBorder
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        StatusPill(
                          icon: selectedItem.onExecute != null
                              ? Icons.play_circle_outline_rounded
                              : Icons.open_in_new_rounded,
                          label: selectedItem.onExecute != null
                              ? _deEn(context, de: 'Direkt im Dashboard', en: 'Run in dashboard')
                              : _deEn(context, de: 'Im Viewer ausfuehren', en: 'Run in viewer'),
                          compact: true,
                        ),
                        if (selectedItem.executeCount > 0)
                          StatusPill(
                            icon: Icons.list_alt_rounded,
                            label: _deEn(
                              context,
                              de: '${selectedItem.executeCount} Kandidaten',
                              en: '${selectedItem.executeCount} candidates',
                            ),
                            compact: true,
                          ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        _deEn(context, de: 'Details im Dashboard', en: 'Details in dashboard'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (selectedItem.explanation
                                              ?.trim()
                                              .isNotEmpty ??
                                          false) ...<Widget>[
                                        Text(
                                          _deEn(
                                            context,
                                            de: 'Was bedeutet das konkret?',
                                            en: 'What this means in practice',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          selectedItem.explanation!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                      ],
                                      if (selectedItem.whenToRun
                                              ?.trim()
                                              .isNotEmpty ??
                                          false) ...<Widget>[
                                        _ActionInfoRow(
                                          icon: Icons.schedule_rounded,
                                          label: _deEn(
                                            context,
                                            de: 'Wann einsetzen',
                                            en: 'When to run',
                                          ),
                                          text: selectedItem.whenToRun!,
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                      ],
                                      if (selectedItem.whatHappens
                                              ?.trim()
                                              .isNotEmpty ??
                                          false) ...<Widget>[
                                        _ActionInfoRow(
                                          icon: Icons.auto_graph_rounded,
                                          label: _deEn(
                                            context,
                                            de: 'Was passiert nach Start',
                                            en: 'What happens after start',
                                          ),
                                          text: selectedItem.whatHappens!,
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                      ],
                                      ...selectedItem.detailPoints.map(
                                        (point) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: _ActionBulletTile(text: point),
                                        ),
                                      ),
                                      if (selectedItem.checklist.isNotEmpty)
                                        const SizedBox(height: AppSpacing.xs),
                                      if (selectedItem.checklist.isNotEmpty)
                                        Text(
                                          _deEn(context, de: 'Checkliste', en: 'Checklist'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      if (selectedItem.checklist.isNotEmpty)
                                        const SizedBox(height: 4),
                                      ...selectedItem.checklist.map(
                                        (point) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 1,
                                                ),
                                                child: Icon(
                                                  Icons.check_circle_outline,
                                                  size: 14,
                                                  color: colorScheme.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  point,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (selectedItem.extra != null) ...<Widget>[
                                        const SizedBox(height: AppSpacing.sm),
                                        const Divider(height: 1),
                                        const SizedBox(height: AppSpacing.sm),
                                        selectedItem.extra!,
                                      ],
                                      if (selectedItem.onExecute != null) ...<Widget>[
                                        const SizedBox(height: AppSpacing.sm),
                                        Wrap(
                                          spacing: AppSpacing.xs,
                                          runSpacing: AppSpacing.xs,
                                          children: <Widget>[
                                            FilledButton.icon(
                                              onPressed: isExecuting
                                                  ? null
                                                  : () => _executeInDashboard(
                                                        context,
                                                        selectedItem,
                                                      ),
                                              icon: isExecuting
                                                  ? const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.play_arrow_rounded,
                                                    ),
                                              label: Text(
                                                isExecuting
                                                    ? _deEn(context, de: 'Wird gestartet...', en: 'Starting...')
                                                    : selectedItem.executeLabel,
                                              ),
                                            ),
                                            if (isExecuted)
                                              Chip(
                                                avatar: const Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 16,
                                                ),
                                                label: Text(
                                                  selectedItem.executeDoneLabel,
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (isExecuted &&
                                            (selectedItem.executeSummary
                                                    ?.trim()
                                                    .isNotEmpty ??
                                                false)) ...<Widget>[
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            selectedItem.executeSummary!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ],
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        _deEn(
                                          context,
                                          de: 'Ansicht bleibt im Dashboard, kein Seitenwechsel.',
                                          en: 'View stays in dashboard, no page switch.',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedItem.onPressed == null
                                            ? _deEn(context, de: 'Aktion derzeit nicht verfuegbar.', en: 'Action currently not available.')
                                            : _deEn(context, de: 'Aktion ist vorbereitet und kann intern ausgefuehrt werden.', en: 'Action is prepared and can be executed internally.'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeInDashboard(
    BuildContext context,
    _OperationalActionItem item,
  ) async {
    final task = item.onExecute;
    if (task == null || _executingItemIds.contains(item.id)) {
      return;
    }
    setState(() {
      _executingItemIds.add(item.id);
    });
    try {
      await task();
      if (!mounted) {
        return;
      }
      setState(() {
        _executedItemIds.add(item.id);
      });
      final msg = item.executeCount > 0
          ? _deEn(
              context,
              de: '${item.executeDoneLabel}: ${item.executeCount} Positionen.',
              en: '${item.executeDoneLabel}: ${item.executeCount} positions.',
            )
          : item.executeDoneLabel;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _executingItemIds.remove(item.id);
        });
      }
    }
  }
}

class _ActionStateBadge extends StatelessWidget {
  const _ActionStateBadge({required this.recommended});

  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return StatusPill(
      label: recommended
          ? _deEn(context, de: 'Empfohlen', en: 'Recommended')
          : _deEn(context, de: 'Optional', en: 'Optional'),
      backgroundColor: recommended
          ? AppColors.warningLight
          : colorScheme.surfaceContainerHighest,
      foregroundColor: recommended
          ? AppColors.warningDark
          : colorScheme.onSurfaceVariant,
      borderColor: recommended
          ? AppColors.warningBorder
          : colorScheme.outlineVariant.withValues(alpha: 0.4),
      compact: true,
    );
  }
}

class _ActionInfoRow extends StatelessWidget {
  const _ActionInfoRow({
    required this.icon,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  children: <InlineSpan>[
                    TextSpan(
                      text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: text),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBulletTile extends StatelessWidget {
  const _ActionBulletTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 7,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 15,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
