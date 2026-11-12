import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.showShadow = true,
    this.radius = 22,
    this.backgroundAlpha,
    this.borderAlpha,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showShadow;
  final double radius;
  final double? backgroundAlpha;
  final double? borderAlpha;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.panel.withValues(
          alpha: backgroundAlpha ?? (isDark ? 0.84 : 0.92),
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: colors.border.withValues(
            alpha: borderAlpha ?? (isDark ? 0.58 : 0.85),
          ),
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: isDark
                      ? const Color(0x24000000)
                      : const Color(0x140F172A),
                  blurRadius: isDark ? 14 : 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
