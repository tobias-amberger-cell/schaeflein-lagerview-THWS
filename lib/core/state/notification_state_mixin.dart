import 'package:flutter/widgets.dart';

import '../../models/app_notification_item.dart';

mixin NotificationStateMixin on ChangeNotifier {
  final List<AppNotificationItem> notificationItems = <AppNotificationItem>[];

  List<AppNotificationItem> get notifications =>
      List<AppNotificationItem>.unmodifiable(notificationItems);

  int get unreadNotificationCount =>
      notificationItems.where((item) => !item.isRead).length;

  void initNotifications() {
    notificationItems.addAll(_defaultNotifications());
  }

  void markNotificationAsRead(String notificationId) {
    final index =
        notificationItems.indexWhere((item) => item.id == notificationId);
    if (index == -1) {
      return;
    }
    final current = notificationItems[index];
    notificationItems[index] = current.copyWith(isRead: true);
    notifyListeners();
  }

  void markAllNotificationsAsRead() {
    for (var i = 0; i < notificationItems.length; i++) {
      notificationItems[i] = notificationItems[i].copyWith(isRead: true);
    }
    notifyListeners();
  }

  void dismissNotification(String notificationId) {
    notificationItems.removeWhere((item) => item.id == notificationId);
    notifyListeners();
  }

  List<AppNotificationItem> _defaultNotifications() {
    final now = DateTime.now();
    return <AppNotificationItem>[
      AppNotificationItem(
        id: 'notif-001',
        title: 'Heatmap aktualisiert',
        message: 'Live-Analyse für Zone A4 ist verfügbar.',
        createdAt: now.subtract(const Duration(minutes: 12)),
        severity: NotificationSeverity.info,
      ),
      AppNotificationItem(
        id: 'notif-002',
        title: 'Kapazität kritisch',
        message: 'Auslastung über 92% in Hochregallager Nord.',
        createdAt: now.subtract(const Duration(hours: 3)),
        severity: NotificationSeverity.warning,
      ),
    ];
  }
}
