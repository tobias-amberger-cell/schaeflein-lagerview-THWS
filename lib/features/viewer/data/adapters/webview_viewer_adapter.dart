import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse.dart';
import '../../domain/viewer_adapter.dart';
import '../../domain/viewer_type.dart';

class WebViewViewerAdapter extends ViewerAdapter {
  @override
  ViewerType get type => ViewerType.webView;

  @override
  String get displayName => 'webViewViewerName';

  @override
  String get statusText => 'adapterStatusPrepared';

  @override
  bool get isImplemented => false;

  @override
  Widget buildViewerCanvas(BuildContext context, Warehouse warehouse) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.language, size: 68),
              const SizedBox(height: 12),
              Text(
                context.tr('webViewPlaceholderTitle'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('webViewPlaceholderSubtitle'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<String> resetView(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('webViewAdapterInactive');
  }

  @override
  Future<String> showZones(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('webViewZonesPending');
  }

  @override
  Future<String> startTour(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('webViewTourPending');
  }

  @override
  Future<String> showHeatmap(
    AppLocalizations l10n,
    Warehouse warehouse,
    ViewerHeatmapMetric metric,
  ) async {
    return l10n.tr('webViewHeatmapPending');
  }

  @override
  Future<String> hideHeatmap(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('webViewHeatmapPending');
  }
}
