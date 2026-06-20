import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shadcn theme data tuned to match mova's existing indigo Material theme.
///
/// mova keeps [MaterialApp] as the root, so shadcn components read their
/// colors from a [ShadTheme] injected via [ShadTheme.merge]. These factories
/// align the shadcn color scheme with the indigo palette in [theme.dart].
ShadThemeData buildShadLightTheme() {
  const base = ShadVioletColorScheme.light();
  final colorScheme = base.copyWith(
    primary: const Color(0xFF5856F6),
    ring: const Color(0xFF5856F6),
    background: const Color(0xFFF2F2F7),
    card: const Color(0xFFFFFFFF),
    border: const Color(0xFFD8D8DE),
    input: const Color(0xFFD8D8DE),
  );
 return ShadThemeData(
   colorScheme: colorScheme,
   brightness: Brightness.light,
   disableSecondaryBorder: true,
   inputTheme: _movaInputTheme(
     fillColor: const Color(0xFFF3F4F7),
     borderColor: const Color(0xFFD8D8DE),
     focusColor: const Color(0xFF5856F6),
   ),
 );
}

ShadThemeData buildShadDarkTheme() {
  const base = ShadVioletColorScheme.dark();
  final colorScheme = base.copyWith(
    primary: const Color(0xFF7A78FF),
    ring: const Color(0xFF7A78FF),
    background: const Color(0xFF111317),
    card: const Color(0xEB191C20),
    border: const Color(0xFF3C434D),
    input: const Color(0xFF3C434D),
  );
 return ShadThemeData(
   colorScheme: colorScheme,
   brightness: Brightness.dark,
   disableSecondaryBorder: true,
   inputTheme: _movaInputTheme(
     fillColor: const Color(0xFF2A3038),
     borderColor: const Color(0xFF3C434D),
     focusColor: const Color(0xFF7A78FF),
   ),
 );
}

/// Picks the matching shadcn theme for the current platform brightness.
ShadThemeData shadThemeFor(Brightness brightness) {
  return brightness == Brightness.dark
      ? buildShadDarkTheme()
      : buildShadLightTheme();
}

/// Builds a [ShadInputTheme] that mirrors mova's Material input style:
/// filled grey background, 12px radius, thin outline border, primary-colored
/// border on focus, and no shadcn "ring" secondary border.
ShadInputTheme _movaInputTheme({
  required Color fillColor,
  required Color borderColor,
  required Color focusColor,
}) {
  return ShadInputTheme(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: ShadDecoration(
      color: fillColor,
      border: ShadBorder.all(
        width: 1,
        color: borderColor,
        radius: const BorderRadius.all(Radius.circular(12)),
      ),
      focusedBorder: ShadBorder.all(
        width: 1.5,
        color: focusColor,
        radius: const BorderRadius.all(Radius.circular(12)),
      ),
      // Kill the shadcn outer focus ring; we style focus via the border.
      secondaryBorder: ShadBorder.none,
      secondaryFocusedBorder: ShadBorder.none,
    ),
  );
}
