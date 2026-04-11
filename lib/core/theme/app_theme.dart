import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';

class AppTheme {
  const AppTheme._();

  static const Color _brandBlue = Color(0xFF006FAE);
  static const Color _brandRed = Color(0xFFE30613);
  static const Color _brandBlack = Color(0xFF111111);
  static const Color _surfaceLight = Color(0xFFF6F6F4);
  static const Color _surfaceLightLow = Color(0xFFF1F2F4);
  static const Color _surfaceLightHigh = Color(0xFFE8EAEE);
  static const Color _surfaceDark = Color(0xFF121212);
  static const Color _surfaceDarkLow = Color(0xFF1E1F22);
  static const Color _surfaceDarkHigh = Color(0xFF292B30);

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final seededScheme = ColorScheme.fromSeed(
      seedColor: _brandBlue,
      brightness: brightness,
    );
    final colorScheme = brightness == Brightness.dark
        ? seededScheme.copyWith(
            primary: const Color(0xFFFF6B72),
            onPrimary: const Color(0xFF3B0004),
            secondary: const Color(0xFFFFE769),
            onSecondary: const Color(0xFF3D3300),
            tertiary: const Color(0xFFCBCBCB),
            surface: _surfaceDark,
            surfaceContainerLowest: _surfaceDark,
            surfaceContainerLow: _surfaceDarkLow,
            surfaceContainer: _surfaceDarkLow,
            surfaceContainerHigh: _surfaceDarkHigh,
            surfaceContainerHighest: const Color(0xFF282828),
            surfaceDim: const Color(0xFF111214),
            surfaceBright: const Color(0xFF2F3238),
            surfaceTint: Colors.transparent,
          )
        : seededScheme.copyWith(
            primary: _brandBlue,
            onPrimary: Colors.white,
            secondary: _brandRed,
            onSecondary: Colors.white,
            tertiary: _brandBlack,
            surface: _surfaceLight,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: _surfaceLightLow,
            surfaceContainer: _surfaceLightLow,
            surfaceContainerHigh: _surfaceLightHigh,
            surfaceContainerHighest: const Color(0xFFF0EFE9),
            surfaceDim: const Color(0xFFE1E3E7),
            surfaceBright: Colors.white,
            surfaceTint: Colors.transparent,
          );

    final baseTextTheme = GoogleFonts.manropeTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );

    final refinedTextTheme = baseTextTheme.copyWith(
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.3,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.24,
        letterSpacing: -0.2,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.36),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.34),
      bodySmall: baseTextTheme.bodySmall?.copyWith(height: 1.3),
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
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.45),
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
        elevation: brightness == Brightness.dark ? 0 : 1,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
        backgroundColor: Colors.transparent,
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
            borderRadius: BorderRadius.circular(14),
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
            borderRadius: BorderRadius.circular(14),
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
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: colorScheme.outlineVariant),
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: refinedTextTheme,
    );
  }
}
