import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens. One accent (ember) used sparingly; everything else is ink
/// on paper. Fast-Track gets a muted gold.
@immutable
class FinderColors extends ThemeExtension<FinderColors> {
  const FinderColors({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.hair,
    required this.accent,
    required this.accentSoft,
    required this.gold,
    required this.goldSoft,
    required this.ok,
  });

  final Color paper, surface, ink, ink2, muted, hair, accent, accentSoft, gold, goldSoft, ok;

  static const light = FinderColors(
    paper: Color(0xFFF6F6F4),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF111113),
    ink2: Color(0xFF4B4B52),
    muted: Color(0xFF8E8E96),
    hair: Color(0x14111113),
    accent: Color(0xFFFF4A2B),
    accentSoft: Color(0xFFFFEDE8),
    gold: Color(0xFFB8945A),
    goldSoft: Color(0xFFF4EEE3),
    ok: Color(0xFF1F9D63),
  );

  static const dark = FinderColors(
    paper: Color(0xFF0B0B0C),
    surface: Color(0xFF161618),
    ink: Color(0xFFF5F5F4),
    ink2: Color(0xFFB4B4BA),
    muted: Color(0xFF77777F),
    hair: Color(0x14FFFFFF),
    accent: Color(0xFFFF5A3D),
    accentSoft: Color(0xFF2A1510),
    gold: Color(0xFFCDAA6E),
    goldSoft: Color(0xFF221D14),
    ok: Color(0xFF34C17E),
  );

  @override
  FinderColors copyWith() => this;

  @override
  FinderColors lerp(ThemeExtension<FinderColors>? other, double t) {
    if (other is! FinderColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return FinderColors(
      paper: l(paper, other.paper),
      surface: l(surface, other.surface),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      muted: l(muted, other.muted),
      hair: l(hair, other.hair),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      gold: l(gold, other.gold),
      goldSoft: l(goldSoft, other.goldSoft),
      ok: l(ok, other.ok),
    );
  }
}

extension FinderThemeX on BuildContext {
  FinderColors get fc => Theme.of(this).extension<FinderColors>()!;
}

/// Motion tokens (emil-design-eng / apple-design): strong ease-out for
/// entering UI, iOS drawer curve for sheets and pushes, everything < 300 ms
/// except rare, celebratory moments.
class Motion {
  static const easeOut = Cubic(0.23, 1, 0.32, 1);
  static const easeInOut = Cubic(0.77, 0, 0.175, 1);
  static const drawer = Cubic(0.32, 0.72, 0, 1);
  static const press = Duration(milliseconds: 120);
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const sheet = Duration(milliseconds: 320);

  /// Respect the OS "remove animations" setting.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}

// Legacy names kept for screens that still reference them.
class AppColors {
  static const brand = Color(0xFFFF4A2B);
  static const brandDeep = Color(0xFFD7265A);
  static const gold = Color(0xFFB8945A);
  static const pass = Color(0xFF8E8E96);
  static const ink = Color(0xFF111113);
  static const surface = Color(0xFFF6F6F4);
  static const vipGradient = LinearGradient(colors: [Color(0xFFCDAA6E), Color(0xFFB8945A)]);
  static const brandGradient = LinearGradient(colors: [Color(0xFF2A2A2E), Color(0xFF111113)]);
}

TextTheme _type(Color ink, Color ink2) {
  // Size-specific tracking: tight for display, neutral for body.
  TextStyle s(double size, FontWeight w, double tracking, double height, [Color? c]) => TextStyle(
        fontFamily: 'Geist',
        fontSize: size,
        fontWeight: w,
        letterSpacing: size * tracking,
        height: height,
        color: c ?? ink,
      );
  return TextTheme(
    displaySmall: s(38, FontWeight.w600, -0.035, 1.05),
    headlineMedium: s(30, FontWeight.w600, -0.035, 1.1),
    headlineSmall: s(26, FontWeight.w600, -0.03, 1.15),
    titleLarge: s(20, FontWeight.w600, -0.02, 1.2),
    titleMedium: s(16, FontWeight.w600, -0.01, 1.3),
    titleSmall: s(14, FontWeight.w600, 0, 1.3),
    bodyLarge: s(16, FontWeight.w400, 0, 1.45, ink2),
    bodyMedium: s(15, FontWeight.w400, 0, 1.4, ink2),
    bodySmall: s(13, FontWeight.w400, 0, 1.35, ink2),
    labelLarge: s(15.5, FontWeight.w600, 0, 1.2),
    labelMedium: s(13, FontWeight.w500, 0, 1.2),
    labelSmall: s(11, FontWeight.w600, 0.04, 1.2),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? FinderColors.light : FinderColors.dark;
  final scheme = ColorScheme.fromSeed(seedColor: c.ink, brightness: brightness).copyWith(
    primary: c.ink,
    onPrimary: c.paper,
    secondary: c.accent,
    surface: c.surface,
    onSurface: c.ink,
    outline: c.hair,
    error: const Color(0xFFE5484D),
  );
  final text = _type(c.ink, c.ink2);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Geist',
    textTheme: text,
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.paper,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    // iOS-style push/pop everywhere (spatially consistent, interruptible by edge swipe on iOS).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: brightness == Brightness.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      titleTextStyle: text.headlineSmall,
    ),
    dividerTheme: DividerThemeData(color: c.hair, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.ink2,
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodySmall?.copyWith(color: c.muted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: text.bodyLarge?.copyWith(color: c.muted),
      labelStyle: text.bodyMedium?.copyWith(color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.hair)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.hair)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.ink, width: 1.2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.ink,
        foregroundColor: c.paper,
        disabledBackgroundColor: c.hair,
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        backgroundColor: c.surface,
        side: BorderSide(color: c.hair),
        minimumSize: const Size.fromHeight(50),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.ink, textStyle: text.labelLarge),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.ink,
      side: BorderSide(color: c.hair),
      shape: const StadiumBorder(),
      labelStyle: text.labelMedium,
      secondaryLabelStyle: text.labelMedium?.copyWith(color: c.paper),
      checkmarkColor: c.paper,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.paper : c.surface),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.hair),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.paper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink),
    tabBarTheme: TabBarThemeData(
      labelColor: c.ink,
      unselectedLabelColor: c.muted,
      indicatorColor: c.ink,
      labelStyle: text.labelMedium,
      dividerColor: c.hair,
    ),
  );
}
