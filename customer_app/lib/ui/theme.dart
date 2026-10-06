import 'package:flutter/material.dart';

/// Brand palette — maroon and rose gold from the Gandharva disc logo, on a
/// warm blush background (SPEC §9 intro). Mirrored in the backend's public
/// registration form so the web page matches the app.
class AppColors {
  static const maroonDeep = Color(0xFF2E0F18);
  static const maroon = Color(0xFF4A1A29);
  static const maroonLight = Color(0xFF6B2A3D);
  static const roseGold = Color(0xFFD4A28C);
  static const roseDark = Color(0xFFB07E68);
  static const roseLight = Color(0xFFF0D6CC);
  static const blush = Color(0xFFFAF3F0);

  /// A slightly deeper neutral than blush — used for chips and tinted panels.
  static const blushDeep = Color(0xFFF3E8E3);
  static const ink = Color(0xFF241418);
  static const muted = Color(0xFF7A6A6E);
  static const rule = Color(0xFFEADCD6);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFEF6C00);

  /// The header gradient used on the phone screen, the splash and the More header.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [maroonLight, maroon, maroonDeep],
    stops: [0, 0.55, 1],
  );
}

/// Material 3, warm and legible for non-technical users: large touch
/// targets, generous type, high contrast (SPEC §5 / §9.11). Poppins for text,
/// Playfair Display for the brand wordmark and headlines.
class AppTheme {
  static const seed = AppColors.maroon;
  static const surfaceTint = AppColors.blush;
  static const bodyFont = 'Poppins';
  static const displayFont = 'Playfair Display';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light).copyWith(
      primary: AppColors.maroon,
      onPrimary: Colors.white,
      primaryContainer: AppColors.roseLight,
      onPrimaryContainer: AppColors.maroonDeep,
      secondary: AppColors.roseDark,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.roseLight,
      onSecondaryContainer: AppColors.maroonDeep,
      tertiary: const Color(0xFF8A4A5C),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFF7E6DF),
      onTertiaryContainer: AppColors.maroonDeep,
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: const Color(0xFF5B4A4F),
      surfaceContainerHighest: AppColors.blushDeep,
      surfaceContainerHigh: const Color(0xFFF6EDE9),
      surfaceContainer: const Color(0xFFF8F1EE),
      surfaceContainerLow: AppColors.blush,
      outline: AppColors.muted,
      outlineVariant: AppColors.rule,
      inverseSurface: AppColors.maroonDeep,
      onInverseSurface: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: bodyFont);
    final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
    final display = TextStyle(
      fontFamily: displayFont,
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 600)],
      color: AppColors.maroon,
      letterSpacing: -0.2,
    );

    return base.copyWith(
      scaffoldBackgroundColor: surfaceTint,
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.merge(display),
        displayMedium: text.displayMedium?.merge(display),
        displaySmall: text.displaySmall?.merge(display),
        headlineLarge: text.headlineLarge?.merge(display),
        headlineMedium: text.headlineMedium?.merge(display),
        headlineSmall: text.headlineSmall?.merge(display).copyWith(fontSize: 24),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceTint,
        foregroundColor: AppColors.maroon,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: bodyFont,
          fontWeight: FontWeight.w700,
          color: AppColors.maroon,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.maroon),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.rule),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: Color(0xFF5B4A4F)),
        prefixIconColor: AppColors.maroonLight,
        suffixIconColor: AppColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.maroon, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52), // large touch target
          backgroundColor: AppColors.maroon,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.maroon,
          side: const BorderSide(color: AppColors.maroon, width: 1.2),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.maroon,
          textStyle: const TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.maroon),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.roseGold,
        foregroundColor: AppColors.maroonDeep,
        elevation: 2,
        extendedTextStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.roseLight,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: bodyFont,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.maroon : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.maroon : AppColors.muted,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: AppColors.rule),
        backgroundColor: Colors.white,
        selectedColor: AppColors.roseLight,
        checkmarkColor: AppColors.maroon,
        // Override the shape only. Replacing labelStyle wholesale drops the
        // scheme colours and leaves chip text unreadable on light surfaces.
        labelStyle: text.labelLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w500),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.maroon : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.maroon,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.rule)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.maroonDeep,
        contentTextStyle: const TextStyle(fontFamily: bodyFont, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.maroon),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.rule, space: 1, thickness: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: AppColors.maroonLight,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.roseDark),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.maroon,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.roseGold,
        labelStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w500),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.maroon : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.maroon : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.maroon,
        thumbColor: AppColors.maroon,
        inactiveTrackColor: AppColors.rule,
        rangeThumbShape: RoundRangeSliderThumbShape(enabledThumbRadius: 10),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.roseGold, textColor: AppColors.maroonDeep),
    );
  }
}

/// Status colours shared by chips across the app.
class StatusColors {
  /// Customer account status (SPEC §9.2).
  static Color forCustomerStatus(String status, ColorScheme scheme) => switch (status) {
        'active' => AppColors.success,
        'pending' => AppColors.warning,
        'rejected' => scheme.error,
        'suspended' => scheme.error,
        _ => scheme.outline,
      };

  /// Interest status (SPEC §9.4) — 'expired' is what the app reads when an
  /// accepted interest's access window has lapsed.
  static Color forInterestStatus(String status, ColorScheme scheme) => switch (status) {
        'pending' => AppColors.warning,
        'accepted' => AppColors.success,
        'declined' => scheme.error,
        'revoked' => scheme.error,
        'withdrawn' => scheme.outline,
        'expired' => scheme.outline,
        _ => scheme.outline,
      };

  /// Agent-change request status (SPEC §9.6).
  static Color forRequestStatus(String status, ColorScheme scheme) => switch (status) {
        'pending' => AppColors.warning,
        'approved' => AppColors.success,
        'rejected' => scheme.error,
        'cancelled' => scheme.outline,
        _ => scheme.outline,
      };

  static Color forProfileStatus(String status, ColorScheme scheme) => switch (status) {
        'active' => AppColors.success,
        'engaged' => AppColors.warning,
        'married' => const Color(0xFF6A1B9A),
        'on_hold' => const Color(0xFF3949AB),
        'hidden' => scheme.outline,
        _ => scheme.outline,
      };
}
