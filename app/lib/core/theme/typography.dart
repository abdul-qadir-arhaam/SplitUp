import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SplitUpTypography {
  static TextStyle displayAmount({required Color color}) {
    return GoogleFonts.ibmPlexMono(
      fontSize: 44,
      height: 48 / 44,
      fontWeight: FontWeight.w500,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle titleAmount({required Color color}) {
    return GoogleFonts.ibmPlexMono(
      fontSize: 32,
      height: 36 / 32,
      fontWeight: FontWeight.w500,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle monoMedium({required double size, required Color color}) {
    return GoogleFonts.ibmPlexMono(
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle headline({required Color color}) {
    return GoogleFonts.manrope(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w700,
      color: color,
    );
  }

  static TextStyle title({required Color color}) {
    return GoogleFonts.manrope(
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w600,
      color: color,
    );
  }

  static TextStyle body({required Color color}) {
    return GoogleFonts.manrope(
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
      color: color,
    );
  }

  static TextStyle label({required Color color}) {
    return GoogleFonts.manrope(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w500,
      color: color,
    );
  }

  static TextStyle caption({required Color color}) {
    return GoogleFonts.manrope(
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w500,
      color: color,
    );
  }
}
