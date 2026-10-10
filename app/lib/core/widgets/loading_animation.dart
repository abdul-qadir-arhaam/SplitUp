import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import 'app_background.dart';

/// Premium animated SplitUp loading spinner with dual counter-rotating glowing arcs
/// and a pulsating brand node center.
class SplitUpLoadingAnimation extends StatefulWidget {
  final double size;
  final String? message;
  final Color? primaryColor;
  final Color? secondaryColor;

  const SplitUpLoadingAnimation({
    super.key,
    this.size = 64,
    this.message,
    this.primaryColor,
    this.secondaryColor,
  });

  @override
  State<SplitUpLoadingAnimation> createState() => _SplitUpLoadingAnimationState();
}

class _SplitUpLoadingAnimationState extends State<SplitUpLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = widget.primaryColor ?? colors.accentReceive;
    final secondary = widget.secondaryColor ?? colors.accentBrass;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Ambient soft breathing glow behind spinner
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final pulse = 0.85 + 0.25 * math.sin(_controller.value * 2 * math.pi);
                return Container(
                  width: widget.size * 1.35 * pulse,
                  height: widget.size * 1.35 * pulse,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.18),
                        blurRadius: 28,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                );
              },
            ),

            // Rotating arcs
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _DualArcPainter(
                      progress: _controller.value,
                      primaryColor: primary,
                      secondaryColor: secondary,
                    ),
                  );
                },
              ),
            ),

            // Pulsating central core
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final scale = 0.88 + 0.16 * math.sin(_controller.value * 2 * math.pi);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size * 0.32,
                    height: widget.size * 0.32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          primary,
                          secondary.withValues(alpha: 0.6),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: widget.size * 0.12,
                        height: widget.size * 0.12,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 18),
          _ShimmeringText(
            text: widget.message!,
            color: colors.textPrimary,
          ),
        ],
      ],
    );
  }
}

class _DualArcPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;

  _DualArcPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.085;
    final center = Offset(size.width / 2, size.height / 2);

    // Outer Arc (Clockwise)
    final outerRadius = (size.width - strokeWidth) / 2;
    final outerAngle = progress * 2 * math.pi;
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = primaryColor;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      outerAngle,
      math.pi * 1.3,
      false,
      outerPaint,
    );

    // Inner Arc (Counter-Clockwise)
    final innerRadius = outerRadius - strokeWidth * 1.5;
    final innerAngle = -progress * 2 * math.pi;
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.8
      ..strokeCap = StrokeCap.round
      ..color = secondaryColor;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      innerAngle,
      math.pi * 0.95,
      false,
      innerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DualArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.secondaryColor != secondaryColor;
}

class _ShimmeringText extends StatefulWidget {
  final String text;
  final Color color;

  const _ShimmeringText({required this.text, required this.color});

  @override
  State<_ShimmeringText> createState() => _ShimmeringTextState();
}

class _ShimmeringTextState extends State<_ShimmeringText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _textController;

  @override
  void initState() {
    super.initState();
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _textController,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color.withValues(alpha: 0.45),
                widget.color,
                widget.color.withValues(alpha: 0.45),
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: _textController.value),
            ).createShader(bounds);
          },
          child: Text(
            widget.text,
            style: SplitUpTypography.body(color: widget.color).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2 - 1), 0.0, 0.0);
  }
}

/// Full screen animated loading view with SplitUp background styling
class SplitUpLoadingView extends StatelessWidget {
  final String message;
  final double size;

  const SplitUpLoadingView({
    super.key,
    this.message = 'Loading...',
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Center(
        child: SplitUpLoadingAnimation(
          size: size,
          message: message,
        ),
      ),
    );
  }
}

/// Shimmer placeholder container for skeleton cards
class SplitUpShimmer extends StatefulWidget {
  final Widget child;

  const SplitUpShimmer({super.key, required this.child});

  @override
  State<SplitUpShimmer> createState() => _SplitUpShimmerState();
}

class _SplitUpShimmerState extends State<SplitUpShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final baseColor = colors.surfaceFlat;
    final highlightColor = colors.surfaceFlatRaised;

    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.1, 0.5, 0.9],
              transform: _SlidingGradientTransform(slidePercent: _shimmerController.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// Shimmer Skeleton List Placeholder
class SplitUpSkeletonList extends StatelessWidget {
  final int count;

  const SplitUpSkeletonList({
    super.key,
    this.count = 4,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SplitUpShimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.surfaceFlatRaised,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 120,
                        decoration: BoxDecoration(
                          color: colors.surfaceFlatRaised,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 80,
                        decoration: BoxDecoration(
                          color: colors.surfaceFlatRaised,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 18,
                  width: 50,
                  decoration: BoxDecoration(
                    color: colors.surfaceFlatRaised,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
