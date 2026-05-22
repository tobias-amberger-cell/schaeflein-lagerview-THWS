import 'package:flutter/material.dart';

/// Semantic color tokens used across the app.
///
/// These map to Tailwind-style palette values so the design stays
/// consistent without hardcoding hex values in every widget.
class AppColors {
  const AppColors._();

  // Brand / Primary
  static const Color brandBlue = Color(0xFF2563EB);
  static const Color brandTeal = Color(0xFF0F766E);
  static const Color brandPurple = Color(0xFF7C3AED);
  static const Color brandOrange = Color(0xFFF97316);
  static const Color brandPink = Color(0xFFEC4899);
  static const Color brandIndigo = Color(0xFF4F46E5);
  static const Color brandSky = Color(0xFF0EA5E9);

  // Severity / Status
  static const Color success = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF166534);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color successBorder = Color(0xFF86EFAC);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFF92400E);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color warningBorder = Color(0xFFFCD34D);

  static const Color error = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFB91C1C);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color errorBorder = Color(0xFFFCA5A5);

  static const Color neutralGray = Color(0xFF6B7280);
  static const Color brownDark = Color(0xFF9A3412);

  // ABC Analysis
  static const Color abcA = Color(0xFF15803D);
  static const Color abcB = Color(0xFFF59E0B);
  static const Color abcC = Color(0xFF6B7280);
}
