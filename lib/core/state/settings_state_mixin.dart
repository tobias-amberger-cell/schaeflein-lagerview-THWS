import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/viewer/domain/viewer_type.dart';
import '../../models/user_role.dart';

enum AutoEscalationPreset {
  conservative,
  standard,
  aggressive,
  custom,
}

extension AutoEscalationPresetLabel on AutoEscalationPreset {
  String get labelKey {
    switch (this) {
      case AutoEscalationPreset.conservative:
        return 'autoEscalationPresetConservative';
      case AutoEscalationPreset.standard:
        return 'autoEscalationPresetStandard';
      case AutoEscalationPreset.aggressive:
        return 'autoEscalationPresetAggressive';
      case AutoEscalationPreset.custom:
        return 'autoEscalationPresetCustom';
    }
  }
}

mixin SettingsStateMixin on ChangeNotifier {
  static const String prefDarkMode = 'settings.dark_mode';
  static const String prefNotificationsEnabled = 'settings.notifications_enabled';
  static const String prefLanguageCode = 'settings.language_code';
  static const String prefViewerType = 'settings.viewer_type';
  static const String prefUserRole = 'settings.user_role';
  static const String prefAutoEscFirstMinutes = 'settings.auto_escalation_first';
  static const String prefAutoEscSecondMinutes = 'settings.auto_escalation_second';
  static const String prefViewerHeatmapZoneTypeFilter =
      'settings.viewer.heatmap_zone_type_filter';
  static const String prefViewerHeatmapSeverityFilter =
      'settings.viewer.heatmap_severity_filter';
  static const String prefViewerHeatmapLiveModeEnabled =
      'settings.viewer.heatmap_live_mode_enabled';
  static const String prefViewerHeatmapAutoFocusEnabled =
      'settings.viewer.heatmap_auto_focus_enabled';
  static const String prefStorageFilterQuery = 'viewer.storage.filter_query';
  static const String prefStorageSortByAbc = 'viewer.storage.sort_abc';
  static const String prefStorageVisibleCount = 'viewer.storage.visible_count';
  static const String prefSettingsLastSavedAt = 'settings.last_saved_at';

  bool settingsIsDarkMode = false;
  bool settingsNotificationsEnabled = true;
  String settingsLanguageCode = 'de';
  ViewerType settingsViewerType = ViewerType.nativePlaceholder;
  UserRole settingsUserRole = UserRole.operator;
  int settingsAutoEscalationFirstStepMinutes = 0;
  int settingsAutoEscalationSecondStepMinutes = 30;
  String settingsViewerHeatmapZoneTypeFilter = 'all';
  String settingsViewerHeatmapSeverityFilter = 'all';
  bool settingsViewerHeatmapLiveModeEnabled = !kIsWeb;
  bool settingsViewerHeatmapAutoFocusEnabled = false;
  String settingsStorageFilterQuery = '';
  bool settingsStorageSortByAbc = true;
  int settingsStorageVisibleSampleCount = 12;
  DateTime? settingsLastSavedAt;
  bool settingsHasLoadedPersistedSettings = false;

  SharedPreferences? settingsPrefs;

  bool get isDarkMode => settingsIsDarkMode;
  bool get notificationsEnabled => settingsNotificationsEnabled;
  String get languageCode => settingsLanguageCode;
  Locale get locale => Locale(settingsLanguageCode);
  ViewerType get viewerType => settingsViewerType;
  UserRole get userRole => settingsUserRole;
  String get userRoleLabelKey => settingsUserRole.labelKey;
  int get autoEscalationFirstStepMinutes => settingsAutoEscalationFirstStepMinutes;
  int get autoEscalationSecondStepMinutes => settingsAutoEscalationSecondStepMinutes;
  DateTime? get settingsLastSavedAtValue => settingsLastSavedAt;
  bool get hasLoadedPersistedSettings => settingsHasLoadedPersistedSettings;
  String get viewerHeatmapZoneTypeFilter => settingsViewerHeatmapZoneTypeFilter;
  String get viewerHeatmapSeverityFilter => settingsViewerHeatmapSeverityFilter;
  bool get viewerHeatmapLiveModeEnabled => settingsViewerHeatmapLiveModeEnabled;
  bool get viewerHeatmapAutoFocusEnabled => settingsViewerHeatmapAutoFocusEnabled;
  String get storageFilterQuery => settingsStorageFilterQuery;
  bool get storageSortByAbc => settingsStorageSortByAbc;
  int get storageVisibleSampleCount => settingsStorageVisibleSampleCount;

  bool get canUseViewerControls => settingsUserRole != UserRole.viewer;
  bool get canToggleFavorites => settingsUserRole != UserRole.viewer;
  bool get canManageWarehouses => settingsUserRole != UserRole.viewer;
  bool get canExportReports => settingsUserRole != UserRole.viewer;

  AutoEscalationPreset get autoEscalationPreset {
    if (settingsAutoEscalationFirstStepMinutes == 15 &&
        settingsAutoEscalationSecondStepMinutes == 60) {
      return AutoEscalationPreset.conservative;
    }
    if (settingsAutoEscalationFirstStepMinutes == 0 &&
        settingsAutoEscalationSecondStepMinutes == 30) {
      return AutoEscalationPreset.standard;
    }
    if (settingsAutoEscalationFirstStepMinutes == 0 &&
        settingsAutoEscalationSecondStepMinutes == 10) {
      return AutoEscalationPreset.aggressive;
    }
    return AutoEscalationPreset.custom;
  }

  Future<void> loadPersistedSettings() async {
    settingsPrefs = await SharedPreferences.getInstance();
    settingsIsDarkMode = settingsPrefs?.getBool(prefDarkMode) ?? settingsIsDarkMode;
    settingsNotificationsEnabled =
        settingsPrefs?.getBool(prefNotificationsEnabled) ?? settingsNotificationsEnabled;
    settingsLanguageCode =
        settingsPrefs?.getString(prefLanguageCode) ?? settingsLanguageCode;
    settingsViewerType =
        _viewerTypeFromRaw(settingsPrefs?.getString(prefViewerType));
    settingsUserRole = _userRoleFromRaw(settingsPrefs?.getString(prefUserRole));
    settingsAutoEscalationFirstStepMinutes =
        settingsPrefs?.getInt(prefAutoEscFirstMinutes) ??
            settingsAutoEscalationFirstStepMinutes;
    settingsAutoEscalationSecondStepMinutes =
        settingsPrefs?.getInt(prefAutoEscSecondMinutes) ??
            settingsAutoEscalationSecondStepMinutes;
    settingsViewerHeatmapZoneTypeFilter =
        settingsPrefs?.getString(prefViewerHeatmapZoneTypeFilter) ??
            settingsViewerHeatmapZoneTypeFilter;
    settingsViewerHeatmapSeverityFilter =
        settingsPrefs?.getString(prefViewerHeatmapSeverityFilter) ??
            settingsViewerHeatmapSeverityFilter;
    settingsViewerHeatmapLiveModeEnabled =
        settingsPrefs?.getBool(prefViewerHeatmapLiveModeEnabled) ??
            settingsViewerHeatmapLiveModeEnabled;
    settingsViewerHeatmapAutoFocusEnabled =
        settingsPrefs?.getBool(prefViewerHeatmapAutoFocusEnabled) ??
            settingsViewerHeatmapAutoFocusEnabled;
    settingsStorageFilterQuery =
        settingsPrefs?.getString(prefStorageFilterQuery) ?? settingsStorageFilterQuery;
    settingsStorageSortByAbc =
        settingsPrefs?.getBool(prefStorageSortByAbc) ?? settingsStorageSortByAbc;
    settingsStorageVisibleSampleCount =
        settingsPrefs?.getInt(prefStorageVisibleCount) ??
            settingsStorageVisibleSampleCount;
    final lastSavedRaw = settingsPrefs?.getString(prefSettingsLastSavedAt);
    if (lastSavedRaw != null) {
      settingsLastSavedAt = DateTime.tryParse(lastSavedRaw);
    }
    settingsHasLoadedPersistedSettings = true;
    notifyListeners();
  }

  void setDarkMode(bool value) {
    settingsIsDarkMode = value;
    settingsPrefs?.setBool(prefDarkMode, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    settingsNotificationsEnabled = value;
    settingsPrefs?.setBool(prefNotificationsEnabled, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setLanguageCode(String value) {
    settingsLanguageCode = value;
    settingsPrefs?.setString(prefLanguageCode, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setViewerType(ViewerType value) {
    settingsViewerType = value;
    settingsPrefs?.setString(prefViewerType, value.name);
    touchSettingsSaved();
    notifyListeners();
  }

  void setUserRole(UserRole value) {
    settingsUserRole = value;
    settingsPrefs?.setString(prefUserRole, value.name);
    touchSettingsSaved();
    notifyListeners();
  }

  void setAutoEscalationPreset(AutoEscalationPreset preset) {
    switch (preset) {
      case AutoEscalationPreset.conservative:
        settingsAutoEscalationFirstStepMinutes = 15;
        settingsAutoEscalationSecondStepMinutes = 60;
      case AutoEscalationPreset.standard:
        settingsAutoEscalationFirstStepMinutes = 0;
        settingsAutoEscalationSecondStepMinutes = 30;
      case AutoEscalationPreset.aggressive:
        settingsAutoEscalationFirstStepMinutes = 0;
        settingsAutoEscalationSecondStepMinutes = 10;
      case AutoEscalationPreset.custom:
        return;
    }
    persistAutoEscalation();
  }

  void resetAutoEscalationRules() {
    settingsAutoEscalationFirstStepMinutes = 0;
    settingsAutoEscalationSecondStepMinutes = 30;
    persistAutoEscalation();
  }

  void setAutoEscalationFirstStepMinutes(int value) {
    settingsAutoEscalationFirstStepMinutes = value.clamp(0, 120).toInt();
    persistAutoEscalation();
  }

  void setAutoEscalationSecondStepMinutes(int value) {
    settingsAutoEscalationSecondStepMinutes = value.clamp(0, 240).toInt();
    persistAutoEscalation();
  }

  void persistAutoEscalation() {
    settingsPrefs?.setInt(
        prefAutoEscFirstMinutes, settingsAutoEscalationFirstStepMinutes);
    settingsPrefs?.setInt(
        prefAutoEscSecondMinutes, settingsAutoEscalationSecondStepMinutes);
    touchSettingsSaved();
    notifyListeners();
  }

  void setViewerHeatmapZoneTypeFilter(String value) {
    settingsViewerHeatmapZoneTypeFilter = value;
    settingsPrefs?.setString(prefViewerHeatmapZoneTypeFilter, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setViewerHeatmapSeverityFilter(String value) {
    settingsViewerHeatmapSeverityFilter = value;
    settingsPrefs?.setString(prefViewerHeatmapSeverityFilter, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setViewerHeatmapLiveModeEnabled(bool value) {
    settingsViewerHeatmapLiveModeEnabled = value;
    settingsPrefs?.setBool(prefViewerHeatmapLiveModeEnabled, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setViewerHeatmapAutoFocusEnabled(bool value) {
    settingsViewerHeatmapAutoFocusEnabled = value;
    settingsPrefs?.setBool(prefViewerHeatmapAutoFocusEnabled, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setStorageFilterQuery(String value) {
    settingsStorageFilterQuery = value;
    settingsPrefs?.setString(prefStorageFilterQuery, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setStorageSortByAbc(bool value) {
    settingsStorageSortByAbc = value;
    settingsPrefs?.setBool(prefStorageSortByAbc, value);
    touchSettingsSaved();
    notifyListeners();
  }

  void setStorageVisibleSampleCount(int value) {
    settingsStorageVisibleSampleCount = value.clamp(6, 300).toInt();
    settingsPrefs?.setInt(
        prefStorageVisibleCount, settingsStorageVisibleSampleCount);
    touchSettingsSaved();
    notifyListeners();
  }

  void touchSettingsSaved() {
    settingsLastSavedAt = DateTime.now();
    settingsPrefs?.setString(
        prefSettingsLastSavedAt, settingsLastSavedAt!.toIso8601String());
  }

  String exportSettingsAsJson() {
    final payload = <String, Object?>{
      'dark_mode': settingsIsDarkMode,
      'notifications': settingsNotificationsEnabled,
      'language': settingsLanguageCode,
      'viewer_type': settingsViewerType.name,
      'user_role': settingsUserRole.name,
      'auto_escalation_first': settingsAutoEscalationFirstStepMinutes,
      'auto_escalation_second': settingsAutoEscalationSecondStepMinutes,
      'heatmap_zone_filter': settingsViewerHeatmapZoneTypeFilter,
      'heatmap_severity_filter': settingsViewerHeatmapSeverityFilter,
      'heatmap_live_mode': settingsViewerHeatmapLiveModeEnabled,
      'heatmap_auto_focus': settingsViewerHeatmapAutoFocusEnabled,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  bool importSettingsFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return false;
      }
      final payload =
          Map<String, Object?>.from(decoded.cast<Object?, Object?>());
      settingsIsDarkMode = payload['dark_mode'] is bool
          ? payload['dark_mode'] as bool
          : settingsIsDarkMode;
      settingsNotificationsEnabled = payload['notifications'] is bool
          ? payload['notifications'] as bool
          : settingsNotificationsEnabled;
      settingsLanguageCode =
          payload['language']?.toString() ?? settingsLanguageCode;
      settingsViewerType =
          _viewerTypeFromRaw(payload['viewer_type']?.toString());
      settingsUserRole = _userRoleFromRaw(payload['user_role']?.toString());
      settingsAutoEscalationFirstStepMinutes = _toInt(
          payload['auto_escalation_first'],
          settingsAutoEscalationFirstStepMinutes);
      settingsAutoEscalationSecondStepMinutes = _toInt(
          payload['auto_escalation_second'],
          settingsAutoEscalationSecondStepMinutes);
      settingsViewerHeatmapZoneTypeFilter =
          payload['heatmap_zone_filter']?.toString() ??
              settingsViewerHeatmapZoneTypeFilter;
      settingsViewerHeatmapSeverityFilter =
          payload['heatmap_severity_filter']?.toString() ??
              settingsViewerHeatmapSeverityFilter;
      settingsViewerHeatmapLiveModeEnabled =
          payload['heatmap_live_mode'] is bool
              ? payload['heatmap_live_mode'] as bool
              : settingsViewerHeatmapLiveModeEnabled;
      settingsViewerHeatmapAutoFocusEnabled =
          payload['heatmap_auto_focus'] is bool
              ? payload['heatmap_auto_focus'] as bool
              : settingsViewerHeatmapAutoFocusEnabled;
      touchSettingsSaved();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  ViewerType _viewerTypeFromRaw(String? raw) {
    if (raw == null) {
      return settingsViewerType;
    }
    return ViewerType.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ViewerType.nativePlaceholder,
    );
  }

  UserRole _userRoleFromRaw(String? raw) {
    if (raw == null) {
      return settingsUserRole;
    }
    return UserRole.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => UserRole.operator,
    );
  }

  int _toInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse('$value') ?? fallback;
  }
}
