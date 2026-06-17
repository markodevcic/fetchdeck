import 'package:flutter/material.dart';

class FetchdeckTheme {
  const FetchdeckTheme._();

  static FetchdeckThemeData of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? FetchdeckThemeData.dark()
        : FetchdeckThemeData.light();
  }
}

class FetchdeckThemeData {
  FetchdeckThemeData({required this.colorScheme, required this.textTheme});

  factory FetchdeckThemeData.dark() {
    const colors = FetchdeckColorScheme(
      background: Color(0xFF09090B),
      foreground: Color(0xFFFAFAFA),
      muted: Color(0xFF27272A),
      mutedForeground: Color(0xFFA1A1AA),
      border: Color(0xFF27272A),
      primary: Color(0xFFFAFAFA),
      secondary: Color(0xFF18181B),
      accent: Color(0xFF27272A),
      ring: Color(0xFFFAFAFA),
    );
    return FetchdeckThemeData(
      colorScheme: colors,
      textTheme: FetchdeckTextTheme.fromColors(colors),
    );
  }

  factory FetchdeckThemeData.light() {
    const colors = FetchdeckColorScheme(
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF09090B),
      muted: Color(0xFFF4F4F5),
      mutedForeground: Color(0xFF71717A),
      border: Color(0xFFE4E4E7),
      primary: Color(0xFF18181B),
      secondary: Color(0xFFF4F4F5),
      accent: Color(0xFFE4E4E7),
      ring: Color(0xFF18181B),
    );
    return FetchdeckThemeData(
      colorScheme: colors,
      textTheme: FetchdeckTextTheme.fromColors(colors),
    );
  }

  final FetchdeckColorScheme colorScheme;
  final FetchdeckTextTheme textTheme;
  final BorderRadius radius = BorderRadius.circular(8);
}

class FetchdeckColorScheme {
  const FetchdeckColorScheme({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.ring,
  });

  final Color background;
  final Color foreground;
  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color ring;
}

class FetchdeckTextTheme {
  FetchdeckTextTheme({
    required this.h4,
    required this.large,
    required this.p,
    required this.small,
    required this.muted,
  });

  factory FetchdeckTextTheme.fromColors(FetchdeckColorScheme colors) {
    final base = TextStyle(
      color: colors.foreground,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    return FetchdeckTextTheme(
      h4: base.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
      large: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      p: base,
      small: base.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      muted: base.copyWith(
        fontSize: 13,
        color: colors.mutedForeground,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  final TextStyle h4;
  final TextStyle large;
  final TextStyle p;
  final TextStyle small;
  final TextStyle muted;
}

ThemeData fetchdeckMaterialTheme(Brightness brightness) {
  final data = brightness == Brightness.dark
      ? FetchdeckThemeData.dark()
      : FetchdeckThemeData.light();
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: data.colorScheme.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: data.colorScheme.primary,
      brightness: brightness,
      surface: data.colorScheme.background,
    ),
    textTheme:
        (brightness == Brightness.dark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(
              bodyColor: data.colorScheme.foreground,
              displayColor: data.colorScheme.foreground,
            ),
  );
}
