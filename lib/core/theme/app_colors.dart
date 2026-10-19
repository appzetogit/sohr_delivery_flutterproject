import 'package:flutter/material.dart';

/// The single source of truth for every colour in the app.
///
/// Nothing outside this file should write a raw `Color(0xFF…)`. Screens read
/// either the semantic getters here (via [AppColors.of]) or, for anything the
/// framework already themes, `Theme.of(context)`.
///
/// The brand colour is Golden (#C4801C). Green is a **status** colour only —
/// online, success, approved, completed, available — and must never be used
/// as a brand accent.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------- brand
  static const Color primary = Color(0xFFC4801C);
  static const Color primaryLight = Color(0xFFE0A64F);
  static const Color primaryDark = Color(0xFF9E6512);

  /// Text/icon colour that sits on top of [primary]. Golden is dark enough
  /// that white wins on contrast — every primary-filled button must use it.
  /// On a *tinted* purple surface (low-alpha [primary]) use [primaryDark].
  static const Color onPrimary = Color(0xFFFFFFFF);

  // ---------------------------------------------------------- light theme
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF3F4F6);
  static const Color lightTextPrimary = Color(0xFF181C2E);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightBorder = Color(0xFFE5E7EB);

  // ----------------------------------------------------------- dark theme
  static const Color darkBackground = Color(0xFF121223);
  static const Color darkSurface = Color(0xFF1E1E2E);
  static const Color darkSurfaceVariant = Color(0xFF2A2A3C);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA0A0B2);
  static const Color darkBorder = Color(0xFF32324A);

  // --------------------------------------------------------------- status
  static const Color success = Color(0xFF2FB457);
  static const Color successBg = Color(0xFFE6F4EA);
  static const Color successText = Color(0xFF1E8E3E);

  static const Color warning = Color(0xFFF59E0B);

  static const Color pendingBg = Color(0xFFFFF8E7);
  static const Color pendingText = Color(0xFFD97706);

  static const Color error = Color(0xFFE04444);
  static const Color errorBg = Color(0xFFFCE8E6);
  static const Color errorText = Color(0xFFD93025);

  static const Color rating = Color(0xFFFFC529);

  /// Rider is online / available / sharing location.
  static const Color online = success;

  /// Rider is offline. Deliberately neutral, not red — offline is a normal
  /// state, not a fault.
  static const Color offline = Color(0xFF9CA3AF);

  // ---------------------------------------------------------------- misc
  /// Fill for dark pill buttons (navigate / call / chat) that must read as
  /// secondary next to a primary-purple action.
  static const Color lightNeutralDark = Color(0xFF1C1C1E);

  /// Map placeholder backdrops, shown before the first GPS fix.
  static const Color mapPlaceholderLight = Color(0xFFE8F2ED);
  static const Color mapPlaceholderDark = Color(0xFF242F3E);

  /// Resolves the light or dark palette for the current context.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const AppPalette.dark()
      : const AppPalette.light();
}

/// Brightness-resolved colours, so a screen writes `c.textPrimary` instead of
/// repeating `isDark ? … : …` at every call site.
class AppPalette {
  const AppPalette._({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  const AppPalette.light()
    : this._(
        isDark: false,
        background: AppColors.lightBackground,
        surface: AppColors.lightSurface,
        surfaceVariant: AppColors.lightSurfaceVariant,
        textPrimary: AppColors.lightTextPrimary,
        textSecondary: AppColors.lightTextSecondary,
        border: AppColors.lightBorder,
      );

  const AppPalette.dark()
    : this._(
        isDark: true,
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        surfaceVariant: AppColors.darkSurfaceVariant,
        textPrimary: AppColors.darkTextPrimary,
        textSecondary: AppColors.darkTextSecondary,
        border: AppColors.darkBorder,
      );

  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  /// Backdrop shown behind the map before a GPS fix arrives.
  Color get mapPlaceholder =>
      isDark ? AppColors.mapPlaceholderDark : AppColors.mapPlaceholderLight;
}
