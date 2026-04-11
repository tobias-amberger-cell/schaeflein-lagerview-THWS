import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';

import 'core/constants/app_constants.dart';
import 'core/localization/app_localizations.dart';
import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

class LagerViewApp extends StatefulWidget {
  const LagerViewApp({super.key});

  @override
  State<LagerViewApp> createState() => _LagerViewAppState();
}

class _LagerViewAppState extends State<LagerViewApp> {
  late final AppState _appState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _appState = AppState();
    _router = createAppRouter(_appState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_appState.loadPersistedSettings());
      unawaited(_appState.syncWarehouses());
    });
  }

  @override
  void dispose() {
    _router.dispose();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: _appState,
      child: AnimatedBuilder(
        animation: _appState,
        builder: (context, _) {
          return MaterialApp.router(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            locale: _appState.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            scrollBehavior: const _AppScrollBehavior(),
            routerConfig: _router,
          );
        },
      ),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}
