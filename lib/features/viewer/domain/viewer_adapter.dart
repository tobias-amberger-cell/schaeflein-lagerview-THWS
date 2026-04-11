import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../models/viewer_heatmap.dart';
import '../../../models/warehouse.dart';
import 'viewer_type.dart';

abstract class ViewerAdapter {
  ViewerType get type;
  String get displayName;
  String get statusText;
  bool get isImplemented;

  Widget buildViewerCanvas(BuildContext context, Warehouse warehouse);

  Future<String> resetView(AppLocalizations l10n, Warehouse warehouse);
  Future<String> showZones(AppLocalizations l10n, Warehouse warehouse);
  Future<String> startTour(AppLocalizations l10n, Warehouse warehouse);
  Future<String> showHeatmap(
    AppLocalizations l10n,
    Warehouse warehouse,
    ViewerHeatmapMetric metric,
  );
  Future<String> hideHeatmap(AppLocalizations l10n, Warehouse warehouse);
}
