import 'package:flutter/material.dart';

@immutable
class SplitUpColors extends ThemeExtension<SplitUpColors> {
  final Color bgBase;
  final Color bgBlobEmerald;
  final Color bgBlobBrass;
  final Color bgBlobTeal;
  final Color surfaceFlat;
  final Color surfaceFlatRaised;
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accentReceive;
  final Color accentOwe;
  final Color accentBrass;
  final Color statusWarn;
  final Color statusInfo;
  final Color divider;

  const SplitUpColors({
    required this.bgBase,
    required this.bgBlobEmerald,
    required this.bgBlobBrass,
    required this.bgBlobTeal,
    required this.surfaceFlat,
    required this.surfaceFlatRaised,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accentReceive,
    required this.accentOwe,
    required this.accentBrass,
    required this.statusWarn,
    required this.statusInfo,
    required this.divider,
  });

  static const dark = SplitUpColors(
    bgBase: Color(0xFF0A1411),
    bgBlobEmerald: Color(0xFF1FA67A),
    bgBlobBrass: Color(0xFFC9A961),
    bgBlobTeal: Color(0xFF0E5C63),
    surfaceFlat: Color(0xFF111C18),
    surfaceFlatRaised: Color(0xFF16241F),
    glassFill: Color(0x24FFFFFF), // ~14%
    glassFillStrong: Color(0x38FFFFFF), // ~22%
    glassBorder: Color(0x4DFFFFFF), // ~30%
    textPrimary: Color(0xFFF3F1EA),
    textSecondary: Color(0xFFA9B4AF),
    textMuted: Color(0xFF6E7B76),
    accentReceive: Color(0xFF1FA67A),
    accentOwe: Color(0xFFE0674A),
    accentBrass: Color(0xFFC9A961),
    statusWarn: Color(0xFFE3A33B),
    statusInfo: Color(0xFF5BA7B8),
    divider: Color(0x14FFFFFF), // 8%
  );

  static const light = SplitUpColors(
    bgBase: Color(0xFFF5F2EA),
    bgBlobEmerald: Color(0xFF1FA67A),
    bgBlobBrass: Color(0xFFC9A961),
    bgBlobTeal: Color(0xFF0E5C63),
    surfaceFlat: Color(0xFFFFFFFF),
    surfaceFlatRaised: Color(0xFFEFEBE0),
    glassFill: Color(0x99FFFFFF), // ~60%
    glassFillStrong: Color(0xCCFFFFFF), // ~80%
    glassBorder: Color(0xB3FFFFFF), // ~70%
    textPrimary: Color(0xFF14201C),
    textSecondary: Color(0xFF4B5A54),
    textMuted: Color(0xFF86938D),
    accentReceive: Color(0xFF0F7F5C),
    accentOwe: Color(0xFFC4482C),
    accentBrass: Color(0xFF9A7B2F),
    statusWarn: Color(0xFFE3A33B),
    statusInfo: Color(0xFF5BA7B8),
    divider: Color(0x1414201C), // 8%
  );

  @override
  SplitUpColors copyWith({
    Color? bgBase,
    Color? bgBlobEmerald,
    Color? bgBlobBrass,
    Color? bgBlobTeal,
    Color? surfaceFlat,
    Color? surfaceFlatRaised,
    Color? glassFill,
    Color? glassFillStrong,
    Color? glassBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accentReceive,
    Color? accentOwe,
    Color? accentBrass,
    Color? statusWarn,
    Color? statusInfo,
    Color? divider,
  }) {
    return SplitUpColors(
      bgBase: bgBase ?? this.bgBase,
      bgBlobEmerald: bgBlobEmerald ?? this.bgBlobEmerald,
      bgBlobBrass: bgBlobBrass ?? this.bgBlobBrass,
      bgBlobTeal: bgBlobTeal ?? this.bgBlobTeal,
      surfaceFlat: surfaceFlat ?? this.surfaceFlat,
      surfaceFlatRaised: surfaceFlatRaised ?? this.surfaceFlatRaised,
      glassFill: glassFill ?? this.glassFill,
      glassFillStrong: glassFillStrong ?? this.glassFillStrong,
      glassBorder: glassBorder ?? this.glassBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accentReceive: accentReceive ?? this.accentReceive,
      accentOwe: accentOwe ?? this.accentOwe,
      accentBrass: accentBrass ?? this.accentBrass,
      statusWarn: statusWarn ?? this.statusWarn,
      statusInfo: statusInfo ?? this.statusInfo,
      divider: divider ?? this.divider,
    );
  }

  @override
  SplitUpColors lerp(ThemeExtension<SplitUpColors>? other, double t) {
    if (other is! SplitUpColors) return this;
    return SplitUpColors(
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      bgBlobEmerald: Color.lerp(bgBlobEmerald, other.bgBlobEmerald, t)!,
      bgBlobBrass: Color.lerp(bgBlobBrass, other.bgBlobBrass, t)!,
      bgBlobTeal: Color.lerp(bgBlobTeal, other.bgBlobTeal, t)!,
      surfaceFlat: Color.lerp(surfaceFlat, other.surfaceFlat, t)!,
      surfaceFlatRaised: Color.lerp(surfaceFlatRaised, other.surfaceFlatRaised, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassFillStrong: Color.lerp(glassFillStrong, other.glassFillStrong, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accentReceive: Color.lerp(accentReceive, other.accentReceive, t)!,
      accentOwe: Color.lerp(accentOwe, other.accentOwe, t)!,
      accentBrass: Color.lerp(accentBrass, other.accentBrass, t)!,
      statusWarn: Color.lerp(statusWarn, other.statusWarn, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

extension BuildContextColors on BuildContext {
  SplitUpColors get colors =>
      Theme.of(this).extension<SplitUpColors>() ?? SplitUpColors.dark;
}
