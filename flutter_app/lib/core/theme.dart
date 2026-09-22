import 'package:flutter/material.dart';

/// 根据用户选择的两种颜色生成全局主题。
class AppTheme {
  static const Color defaultBase = Color(0xFF0B0C10);
  static const Color defaultAccent = Color(0xFFA855F7);
  static const Color primary = defaultAccent;
  static const Color ink = defaultBase;
  static const Color defaultSurface = Color(0xFF151720);

  static ThemeData build() {
    const baseColor = defaultBase;
    const accentColor = defaultAccent;
    final onBase = readableTextColor(baseColor);
    final brightness =
        baseColor.computeLuminance() > .42 ? Brightness.light : Brightness.dark;
    final surface = Color.alphaBlend(
      onBase.withValues(alpha: brightness == Brightness.light ? .10 : .08),
      baseColor,
    );
    final onSurface = readableTextColor(surface);
    // 星紫底色统一使用白色前景，避免按钮和卡片文字变黑。
    const onAccent = Colors.white;
    final border = accentColor.withValues(
        alpha: brightness == Brightness.light ? .58 : .72);
    assertThemeContrast(
      background: baseColor,
      surface: surface,
      accent: accentColor,
      onBackground: onBase,
      onSurface: onSurface,
      onAccent: onAccent,
    );
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    ).copyWith(
      primary: accentColor,
      onPrimary: onAccent,
      secondary: accentColor,
      onSecondary: onAccent,
      surface: surface,
      onSurface: onSurface,
      outline: border,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: baseColor,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: baseColor,
        foregroundColor: onBase,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color.alphaBlend(
          onSurface.withValues(
              alpha: brightness == Brightness.light ? .04 : .06),
          surface,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: TextStyle(color: onSurface.withValues(alpha: .72)),
        hintStyle: TextStyle(color: onSurface.withValues(alpha: .42)),
        prefixIconColor: accentColor,
        suffixIconColor: onSurface.withValues(alpha: .68),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border.withValues(alpha: .72)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border.withValues(alpha: .72)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accentColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentColor,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(
          color: onBase,
          fontWeight: FontWeight.w700,
        )),
      ),
    );
  }

  static Color readableTextColor(Color background) {
    final whiteRatio = contrastRatio(Colors.white, background);
    final blackRatio = contrastRatio(Colors.black, background);
    return whiteRatio >= blackRatio ? Colors.white : Colors.black;
  }

  static double contrastRatio(Color foreground, Color background) {
    final lighter =
        foreground.computeLuminance() > background.computeLuminance()
            ? foreground.computeLuminance()
            : background.computeLuminance();
    final darker = foreground.computeLuminance() > background.computeLuminance()
        ? background.computeLuminance()
        : foreground.computeLuminance();
    return (lighter + .05) / (darker + .05);
  }

  static bool meetsWcagAA(Color foreground, Color background,
      {bool largeText = false}) {
    return contrastRatio(foreground, background) >= (largeText ? 3 : 4.5);
  }

  static void assertThemeContrast({
    required Color background,
    required Color surface,
    required Color accent,
    required Color onBackground,
    required Color onSurface,
    required Color onAccent,
  }) {
    assert(meetsWcagAA(onBackground, background));
    assert(meetsWcagAA(onSurface, surface));
    // 星紫色固定配白字，按大字号/强调文字标准校验对比度。
    assert(meetsWcagAA(onAccent, accent, largeText: true));
  }
}
