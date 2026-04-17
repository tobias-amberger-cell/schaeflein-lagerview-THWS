import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';

class AppTheme {
  const AppTheme._();

  static const Color _brandBlue = Color(0xFF005AA4);
  static const Color _brandRed = Color(0xFFE10B2B);
  static const Color _brandInk = Color(0xFF111827);
  static const Color _surfaceLight = Color(0xFFF7F8FB);
  static const Color _surfaceLightLow = Color(0xFFF1F4F8);
  static const Color _surfaceLightHigh = Color(0xFFE6EBF2);
  static const Color _surfaceDark = Color(0xFF0F1115);
  static const Color _surfaceDarkLow = Color(0xFF181B21);
  static const Color _surfaceDarkHigh = Color(0xFF23262E);

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final seededScheme = ColorScheme.fromSeed(
      seedColor: _brandBlue,
      brightness: brightness,
    );
    final colorScheme = brightness == Brightness.dark
        ? seededScheme.copyWith(
            primary: const Color(0xFF77B3FF),
            onPrimary: const Color(0xFF001B3B),
            secondary: const Color(0xFFFFB4B4),
            onSecondary: const Color(0xFF3A0409),
            tertiary: const Color(0xFFB9C2D0),
            surface: _surfaceDark,
            surfaceContainerLowest: _surfaceDark,
            surfaceContainerLow: _surfaceDarkLow,
            surfaceContainer: _surfaceDarkLow,
            surfaceContainerHigh: _surfaceDarkHigh,
            surfaceContainerHighest: const Color(0xFF2B3038),
            surfaceDim: const Color(0xFF0D0F12),
            surfaceBright: const Color(0xFF343A44),
            surfaceTint: Colors.transparent,
            outline: const Color(0xFF3B4250),
            outlineVariant: const Color(0xFF2B313B),
          )
        : seededScheme.copyWith(
            primary: _brandBlue,
            onPrimary: Colors.white,
            secondary: _brandRed,
            onSecondary: Colors.white,
            tertiary: _brandInk,
            surface: _surfaceLight,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: _surfaceLightLow,
            surfaceContainer: _surfaceLightLow,
            surfaceContainerHigh: _surfaceLightHigh,
            surfaceContainerHighest: const Color(0xFFEEF2F7),
            surfaceDim: const Color(0xFFE0E5ED),
            surfaceBright: Colors.white,
            surfaceTint: Colors.transparent,
            outline: const Color(0xFFB9C2D0),
            outlineVariant: const Color(0xFFD6DCE6),
          );

    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );

    final refinedTextTheme = baseTextTheme.copyWith(
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.18,
        letterSpacing: -0.4,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.22,
        letterSpacing: -0.3,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.1,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.42),
      bodySmall: baseTextTheme.bodySmall?.copyWith(height: 1.38),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.1,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? _surfaceDark : _surfaceLight,
      cardColor: colorScheme.surfaceContainerLowest,
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainerLowest,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: refinedTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.08),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerLowest,
        hintStyle: refinedTextTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.primary.withValues(alpha: 0.18),
        backgroundColor: colorScheme.surfaceContainerLowest,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: colorScheme.outlineVariant),
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.2),
        selectionHandleColor: colorScheme.primary,
      ),
      textTheme: refinedTextTheme,
    );
  }
}
