import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Terra Ethos Palette - Premium, Human-centric, Earthy
  static const Color surface = Color(0xFFFAF9F5);
  static const Color surfaceDim = Color(0xFFDBDAD6);
  static const Color surfaceContainerLow = Color(0xFFF4F4F0);
  static const Color surfaceContainer = Color(0xFFEEEEEA);
  static const Color surfaceContainerHigh = Color(0xFFE9E8E4);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  
  static const Color primary = Color(0xFF334F2B);
  static const Color primaryContainer = Color(0xFF4A6741);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFC2E4B4);
  
  static const Color tertiary = Color(0xFF5F412B);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF795841);
  
  static const Color onSurface = Color(0xFF1B1C1A);
  static const Color onSurfaceVariant = Color(0xFF434840);
  static const Color outline = Color(0xFF73796F);
  static const Color outlineVariant = Color(0xFFC3C8BD);

  // Status Colors (Earthy variants)
  static const Color success = Color(0xFF4A6549); // Secondary
  static const Color warning = Color(0xFF967259); // Tertiary override
  static const Color error = Color(0xFFBA1A1A);
  static const Color info = Color(0xFF8BA888); // Secondary override

  // Urgency mapping
  static const Color urgencyCritical = error;
  static const Color urgencyHigh = tertiary;
  static const Color urgencyMedium = warning;
  static const Color urgencyLow = success;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.success,
        tertiary: AppColors.tertiary,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.manrope(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -0.96, color: AppColors.onSurface),
        displayMedium: GoogleFonts.manrope(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: AppColors.onSurface),
        headlineLarge: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.64, color: AppColors.onSurface),
        headlineSmall: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.48, color: AppColors.onSurface),
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.onSurface),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.onSurfaceVariant),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.onSurfaceVariant),
        labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        titleTextStyle: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(48)), // xl radius
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        selectedColor: AppColors.tertiary,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onSurface),
        secondaryLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onTertiary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: StadiumBorder(side: BorderSide(color: Colors.transparent)),
      ),
    );
  }
}

class AppDecorations {
  // Ambient Diffusion - No harsh digital drop shadows
  static List<BoxShadow> get ambientShadow => [
    BoxShadow(
      color: AppColors.onSurface.withValues(alpha: 0.12),
      blurRadius: 40,
      spreadRadius: -10,
      offset: const Offset(0, 10),
    )
  ];

  // For base cards (surface container lowest on surface)
  static BoxDecoration get baseCard => BoxDecoration(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(32), // lg radius
    boxShadow: ambientShadow,
  );
  
  // For content blocks (surface container low on surface)
  static BoxDecoration get contentBlock => BoxDecoration(
    color: AppColors.surfaceContainerLow,
    borderRadius: BorderRadius.circular(24),
  );

  static BoxDecoration get activeChip => BoxDecoration(
    color: AppColors.tertiary,
    borderRadius: BorderRadius.circular(9999),
  );
  
  static BoxDecoration get inactiveChip => BoxDecoration(
    color: AppColors.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(9999),
  );
}
