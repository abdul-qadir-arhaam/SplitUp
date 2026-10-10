import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Glass app bar or navigation bar.
class GlassBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;

  const GlassBar({
    super.key,
    required this.child,
    this.height = 64,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: colors.glassFill,
            border: Border(
              bottom: BorderSide(color: colors.divider, width: 1),
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// Glass Bottom Sheet with drag handle
class GlassSheet extends StatelessWidget {
  final Widget child;
  final double? maxHeight;
  final EdgeInsetsGeometry padding;

  const GlassSheet({
    super.key,
    required this.child,
    this.maxHeight,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: maxHeight != null ? BoxConstraints(maxHeight: maxHeight!) : null,
          padding: padding,
          decoration: BoxDecoration(
            color: colors.surfaceFlatRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: colors.glassBorder, width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pill drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
