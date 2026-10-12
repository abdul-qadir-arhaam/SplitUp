import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

enum AppLogoVariant {
  symbolOnly,
  horizontal,
}

class AppLogo extends StatelessWidget {
  final AppLogoVariant variant;
  final double size;
  final double? fontSize;
  final bool? isDark;
  final bool mono;
  final Color? textColor;

  const AppLogo({
    super.key,
    this.variant = AppLogoVariant.horizontal,
    this.size = 36,
    this.fontSize,
    this.isDark,
    this.mono = false,
    this.textColor,
  });

  const AppLogo.symbol({
    super.key,
    this.size = 36,
    this.isDark,
    this.mono = false,
    this.textColor,
  })  : variant = AppLogoVariant.symbolOnly,
        fontSize = null;

  const AppLogo.horizontal({
    super.key,
    this.size = 36,
    this.fontSize,
    this.isDark,
    this.mono = false,
    this.textColor,
  }) : variant = AppLogoVariant.horizontal;

  String _getAssetPath(bool dark) {
    if (mono) {
      return dark
          ? 'assets/brand/symbol_mono_white.svg'
          : 'assets/brand/symbol_mono_dark.svg';
    }
    return dark
        ? 'assets/brand/symbol_dark.svg'
        : 'assets/brand/symbol_light.svg';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDark = isDark ?? (Theme.of(context).brightness == Brightness.dark);
    final assetPath = _getAssetPath(effectiveDark);
    final colors = context.colors;

    final symbolWidget = SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
    );

    if (variant == AppLogoVariant.symbolOnly) {
      return symbolWidget;
    }

    final double effectiveFontSize = fontSize ?? (size * 0.72);
    final effectiveTextColor = textColor ?? colors.textPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        symbolWidget,
        SizedBox(width: size * 0.28),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Split',
                style: GoogleFonts.manrope(
                  fontSize: effectiveFontSize,
                  fontWeight: FontWeight.w800,
                  color: effectiveTextColor,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'Up',
                style: GoogleFonts.manrope(
                  fontSize: effectiveFontSize,
                  fontWeight: FontWeight.w800,
                  color: effectiveDark ? const Color(0xFF1FA67A) : const Color(0xFF0F7F5C),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
