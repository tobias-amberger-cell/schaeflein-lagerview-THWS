import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../models/app_notification_item.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/ssi_branding.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final notifications = appState.notifications;

    return Scaffold(
      appBar: AppBar(
        title: CompanyAppBarTitle(sectionTitle: context.tr('notifications')),
        actions: <Widget>[
          if (notifications.isNotEmpty)
            TextButton(
              onPressed: appState.markAllNotificationsAsRead,
              child: Text(context.tr('markAllRead')),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.desktop),
            child: notifications.isEmpty
                ? EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: context.tr('noNotifications'),
                    message: context.tr('noNotificationsMsg'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _NotificationCard(notification: notification);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final AppNotificationItem notification;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final color = switch (notification.severity) {
      NotificationSeverity.info => Colors.blue,
      NotificationSeverity.warning => Colors.orange,
      NotificationSeverity.critical => Colors.redAccent,
    };
    final icon = switch (notification.severity) {
      NotificationSeverity.info => Icons.info_outline,
      NotificationSeverity.warning => Icons.warning_amber_outlined,
      NotificationSeverity.critical => Icons.error_outline,
    };

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(
          notification.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.w800,
              ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(notification.message),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${context.tr(notification.severity.labelKey)} | ${_relativeTime(context, notification.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: context.tr('remove'),
          onPressed: () => appState.dismissNotification(notification.id),
          icon: const Icon(Icons.close),
        ),
        onTap: () => appState.markNotificationAsRead(notification.id),
      ),
    );
  }

  String _relativeTime(BuildContext context, DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return context.tr('justNow');
    }
    if (diff.inMinutes < 60) {
      return context.tr('minutesAgo', <String, Object>{'count': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return context.tr('hoursAgo', <String, Object>{'count': diff.inHours});
    }
    return context.tr('daysAgo', <String, Object>{'count': diff.inDays});
  }
}
