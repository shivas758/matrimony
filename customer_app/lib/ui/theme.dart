import 'package:flutter/material.dart';

/// Brand palette — the wine wordmark and gold rings of the MILI logo, on the
/// logo's cream tile (SPEC §9.17). Mirrored in the backend's public
/// registration form so the web page matches the app.
class AppColors {
  static const wineDeep = Color(0xFF3F0E1A);
  static const wine = Color(0xFF6A1B2D);
  static const wineLight = Color(0xFF8C2D44);
  static const gold = Color(0xFFC8A056);

  /// Gold dark enough for text and icons on white (4.5:1).
  static const goldDark = Color(0xFF94702F);
  static const goldLight = Color(0xFFF5E7C8);

  /// The glow at the centre of the logo tile.
  static const peach = Color(0xFFFED4C4);
  static const cream = Color(0xFFFFF8EE);

  /// A slightly deeper neutral than cream — used for chips and tinted panels.
  static const creamDeep = Color(0xFFFBEEDB);
  static const ink = Color(0xFF2A1518);
  static const muted = Color(0xFF7A6A64);
  static const rule = Color(0xFFEFE0CA);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFEF6C00);

  /// The header gradient used on the phone screen, the splash and the More header.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [wineLight, wine, wineDeep],
    stops: [0, 0.55, 1],
  );
}

/// Material 3, warm and legible for non-technical users: large touch
/// targets, generous type, high contrast (SPEC §5 / §9.11). Poppins for text,
/// Playfair Display for the brand wordmark and headlines.
class AppTheme {
  static const seed = AppColors.wine;
  static const surfaceTint = AppColors.cream;
  static const bodyFont = 'Poppins';
  static const displayFont = 'Playfair Display';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light).copyWith(
      primary: AppColors.wine,
      onPrimary: Colors.white,
      primaryContainer: AppColors.goldLight,
      onPrimaryContainer: AppColors.wineDeep,
      secondary: AppColors.goldDark,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.goldLight,
      onSecondaryContainer: AppColors.wineDeep,
      tertiary: AppColors.wineLight,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFDE6DC),
      onTertiaryContainer: AppColors.wineDeep,
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: const Color(0xFF5E4B46),
      surfaceContainerHighest: AppColors.creamDeep,
      surfaceContainerHigh: const Color(0xFFFCF1E2),
      surfaceContainer: const Color(0xFFFDF4E8),
      surfaceContainerLow: AppColors.cream,
      outline: AppColors.muted,
      outlineVariant: AppColors.rule,
      inverseSurface: AppColors.wineDeep,
      onInverseSurface: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: bodyFont);
    final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
    final display = TextStyle(
      fontFamily: displayFont,
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 600)],
      color: AppColors.wine,
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
        foregroundColor: AppColors.wine,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: bodyFont,
          fontWeight: FontWeight.w700,
          color: AppColors.wine,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.wine),
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
        labelStyle: const TextStyle(color: Color(0xFF5E4B46)),
        prefixIconColor: AppColors.wineLight,
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
          borderSide: const BorderSide(color: AppColors.wine, width: 1.6),
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
          backgroundColor: AppColors.wine,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.wine,
          side: const BorderSide(color: AppColors.wine, width: 1.2),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.wine,
          textStyle: const TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.wine),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.wineDeep,
        elevation: 2,
        extendedTextStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.goldLight,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: bodyFont,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.wine : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.wine : AppColors.muted,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: AppColors.rule),
        backgroundColor: Colors.white,
        selectedColor: AppColors.goldLight,
        checkmarkColor: AppColors.wine,
        // Override the shape only. Replacing labelStyle wholesale drops the
        // scheme colours and leaves chip text unreadable on light surfaces.
        labelStyle: text.labelLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w500),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.wine : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.wine,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.rule)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.wineDeep,
        contentTextStyle: const TextStyle(fontFamily: bodyFont, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.wine),
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
        iconColor: AppColors.wineLight,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.goldDark),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.wine,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.gold,
        labelStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w500),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.wine : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.wine : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.wine,
        thumbColor: AppColors.wine,
        inactiveTrackColor: AppColors.rule,
        rangeThumbShape: RoundRangeSliderThumbShape(enabledThumbRadius: 10),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.gold, textColor: AppColors.wineDeep),
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
