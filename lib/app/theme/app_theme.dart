import 'package:flutter/material.dart';

@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.backgroundSoft,
    required this.backgroundDeep,
    required this.panel,
    required this.panelRaised,
    required this.panelMuted,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.info,
    required this.warning,
    required this.danger,
    required this.textPrimary,
    required this.textMuted,
    required this.hover,
    required this.heroGradient,
    required this.backdropGradient,
  });

  final Color background;
  final Color backgroundSoft;
  final Color backgroundDeep;
  final Color panel;
  final Color panelRaised;
  final Color panelMuted;
  final Color border;
  final Color borderStrong;
  final Color accent;
  final Color info;
  final Color warning;
  final Color danger;
  final Color textPrimary;
  final Color textMuted;
  final Color hover;
  final LinearGradient heroGradient;
  final LinearGradient backdropGradient;
}

class AppTheme {
  static const AppPalette darkPalette = AppPalette(
    background: Color(0xFF0F172A),
    backgroundSoft: Color(0xFF111B2E),
    backgroundDeep: Color(0xFF08111E),
    panel: Color(0xFF101A2B),
    panelRaised: Color(0xFF16243B),
    panelMuted: Color(0xFF1A2A43),
    border: Color(0xFF233552),
    borderStrong: Color(0xFF35507A),
    accent: Color(0xFF22C55E),
    info: Color(0xFF38BDF8),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    textPrimary: Color(0xFFF8FAFC),
    textMuted: Color(0xFF94A3B8),
    hover: Color(0x1F38BDF8),
    heroGradient: LinearGradient(
      colors: [Color(0xFF1A2640), Color(0xFF0E1625), Color(0xFF123527)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    backdropGradient: LinearGradient(
      colors: [Color(0xFF0A1220), Color(0xFF0F172A), Color(0xFF08111E)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const AppPalette lightPalette = AppPalette(
    background: Color(0xFFEDF2F9),
    backgroundSoft: Color(0xFFFFFFFF),
    backgroundDeep: Color(0xFFE1E9F3),
    panel: Color(0xFFFFFFFF),
    panelRaised: Color(0xFFFFFFFF),
    panelMuted: Color(0xFFEDF2F9),
    border: Color(0xFFD2DEEB),
    borderStrong: Color(0xFFA6B9D0),
    accent: Color(0xFF15803D),
    info: Color(0xFF0369A1),
    warning: Color(0xFFB45309),
    danger: Color(0xFFB91C1C),
    textPrimary: Color(0xFF16202F),
    textMuted: Color(0xFF5A6A80),
    hover: Color(0x140369A1),
    heroGradient: LinearGradient(
      colors: [Color(0xFFFFFFFF), Color(0xFFF1F7FF), Color(0xFFE9FAF0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    backdropGradient: LinearGradient(
      colors: [Color(0xFFF7FAFE), Color(0xFFEDF3FA), Color(0xFFE4ECF6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static AppPalette colorsOf(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkPalette
        : lightPalette;
  }

  static ThemeData dark() => _buildTheme(darkPalette, Brightness.dark);

  static ThemeData light() => _buildTheme(lightPalette, Brightness.light);

  static ThemeData _buildTheme(AppPalette palette, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: brightness == Brightness.dark
          ? palette.background
          : palette.backgroundSoft,
      secondary: palette.info,
      onSecondary: brightness == Brightness.dark
          ? palette.background
          : palette.backgroundSoft,
      error: palette.danger,
      onError: palette.backgroundSoft,
      surface: palette.panel,
      onSurface: palette.textPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: _monoStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
      headlineLarge: _monoStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
      headlineMedium: _monoStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
      titleLarge: _monoStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
      bodyLarge: _bodyStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: palette.textPrimary,
      ),
      bodyMedium: _bodyStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: palette.textPrimary,
      ),
      bodySmall: _bodyStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: palette.textMuted,
      ),
      labelLarge: _bodyStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background.withValues(
          alpha: brightness == Brightness.dark ? 0.88 : 0.94,
        ),
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.panelRaised,
        contentTextStyle: TextStyle(color: palette.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: palette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: palette.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.panelMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
        labelStyle: TextStyle(color: palette.textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.panelMuted.withValues(alpha: isDark ? 0.58 : 0.8);
            }
            if (states.contains(WidgetState.pressed)) {
              return _mix(
                palette.accent,
                isDark ? Colors.white : Colors.black,
                isDark ? 0.18 : 0.16,
              );
            }
            if (states.contains(WidgetState.hovered)) {
              return _mix(
                palette.accent,
                isDark ? Colors.white : Colors.black,
                isDark ? 0.1 : 0.08,
              );
            }
            return palette.accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.textMuted.withValues(alpha: 0.62);
            }
            return colorScheme.onPrimary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return colorScheme.onPrimary.withValues(alpha: 0.12);
            }
            return Colors.transparent;
          }),
          side: const WidgetStatePropertyAll(
            BorderSide(color: Colors.transparent),
          ),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: WidgetStatePropertyAll(
            palette.backgroundDeep.withValues(alpha: isDark ? 0.18 : 0.08),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.textMuted.withValues(alpha: 0.62);
            }
            return colorScheme.onPrimary;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.panelMuted.withValues(alpha: isDark ? 0.46 : 0.62);
            }
            if (states.contains(WidgetState.pressed)) {
              return palette.panelMuted.withValues(alpha: isDark ? 0.92 : 0.9);
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.panelRaised.withValues(
                alpha: isDark ? 0.98 : 0.94,
              );
            }
            return palette.panelRaised.withValues(alpha: isDark ? 0.94 : 0.88);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.textMuted.withValues(alpha: 0.7);
            }
            return palette.textPrimary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return palette.info.withValues(alpha: 0.05);
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.info.withValues(alpha: 0.03);
            }
            return null;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: palette.border.withValues(alpha: 0.4));
            }
            return BorderSide(
              color: palette.borderStrong.withValues(alpha: isDark ? 0.7 : 0.6),
            );
          }),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: WidgetStatePropertyAll(
            palette.backgroundDeep.withValues(alpha: isDark ? 0.16 : 0.06),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.textMuted.withValues(alpha: 0.7);
            }
            return palette.textPrimary;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(palette.info),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return palette.info.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.info.withValues(alpha: 0.04);
            }
            return null;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.info.withValues(alpha: isDark ? 0.22 : 0.14);
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.panelMuted.withValues(alpha: isDark ? 0.88 : 0.8);
            }
            return palette.panelRaised.withValues(alpha: isDark ? 0.94 : 0.88);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.info;
            }
            return palette.textPrimary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return palette.info.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.info.withValues(alpha: 0.04);
            }
            return null;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: palette.borderStrong.withValues(
                alpha: isDark ? 0.55 : 0.38,
              ),
            ),
          ),
          shadowColor: WidgetStatePropertyAll(
            palette.backgroundDeep.withValues(alpha: isDark ? 0.18 : 0.08),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.info;
            }
            return palette.textPrimary;
          }),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.panelMuted,
        selectedColor: palette.accent.withValues(alpha: 0.18),
        side: BorderSide(color: palette.border),
        labelStyle: textTheme.bodySmall?.copyWith(color: palette.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  static TextStyle _bodyStyle({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: 'IBM Plex Sans',
      fontFamilyFallback: const [
        'Fira Sans',
        'Inter',
        'SF Pro Text',
        'Segoe UI',
        'Noto Sans',
        'Arial',
      ],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  static TextStyle _monoStyle({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const [
        'Fira Code',
        'SF Mono',
        'Consolas',
        'Monaco',
        'Menlo',
      ],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }
}

Color _mix(Color base, Color overlay, double alpha) {
  return Color.alphaBlend(overlay.withValues(alpha: alpha), base);
}
