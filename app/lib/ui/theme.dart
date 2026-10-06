import 'package:flutter/material.dart';

/// Brand palette — navy and gold from the Mediator logo, on warm ivory.
/// Mirrored in backend/src/lib/pdf.js and card.js so shares match the app.
class AppColors {
  static const navyDeep = Color(0xFF081C33);
  static const navy = Color(0xFF0F2F52);
  static const navyLight = Color(0xFF1B4F82);
  static const navyTint = Color(0xFFDCE6F3);
  static const gold = Color(0xFFC9962E);
  static const goldDark = Color(0xFFA6781C);
  static const goldLight = Color(0xFFE8C25F);
  static const goldPale = Color(0xFFF7E9C4);
  static const ivory = Color(0xFFF7F5F0);
  static const sand = Color(0xFFEFEAE0);
  static const ink = Color(0xFF1C2430);
  static const muted = Color(0xFF6B7280);
  static const rule = Color(0xFFE7E2D8);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFEF6C00);

  /// The header gradient used on the login screen, list cards and the More header.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyLight, navy, navyDeep],
    stops: [0, 0.55, 1],
  );
}

/// Material 3, warm and legible for non-technical users: large touch
/// targets, generous type, high contrast (SPEC §5). Poppins for text,
/// Playfair Display for the brand wordmark and headlines.
class AppTheme {
  static const seed = AppColors.navy;
  static const surfaceTint = AppColors.ivory;
  static const bodyFont = 'Poppins';
  static const displayFont = 'Playfair Display';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light).copyWith(
      primary: AppColors.navy,
      onPrimary: Colors.white,
      primaryContainer: AppColors.navyTint,
      onPrimaryContainer: AppColors.navyDeep,
      secondary: AppColors.goldDark,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.goldPale,
      onSecondaryContainer: const Color(0xFF4A3608),
      tertiary: const Color(0xFF8B5E1A),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFCEBCF),
      onTertiaryContainer: const Color(0xFF4A3608),
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: const Color(0xFF4B5563),
      surfaceContainerHighest: AppColors.sand,
      surfaceContainerHigh: const Color(0xFFF2EEE6),
      surfaceContainer: const Color(0xFFF5F2EC),
      surfaceContainerLow: AppColors.ivory,
      outline: AppColors.muted,
      outlineVariant: AppColors.rule,
      inverseSurface: AppColors.navyDeep,
      onInverseSurface: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: bodyFont);
    final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
    final display = TextStyle(
      fontFamily: displayFont,
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 600)],
      color: AppColors.navy,
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
        foregroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: bodyFont,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
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
        labelStyle: const TextStyle(color: Color(0xFF4B5563)),
        prefixIconColor: AppColors.navyLight,
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
          borderSide: const BorderSide(color: AppColors.navy, width: 1.6),
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
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.navy, width: 1.2),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.navy,
          textStyle: const TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.navy),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navyDeep,
        elevation: 2,
        extendedTextStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.goldPale,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: bodyFont,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.navy : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.navy : AppColors.muted,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: AppColors.rule),
        backgroundColor: Colors.white,
        selectedColor: AppColors.goldPale,
        checkmarkColor: AppColors.navy,
        // Override the shape only. Replacing labelStyle wholesale drops the
        // scheme colours and leaves chip text unreadable on light surfaces.
        labelStyle: text.labelLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w500),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.navy : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.navy,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.rule)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navyDeep,
        contentTextStyle: const TextStyle(fontFamily: bodyFont, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.navy),
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
        iconColor: AppColors.navyLight,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gold),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.navy,
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
          (states) => states.contains(WidgetState.selected) ? AppColors.navy : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.navy : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.navy,
        thumbColor: AppColors.navy,
        inactiveTrackColor: AppColors.rule,
        rangeThumbShape: RoundRangeSliderThumbShape(enabledThumbRadius: 10),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.gold, textColor: AppColors.navyDeep),
    );
  }
}

/// Status colours shared by profile chips and request rows.
class StatusColors {
  static Color forProfileStatus(String status, ColorScheme scheme) => switch (status) {
        'active' => AppColors.success,
        'engaged' => AppColors.warning,
        'married' => const Color(0xFF6A1B9A),
        'on_hold' => const Color(0xFF3949AB),
        'hidden' => scheme.outline,
        _ => scheme.outline,
      };

  static Color forRequestStatus(String status, ColorScheme scheme) => switch (status) {
        'pending' => AppColors.warning,
        'approved' => AppColors.success,
        'rejected' => scheme.error,
        'revoked' => scheme.error,
        'expired' => scheme.outline,
        'cancelled' => scheme.outline,
        'released' => scheme.outline,
        _ => scheme.outline,
      };
}
