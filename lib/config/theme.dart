import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SevaSetu Design System
///
/// One global theme file. Imported everywhere via:
///   import 'package:sevasetu/config/theme.dart';
///
/// Tokens exposed:
///   AppColors      → semantic color palette (Civic Calm)
///   AppTypography  → dual-font pairing (Space Grotesk + Plus Jakarta Sans)
///   AppSpacing     → 4-pt grid spacing scale
///   AppRadius      → corner radius scale
///   AppElevation   → named shadow tiers
///   AppMotion      → animation durations & curves
///   AppDecorations → reusable BoxDecorations (cards, chips, gradients)
///   AppTheme       → assembled ThemeData (lightTheme)
///
/// Design ethos: Civic Calm — confident indigo + verdant teal anchored on a
/// warm bone surface; sharp display type contrasted with soft humanist body.

// ─────────────────────────────────────────────────────────────────────────────
// COLORS — Civic Calm palette (bright mode only)
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  // Brand anchors -----------------------------------------------------------
  /// Confident Indigo — primary action, focused state, key brand color.
  static const Color primary = Color(0xFF1F4FEB);

  /// Soft tinted indigo — used as background for primary chips/badges/icons.
  static const Color primaryContainer = Color(0xFFE2E8FF);

  /// Verdant Teal — secondary brand accent, success, confirmation.
  static const Color secondary = Color(0xFF0F766E);

  /// Soft tinted teal.
  static const Color secondaryContainer = Color(0xFFCCFBF1);

  /// Amber Glow — tertiary accent, focused warning highlight, attention.
  static const Color tertiary = Color(0xFFB45309);

  /// Soft tinted amber.
  static const Color tertiaryContainer = Color(0xFFFEF3C7);

  // Foreground on brand anchors ---------------------------------------------
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF0E2A8B);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF064E47);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFF7C2D12);

  // Surface system — warm neutrals ------------------------------------------
  /// Bone Linen — primary background.
  static const Color background = Color(0xFFFAFAF7);
  static const Color surface = Color(0xFFFAFAF7);
  static const Color surfaceBright = Color(0xFFFFFFFF);
  static const Color surfaceDim = Color(0xFFE9E7E1);

  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF4F2EC);
  static const Color surfaceContainer = Color(0xFFEFECE5);
  static const Color surfaceContainerHigh = Color(0xFFEBE8E0);
  static const Color surfaceContainerHighest = Color(0xFFE3E0D7);
  static const Color surfaceVariant = Color(0xFFEFECE5);

  // Foreground on surface ---------------------------------------------------
  static const Color onBackground = Color(0xFF1A1A18);
  static const Color onSurface = Color(0xFF1A1A18);
  static const Color onSurfaceVariant = Color(0xFF52514C);

  // Lines & dividers --------------------------------------------------------
  static const Color outline = Color(0xFF8C8980);
  static const Color outlineVariant = Color(0xFFD7D4CC);

  // Inverse (used for snackbars/tooltips) -----------------------------------
  static const Color inverseSurface = Color(0xFF2E2D2A);
  static const Color inverseOnSurface = Color(0xFFF4F2EC);
  static const Color inversePrimary = Color(0xFFB6C5FF);

  // Status colors -----------------------------------------------------------
  static const Color error = Color(0xFFB42318);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFEE4E2);
  static const Color onErrorContainer = Color(0xFF7A271A);

  static const Color success = Color(0xFF0F766E);
  static const Color successContainer = Color(0xFFCCFBF1);
  static const Color warning = Color(0xFFD97706);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color info = Color(0xFF1F4FEB);
  static const Color infoContainer = Color(0xFFE2E8FF);

  // Urgency mapping (used by alert/task UI) ---------------------------------
  static const Color urgencyCritical = error;
  static const Color urgencyHigh = Color(0xFFEA580C);
  static const Color urgencyMedium = warning;
  static const Color urgencyLow = success;

  // Surface tint (M3) -------------------------------------------------------
  static const Color surfaceTint = primary;

  // ─────────────────────────────────────────────────────────────────────
  // Backward-compatibility aliases — keep older code compiling.
  // Prefer the new names above for new code.
  // ─────────────────────────────────────────────────────────────────────
  static const Color primaryFixed = primaryContainer;
  static const Color primaryFixedDim = Color(0xFFB6C5FF);
  static const Color onPrimaryFixed = Color(0xFF000B5C);
  static const Color onPrimaryFixedVariant = Color(0xFF1F3BC4);

  static const Color secondaryFixed = secondaryContainer;
  static const Color secondaryFixedDim = Color(0xFF99F6E4);
  static const Color onSecondaryFixed = Color(0xFF064E47);
  static const Color onSecondaryFixedVariant = Color(0xFF0B5F58);

  static const Color tertiaryFixed = tertiaryContainer;
  static const Color tertiaryFixedDim = Color(0xFFFCD34D);
  static const Color onTertiaryFixed = Color(0xFF7C2D12);
  static const Color onTertiaryFixedVariant = Color(0xFF92400E);
}

// ─────────────────────────────────────────────────────────────────────────────
// SPACING — 4pt grid
// ─────────────────────────────────────────────────────────────────────────────

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // Common composite paddings
  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets pageHV = EdgeInsets.symmetric(horizontal: lg, vertical: lg);
  static const EdgeInsets cardInner = EdgeInsets.all(lg);
  static const EdgeInsets sectionInner = EdgeInsets.fromLTRB(lg, lg, lg, xl);
}

// ─────────────────────────────────────────────────────────────────────────────
// RADIUS
// ─────────────────────────────────────────────────────────────────────────────

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double pill = 999;

  static BorderRadius get smR => BorderRadius.circular(sm);
  static BorderRadius get mdR => BorderRadius.circular(md);
  static BorderRadius get lgR => BorderRadius.circular(lg);
  static BorderRadius get xlR => BorderRadius.circular(xl);
  static BorderRadius get xxlR => BorderRadius.circular(xxl);
  static BorderRadius get pillR => BorderRadius.circular(pill);
}

// ─────────────────────────────────────────────────────────────────────────────
// ELEVATION
// ─────────────────────────────────────────────────────────────────────────────

class AppElevation {
  /// No shadow — flush with surface.
  static const List<BoxShadow> flat = [];

  /// Subtle shadow — used for cards on the main canvas.
  static List<BoxShadow> get soft => const [
        BoxShadow(
          color: Color(0x0F1A1A18),
          blurRadius: 16,
          spreadRadius: 0,
          offset: Offset(0, 4),
        ),
      ];

  /// Floating element — bottom nav, FAB, prominent buttons.
  static List<BoxShadow> get floating => const [
        BoxShadow(
          color: Color(0x141A1A18),
          blurRadius: 28,
          spreadRadius: 0,
          offset: Offset(0, 12),
        ),
      ];

  /// Dialog / modal — strong separation.
  static List<BoxShadow> get dialog => const [
        BoxShadow(
          color: Color(0x261A1A18),
          blurRadius: 48,
          spreadRadius: 0,
          offset: Offset(0, 20),
        ),
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// MOTION
// ─────────────────────────────────────────────────────────────────────────────

class AppMotion {
  // Durations
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration emphasized = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 480);

  // Curves
  static const Curve easeStandard = Curves.easeOutCubic;
  static const Curve easeEmphasized = Cubic(0.2, 0.0, 0.0, 1.0); // M3 emphasized
  static const Curve easeIn = Curves.easeIn;
  static const Curve easeBack = Curves.easeOutBack;
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPOGRAPHY — dual-font pairing
//   Display (sharp, structural)  → Space Grotesk
//   Body    (soft, humanist)     → Plus Jakarta Sans
// ─────────────────────────────────────────────────────────────────────────────

class AppTypography {
  static TextStyle display(
      {required double size,
      FontWeight weight = FontWeight.w600,
      double letterSpacing = -0.4,
      Color color = AppColors.onSurface,
      double? height}) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height ?? 1.12,
      color: color,
    );
  }

  static TextStyle body(
      {required double size,
      FontWeight weight = FontWeight.w400,
      double letterSpacing = 0,
      Color color = AppColors.onSurfaceVariant,
      double? height}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height ?? 1.45,
      color: color,
    );
  }

  static TextTheme get textTheme => TextTheme(
        // Display — large hero numerals & headers
        displayLarge: display(size: 56, weight: FontWeight.w700, letterSpacing: -1.4, color: AppColors.onSurface),
        displayMedium: display(size: 44, weight: FontWeight.w700, letterSpacing: -1.0, color: AppColors.onSurface),
        displaySmall: display(size: 36, weight: FontWeight.w700, letterSpacing: -0.8, color: AppColors.onSurface),

        // Headlines — section headers
        headlineLarge: display(size: 30, weight: FontWeight.w700, letterSpacing: -0.6, color: AppColors.onSurface),
        headlineMedium: display(size: 26, weight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.onSurface),
        headlineSmall: display(size: 22, weight: FontWeight.w600, letterSpacing: -0.3, color: AppColors.onSurface),

        // Titles — card / dialog titles (use body font for soft humanist feel)
        titleLarge: body(size: 19, weight: FontWeight.w700, color: AppColors.onSurface, height: 1.28),
        titleMedium: body(size: 16, weight: FontWeight.w600, color: AppColors.onSurface, height: 1.3),
        titleSmall: body(size: 14, weight: FontWeight.w600, color: AppColors.onSurface, height: 1.32),

        // Body — paragraphs
        bodyLarge: body(size: 16, weight: FontWeight.w400, color: AppColors.onSurfaceVariant),
        bodyMedium: body(size: 14, weight: FontWeight.w400, color: AppColors.onSurfaceVariant),
        bodySmall: body(size: 12.5, weight: FontWeight.w400, color: AppColors.onSurfaceVariant),

        // Labels — buttons, chips, captions
        labelLarge: body(size: 14, weight: FontWeight.w600, color: AppColors.onSurface, letterSpacing: 0.1),
        labelMedium: body(size: 12, weight: FontWeight.w600, color: AppColors.onSurfaceVariant, letterSpacing: 0.2),
        labelSmall: body(size: 11, weight: FontWeight.w600, color: AppColors.onSurfaceVariant, letterSpacing: 0.4),
      );

  /// Convenience numeric/metric style (tabular, sharp).
  static TextStyle metric({double size = 32, Color color = AppColors.onSurface, FontWeight weight = FontWeight.w700}) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: -0.6,
      height: 1.0,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      surfaceTint: AppColors.surfaceTint,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.inverseOnSurface,
      inversePrimary: AppColors.inversePrimary,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
    );

    final textTheme = AppTypography.textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      dividerColor: AppColors.outlineVariant,
      splashFactory: InkRipple.splashFactory,

      textTheme: textTheme,
      primaryTextTheme: textTheme,

      // App bar — transparent, theme-driven typography
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        titleTextStyle: textTheme.titleLarge,
        toolbarHeight: 64,
      ),

      // Buttons -----------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.surfaceContainerHigh,
          disabledForegroundColor: AppColors.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR),
          textStyle: textTheme.labelLarge?.copyWith(color: AppColors.onPrimary),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR),
          textStyle: textTheme.labelLarge?.copyWith(color: AppColors.onPrimary),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR),
          side: const BorderSide(color: AppColors.outlineVariant, width: 1.2),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
          textStyle: textTheme.labelLarge?.copyWith(color: AppColors.primary),
        ),
      ),

      // Inputs -----------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant.withValues(alpha: 0.7)),
        prefixIconColor: AppColors.onSurfaceVariant,
        suffixIconColor: AppColors.onSurfaceVariant,
        border: OutlineInputBorder(borderRadius: AppRadius.lgR, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.lgR, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),

      // Chips -----------------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceContainerLow,
        selectedColor: AppColors.primaryContainer,
        labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.onSurface),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: AppColors.onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.pillR,
          side: const BorderSide(color: Colors.transparent),
        ),
        side: const BorderSide(color: Colors.transparent),
      ),

      // Cards -----------------------------------------------------------
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        margin: EdgeInsets.zero,
      ),

      // Dialogs -----------------------------------------------------------
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      // Bottom sheets -----------------------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        modalBackgroundColor: AppColors.surfaceContainerLowest,
      ),

      // Navigation Bar (M3) -----------------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary, size: 26);
          }
          return const IconThemeData(color: AppColors.onSurfaceVariant, size: 24);
        }),
        height: 72,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // Snackbar -----------------------------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inverseOnSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
      ),

      // Dividers -----------------------------------------------------------
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // Tooltip -----------------------------------------------------------
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.inverseSurface,
          borderRadius: AppRadius.smR,
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: AppColors.inverseOnSurface),
      ),

      // Page transitions -----------------------------------------------------------
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE DECORATIONS
// ─────────────────────────────────────────────────────────────────────────────

class AppDecorations {
  /// Editorial ambient shadow — kept for backward compatibility.
  static List<BoxShadow> get ambientShadow => AppElevation.soft;

  /// Primary gradient button background.
  static BoxDecoration get glassGradientButton => BoxDecoration(
        borderRadius: AppRadius.xlR,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF3B62F0)],
          stops: [0.0, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      );

  /// Standard surface card — main canvas blocks.
  static BoxDecoration get baseCard => BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.lgR,
        boxShadow: AppElevation.soft,
      );

  /// Elevated emphatic card — prominent metrics, key surfaces.
  static BoxDecoration get cardElevated => BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.xlR,
        boxShadow: AppElevation.floating,
      );

  /// Subtle card — flush, no shadow, used inside other cards or as quiet groups.
  static BoxDecoration get cardSubtle => BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4), width: 1),
      );

  /// Content block — non-floating tonal block (no shadow).
  static BoxDecoration get contentBlock => BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.lgR,
      );

  /// Active filter pill.
  static BoxDecoration get activeChip => BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.pillR,
      );

  /// Inactive filter pill.
  static BoxDecoration get inactiveChip => BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.pillR,
      );

  /// Pill filter chip (alias).
  static BoxDecoration get pillFilter => inactiveChip;

  /// Tag/accent pill (used for skill/SDG tags).
  static BoxDecoration tagAccent({Color? color}) => BoxDecoration(
        color: (color ?? AppColors.secondary).withValues(alpha: 0.12),
        borderRadius: AppRadius.pillR,
        border: Border.all(color: (color ?? AppColors.secondary).withValues(alpha: 0.25), width: 1),
      );

  /// Soft gradient page header.
  static BoxDecoration get headerGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE2E8FF), Color(0xFFF4F2EC)],
        ),
      );
}
