enum UserRole {
  admin,
  operator,
  viewer,
}

extension UserRoleLabel on UserRole {
  String get labelKey {
    switch (this) {
      case UserRole.admin:
        return 'roleAdmin';
      case UserRole.operator:
        return 'roleOperator';
      case UserRole.viewer:
        return 'roleViewer';
    }
  }
}
