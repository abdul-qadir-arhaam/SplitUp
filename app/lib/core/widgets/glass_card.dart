import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Apple-style glassmorphic container panel.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool strong;
  final VoidCallback? onTap;
  final Color? customFill;
  final Border? customBorder;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 20,
    this.strong = false,
    this.onTap,
    this.customFill,
    this.customBorder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = customFill ?? (strong ? colors.glassFillStrong : colors.glassFill);
    final border = customBorder ?? Border.all(color: colors.glassBorder, width: 1);

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border,
          ),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}
