import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse.dart';
import '../../domain/viewer_adapter.dart';
import '../../domain/viewer_type.dart';

class NativePlaceholderViewerAdapter extends ViewerAdapter {
  @override
  ViewerType get type => ViewerType.nativePlaceholder;

  @override
  String get displayName => 'nativeViewerName';

  @override
  String get statusText => 'adapterStatusActive';

  @override
  bool get isImplemented => true;

  @override
  Widget buildViewerCanvas(BuildContext context, Warehouse warehouse) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: <Color>[
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.view_in_ar_outlined,
              size: 82,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              context.tr('nativePlaceholderTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'nativePlaceholderSubtitle',
                <String, Object>{'name': warehouse.name},
              ),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<String> resetView(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr(
      'adapterResetMessage',
      <String, Object>{'name': warehouse.name},
    );
  }

  @override
  Future<String> showZones(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr(
      'adapterShowZonesMessage',
      <String, Object>{
        'count': warehouse.zoneCount,
        'name': warehouse.name,
      },
    );
  }

  @override
  Future<String> startTour(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr(
      'adapterStartTourMessage',
      <String, Object>{'name': warehouse.name},
    );
  }

  @override
  Future<String> showHeatmap(
    AppLocalizations l10n,
    Warehouse warehouse,
    ViewerHeatmapMetric metric,
  ) async {
    return l10n.tr(
      'adapterHeatmapShownMessage',
      <String, Object>{
        'metric': l10n.tr(metric.labelKey),
        'name': warehouse.name,
      },
    );
  }

  @override
  Future<String> hideHeatmap(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr(
      'adapterHeatmapHiddenMessage',
      <String, Object>{'name': warehouse.name},
    );
  }
}
