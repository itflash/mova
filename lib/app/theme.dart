import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

const _lightScaffold = Color(0xFFF2F2F7);
const _darkScaffold = Color(0xFF111317);

ThemeData buildLightTheme() {
  final theme = FlexThemeData.light(
    scheme: FlexScheme.aquaBlue,
    useMaterial3: true,
    scaffoldBackground: _lightScaffold,
    surfaceMode: FlexSurfaceMode.highBackgroundLowScaffold,
    blendLevel: 2,
    appBarStyle: FlexAppBarStyle.background,
    subThemesData: const FlexSubThemesData(
      cardRadius: 14,
      inputDecoratorRadius: 12,
      navigationBarIndicatorRadius: 12,
      navigationBarHeight: 64,
      thinBorderWidth: 0.7,
      blendOnLevel: 4,
      blendOnColors: false,
      segmentedButtonRadius: 10,
      segmentedButtonUnselectedForegroundSchemeColor: SchemeColor.onSurface,
    ),
  );

  final colorScheme = theme.colorScheme.copyWith(
    primary: const Color(0xFF0A84FF),
    primaryContainer: const Color(0xFFD9ECFF),
    secondary: const Color(0xFF5AC8FA),
    surface: const Color(0xFFFFFFFF),
    surfaceContainer: const Color(0xFFF7F7FA),
    surfaceContainerHigh: const Color(0xFFFFFFFF),
    surfaceContainerHighest: const Color(0xFFF3F4F7),
    outlineVariant: const Color(0xFFD8D8DE),
  );

  final textTheme =
      const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
        ),
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.9,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, height: 1.42),
        bodySmall: TextStyle(fontSize: 12, height: 1.35),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ).apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      );

  return theme.copyWith(
    colorScheme: colorScheme,
    textTheme: textTheme.copyWith(
      bodyMedium: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      bodySmall: textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.75),
      thickness: 0.7,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      floatingLabelStyle: TextStyle(color: colorScheme.primary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        fixedSize: const Size(40, 40),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.primaryContainer,
      disabledColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      checkmarkColor: colorScheme.primary,
      labelStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      side: BorderSide(color: colorScheme.outlineVariant),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surface,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
      indicatorColor: const Color(0xFFDCEBFF),
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(
          BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primaryContainer;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.onSurfaceVariant;
        }),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    ),
  );
}

ThemeData buildDarkTheme() {
  final theme = FlexThemeData.dark(
    scheme: FlexScheme.aquaBlue,
    useMaterial3: true,
    scaffoldBackground: _darkScaffold,
    surfaceMode: FlexSurfaceMode.level,
    blendLevel: 4,
    appBarStyle: FlexAppBarStyle.background,
    subThemesData: const FlexSubThemesData(
      cardRadius: 14,
      inputDecoratorRadius: 12,
      navigationBarIndicatorRadius: 12,
      navigationBarHeight: 64,
      thinBorderWidth: 0.7,
      blendOnLevel: 8,
      blendOnColors: false,
      segmentedButtonRadius: 10,
    ),
  );

  final colorScheme = theme.colorScheme.copyWith(
    primary: const Color(0xFF59A8FF),
    surface: const Color(0xEB191C20),
    surfaceContainer: const Color(0xFF1E2228),
    surfaceContainerHigh: const Color(0xFF232830),
    surfaceContainerHighest: const Color(0xFF2A3038),
    outlineVariant: const Color(0xFF3C434D),
  );

  return theme.copyWith(
    colorScheme: colorScheme,
    textTheme: buildLightTheme().textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.85),
      thickness: 0.7,
      space: 1,
    ),
    inputDecorationTheme: buildLightTheme().inputDecorationTheme.copyWith(
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.6),
          width: 1.4,
        ),
      ),
    ),
    navigationBarTheme: buildLightTheme().navigationBarTheme.copyWith(
      indicatorColor: const Color(0xFF2B3848),
    ),
  );
}
