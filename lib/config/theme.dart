import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // SevaSetu Professional Palette: The Compassionate Ledger
  static const Color background = Color(0xFFfbf9f9);
  static const Color error = Color(0xFFba1a1a);
  static const Color errorContainer = Color(0xFFffdad6);
  static const Color inverseOnSurface = Color(0xFFf2f0f0);
  static const Color inversePrimary = Color(0xFFbdc2ff);
  static const Color inverseSurface = Color(0xFF303031);
  static const Color onBackground = Color(0xFF1b1c1c);
  static const Color onError = Color(0xFFffffff);
  static const Color onErrorContainer = Color(0xFF93000a);
  static const Color onPrimary = Color(0xFFffffff);
  static const Color onPrimaryContainer = Color(0xFF8690ee);
  static const Color onPrimaryFixed = Color(0xFF000767);
  static const Color onPrimaryFixedVariant = Color(0xFF343d96);
  static const Color onSecondary = Color(0xFFffffff);
  static const Color onSecondaryContainer = Color(0xFF631800);
  static const Color onSecondaryFixed = Color(0xFF3a0a00);
  static const Color onSecondaryFixedVariant = Color(0xFF852300);
  static const Color onSurface = Color(0xFF1b1c1c);
  static const Color onSurfaceVariant = Color(0xFF454652);
  static const Color onTertiary = Color(0xFFffffff);
  static const Color onTertiaryContainer = Color(0xFF63a768);
  static const Color onTertiaryFixed = Color(0xFF002107);
  static const Color onTertiaryFixedVariant = Color(0xFF07521d);
  static const Color outline = Color(0xFF767683);
  static const Color outlineVariant = Color(0xFFc6c5d4);
  static const Color primary = Color(0xFF000666);
  static const Color primaryContainer = Color(0xFF1a237e);
  static const Color primaryFixed = Color(0xFFe0e0ff);
  static const Color primaryFixedDim = Color(0xFFbdc2ff);
  static const Color secondary = Color(0xFFac3509);
  static const Color secondaryContainer = Color(0xFFfe6f42);
  static const Color secondaryFixed = Color(0xFFffdbd0);
  static const Color secondaryFixedDim = Color(0xFFffb59f);
  static const Color surface = Color(0xFFfbf9f9);
  static const Color surfaceBright = Color(0xFFfbf9f9);
  static const Color surfaceContainer = Color(0xFFefeded);
  static const Color surfaceContainerHigh = Color(0xFFe9e8e7);
  static const Color surfaceContainerHighest = Color(0xFFe3e2e2);
  static const Color surfaceContainerLow = Color(0xFFf5f3f3);
  static const Color surfaceContainerLowest = Color(0xFFffffff);
  static const Color surfaceDim = Color(0xFFdbdad9);
  static const Color surfaceTint = Color(0xFF4c56af);
  static const Color surfaceVariant = Color(0xFFe3e2e2);
  static const Color tertiary = Color(0xFF002107);
  static const Color tertiaryContainer = Color(0xFF003910);
  static const Color tertiaryFixed = Color(0xFFabf4ac);
  static const Color tertiaryFixedDim = Color(0xFF90d792);

  // Backward compatibility mappings
  static const Color success = tertiaryFixedDim;
  static const Color warning = secondary;
  static const Color info = primaryFixedDim;

  // Urgency mapping
  static const Color urgencyCritical = error;
  static const Color urgencyHigh = secondary;
  static const Color urgencyMedium = warning;
  static const Color urgencyLow = success;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.secondary,
        tertiary: AppColors.tertiary,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.manrope(fontSize: 56, fontWeight: FontWeight.w700, letterSpacing: -1.12, color: AppColors.onSurface),
        displayMedium: GoogleFonts.manrope(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -0.96, color: AppColors.onSurface),
        displaySmall: GoogleFonts.manrope(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.80, color: AppColors.onSurface),
        headlineLarge: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.64, color: AppColors.onSurface),
        headlineSmall: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.48, color: AppColors.onSurface),
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.onSurface),
        titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface),
        titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.onSurfaceVariant),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.onSurfaceVariant),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.onSurfaceVariant),
        labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.14, color: AppColors.onSurfaceVariant),
        labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: AppColors.onSurfaceVariant),
        labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AppColors.onSurfaceVariant),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        titleTextStyle: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, // Controlled by container gradient
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // xl radius mapped to 12
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ).copyWith(
          // Gradient implementation must be done via Ink/Container wraps since ElevatedButton doesn't natively do gradients easily
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        selectedColor: AppColors.primaryContainer,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onSurface),
        secondaryLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.transparent),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}

class AppDecorations {
  // Editorial ambient shadow for floating elements
  static List<BoxShadow> get ambientShadow => [
    BoxShadow(
      color: Color(0x0F1B1C1C), // rgba(27, 28, 28, 0.06) mapped to roughly 6-10%
      blurRadius: 32,
      spreadRadius: 0,
      offset: const Offset(0, 12),
    )
  ];

  static BoxDecoration get glassGradientButton => BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primary, AppColors.primaryContainer],
      stops: [0.0, 1.0],
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.25),
        blurRadius: 16,
        offset: const Offset(0, 8),
      )
    ],
  );

  static BoxDecoration get baseCard => BoxDecoration(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(12), 
    boxShadow: ambientShadow,
  );
  
  static BoxDecoration get contentBlock => BoxDecoration(
    color: AppColors.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    // Intentionally no shadow on sub-blocks (No Line, Tonal Shift rule)
  );

  static BoxDecoration get activeChip => BoxDecoration(
    color: AppColors.tertiaryFixedDim.withValues(alpha: 0.8),
    borderRadius: BorderRadius.circular(12),
  );
  
  static BoxDecoration get inactiveChip => BoxDecoration(
    color: AppColors.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(12),
  );
}
