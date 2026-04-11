import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse.dart';
import '../../domain/viewer_adapter.dart';
import '../../domain/viewer_type.dart';

class UnityViewerAdapter extends ViewerAdapter {
  @override
  ViewerType get type => ViewerType.unity;

  @override
  String get displayName => 'unityViewerName';

  @override
  String get statusText => 'adapterStatusPrepared';

  @override
  bool get isImplemented => false;

  @override
  Widget buildViewerCanvas(BuildContext context, Warehouse warehouse) {
    return _IntegrationPlaceholder(
      icon: Icons.videogame_asset_outlined,
      title: context.tr('unityPlaceholderTitle'),
      subtitle: context.tr('unityPlaceholderSubtitle'),
    );
  }

  @override
  Future<String> resetView(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('unityAdapterInactive');
  }

  @override
  Future<String> showZones(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('unityZonesPending');
  }

  @override
  Future<String> startTour(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('unityTourPending');
  }

  @override
  Future<String> showHeatmap(
    AppLocalizations l10n,
    Warehouse warehouse,
    ViewerHeatmapMetric metric,
  ) async {
    return l10n.tr('unityHeatmapPending');
  }

  @override
  Future<String> hideHeatmap(AppLocalizations l10n, Warehouse warehouse) async {
    return l10n.tr('unityHeatmapPending');
  }
}

class _IntegrationPlaceholder extends StatelessWidget {
  const _IntegrationPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
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
              Icon(icon, size: 68),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
