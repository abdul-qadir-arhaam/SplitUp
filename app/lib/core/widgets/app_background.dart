import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Renders the signature SplitUp background with ambient blurred colored blobs.
/// Encapsulated in a [RepaintBoundary] to ensure high-performance rendering.
class AppBackground extends StatelessWidget {
  final Widget child;
  final bool reducedEffects;

  const AppBackground({
    super.key,
    required this.child,
    this.reducedEffects = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (reducedEffects) {
      return Container(
        color: colors.bgBase,
        child: child,
      );
    }

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base color
          Container(color: colors.bgBase),

          // Ambient blob 1: Emerald top-right
          Positioned(
            top: -60,
            right: -60,
            child: _BlurredBlob(
              color: colors.bgBlobEmerald.withValues(alpha: isDark ? 0.38 : 0.20),
              size: 260,
              blur: 90,
            ),
          ),

          // Ambient blob 2: Teal center-left
          Positioned(
            top: 240,
            left: -80,
            child: _BlurredBlob(
              color: colors.bgBlobTeal.withValues(alpha: isDark ? 0.30 : 0.16),
              size: 280,
              blur: 100,
            ),
          ),

          // Ambient blob 3: Brass bottom-right
          Positioned(
            bottom: 40,
            right: -60,
            child: _BlurredBlob(
              color: colors.bgBlobBrass.withValues(alpha: isDark ? 0.22 : 0.14),
              size: 240,
              blur: 85,
            ),
          ),

          // Subtle gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  colors.bgBase.withValues(alpha: isDark ? 0.4 : 0.2),
                ],
              ),
            ),
          ),

          // Forefront child
          child,
        ],
      ),
    );
  }
}

class _BlurredBlob extends StatelessWidget {
  final Color color;
  final double size;
  final double blur;

  const _BlurredBlob({
    required this.color,
    required this.size,
    required this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
