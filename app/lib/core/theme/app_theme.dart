import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData dark() {
    const colors = SplitUpColors.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.bgBase,
      colorScheme: ColorScheme.dark(
        surface: colors.surfaceFlat,
        primary: colors.accentReceive,
        secondary: colors.accentBrass,
        error: colors.accentOwe,
        onSurface: colors.textPrimary,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.manropeTextTheme().apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      extensions: const [colors],
    );
  }

  static ThemeData light() {
    const colors = SplitUpColors.light;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colors.bgBase,
      colorScheme: ColorScheme.light(
        surface: colors.surfaceFlat,
        primary: colors.accentReceive,
        secondary: colors.accentBrass,
        error: colors.accentOwe,
        onSurface: colors.textPrimary,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.manropeTextTheme().apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      extensions: const [colors],
    );
  }
}
