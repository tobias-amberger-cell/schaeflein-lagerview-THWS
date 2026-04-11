enum NotificationSeverity {
  info,
  warning,
  critical,
}

extension NotificationSeverityLabel on NotificationSeverity {
  String get labelKey {
    switch (this) {
      case NotificationSeverity.info:
        return 'severityInfo';
      case NotificationSeverity.warning:
        return 'severityWarning';
      case NotificationSeverity.critical:
        return 'severityCritical';
    }
  }
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.severity,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final NotificationSeverity severity;
  final bool isRead;

  AppNotificationItem copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? createdAt,
    NotificationSeverity? severity,
    bool? isRead,
  }) {
    return AppNotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      severity: severity ?? this.severity,
      isRead: isRead ?? this.isRead,
    );
  }
}
