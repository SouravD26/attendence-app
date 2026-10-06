import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Central design tokens for the app. Everything visual derives from here so
/// light/dark stay in lockstep and screens never hardcode a colour.
class AppTheme {
  static const seed = Color(0xFF2F6BFF);
  static const success = Color(0xFF17B26A);
  static const warning = Color(0xFFF79009);
  static const danger = Color(0xFFF04438);

  static const radius = 20.0;
  static const gutter = 20.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;
    final surface = isLight ? const Color(0xFFF6F7FB) : const Color(0xFF0E1116);
    final card = isLight ? Colors.white : const Color(0xFF171B22);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(surface: surface),
      scaffoldBackgroundColor: surface,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

/// Soft gradient used behind hero surfaces (punch card, login header).
LinearGradient brandGradient(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [scheme.primary, Color.lerp(scheme.primary, AppTheme.seed, 0.4)!],
  );
}
