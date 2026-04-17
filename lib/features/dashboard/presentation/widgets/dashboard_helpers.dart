import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/app_notification_item.dart';
import '../../../../models/control_tower_event.dart';
import '../../../../models/control_tower_ticket.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse.dart';

String formatNumber(int value) {
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)} Mio';
  }
  if (absValue >= 10000) {
    return '${(value / 1000).toStringAsFixed(1)} Tsd';
  }
  return value.toString();
}

String formatRelativeTime(DateTime? timestamp) {
  if (timestamp == null) {
    return 'Noch nicht synchronisiert';
  }
  final diff = DateTime.now().difference(timestamp);
  if (diff.inMinutes < 1) {
    return 'Gerade eben';
  }
  if (diff.inMinutes < 60) {
    return 'Vor ${diff.inMinutes} Min';
  }
  if (diff.inHours < 24) {
    return 'Vor ${diff.inHours} Std';
  }
  return 'Vor ${diff.inDays} Tagen';
}

List<ViewerHeatmapEntry> topHeatmapZones(
  List<ViewerHeatmapEntry> data,
  ViewerHeatmapMetric metric, {
  int maxItems = 6,
}) {
  if (data.isEmpty) {
    return const <ViewerHeatmapEntry>[];
  }
  final sorted = List<ViewerHeatmapEntry>.from(data)
    ..sort((a, b) => b.valueFor(metric).compareTo(a.valueFor(metric)));
  return sorted.take(maxItems).toList(growable: false);
}

Color severityColor(NotificationSeverity severity) {
  switch (severity) {
    case NotificationSeverity.info:
      return AppColors.brandBlue;
    case NotificationSeverity.warning:
      return AppColors.warning;
    case NotificationSeverity.critical:
      return AppColors.error;
  }
}

Color ticketSeverityColor(ControlTowerEventSeverity severity) {
  switch (severity) {
    case ControlTowerEventSeverity.info:
      return AppColors.brandBlue;
    case ControlTowerEventSeverity.warning:
      return AppColors.warning;
    case ControlTowerEventSeverity.critical:
      return AppColors.error;
  }
}

String ticketStatusLabel(ControlTowerTicketStatus status) {
  switch (status) {
    case ControlTowerTicketStatus.open:
      return 'Offen';
    case ControlTowerTicketStatus.inProgress:
      return 'In Arbeit';
    case ControlTowerTicketStatus.resolved:
      return 'Gelöst';
  }
}

String ticketTitle(ControlTowerTicket ticket) {
  switch (ticket.titleKey) {
    case 'controlTowerTicketCapacityTitle':
      return 'Kapazität kritisch';
    case 'controlTowerTicketInventoryTitle':
      return 'Inventur prüfen';
    default:
      return ticket.titleKey;
  }
}

String heatmapMetricLabel(ViewerHeatmapMetric metric) {
  switch (metric) {
    case ViewerHeatmapMetric.utilization:
      return 'Auslastung';
    case ViewerHeatmapMetric.pickRate:
      return 'Pickrate';
    case ViewerHeatmapMetric.congestion:
      return 'Stau';
    case ViewerHeatmapMetric.abcA:
      return 'A-Anteil';
  }
}

Color heatmapValueColor(double value) {
  if (value >= 0.85) {
    return AppColors.error;
  }
  if (value >= 0.65) {
    return AppColors.warning;
  }
  if (value >= 0.4) {
    return AppColors.brandSky;
  }
  return AppColors.success;
}

String statusLabel(WarehouseStatus status) {
  switch (status) {
    case WarehouseStatus.online:
      return 'Online';
    case WarehouseStatus.limited:
      return 'Eingeschränkt';
    case WarehouseStatus.maintenance:
      return 'Wartung';
  }
}

Color statusColor(WarehouseStatus status) {
  switch (status) {
    case WarehouseStatus.online:
      return AppColors.success;
    case WarehouseStatus.limited:
      return AppColors.warning;
    case WarehouseStatus.maintenance:
      return AppColors.error;
  }
}

class RiskTone {
  const RiskTone({
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final IconData icon;
}

RiskTone riskToneForScore(int score) {
  if (score >= 85) {
    return const RiskTone(
      label: 'Kritisch',
      foreground: AppColors.errorDark,
      background: AppColors.errorLight,
      border: AppColors.errorBorder,
      icon: Icons.error_outline_rounded,
    );
  }
  if (score >= 65) {
    return const RiskTone(
      label: 'Achten',
      foreground: AppColors.warningDark,
      background: AppColors.warningLight,
      border: AppColors.warningBorder,
      icon: Icons.warning_amber_rounded,
    );
  }
  return const RiskTone(
    label: 'Stabil',
    foreground: AppColors.successDark,
    background: AppColors.successLight,
    border: AppColors.successBorder,
    icon: Icons.check_circle_outline_rounded,
  );
}

/// Small inline KPI chip used in multiple dashboard cards.
class InlineKpi extends StatelessWidget {
  const InlineKpi({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$label: $value',
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
