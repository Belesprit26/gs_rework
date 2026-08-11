import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// The GeyserSwitch application theme.
///
/// Light-only for now; the token set in [AppColors] and this structure
/// make a dark variant a later drop-in rather than a rewrite.
///
/// The type face is Poppins (a geometric sans matching the wordmark),
/// pulled via `google_fonts` — no bundled files. It falls back to the
/// platform sans if the font can't be fetched.
abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkSecondary,
      outline: AppColors.muted,
      outlineVariant: AppColors.hairline,
      // Keep the focal card + gauge inner circle pure white.
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surfaceAlt,
      surfaceContainerHigh: AppColors.surfaceAlt,
      error: AppColors.critical,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: AppColors.hairline,
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      // Safety net for any SnackBar not built via app_snack.dart — same
      // ground (white card, ink text, rounded, floating), minus the accent
      // bar. New code should use showAppSnack instead.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(
          fontSize: 13.5,
          color: AppColors.ink,
        ),
        actionTextColor: AppColors.primary,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary.withValues(alpha: 0.4)
              : null,
        ),
      ),
    );
  }
}
