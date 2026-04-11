import 'package:flutter/foundation.dart';

class AppConstants {
  const AppConstants._();

  static const String appName = 'Sch\u00E4flein LagerView';
  static const String appVersion = '1.0.0-mvp';

  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';
  }
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppBreakpoints {
  const AppBreakpoints._();

  static const double tablet = 700;
  static const double rail = 900;
  static const double desktop = 1200;
}
