import 'package:flutter/material.dart';

/// Centralized spacing and layout tokens for consistent rhythm across the app.
class AppSpacing {
  AppSpacing._();

  /// Horizontal page padding (left/right margins for scrollable content).
  static const double pagePaddingH = 20;

  /// Top padding for page content below the header.
  static const double pageContentTop = 6;

  /// Bottom padding for scrollable content (clears the bottom dock).
  static const double pageContentBottom = 28;

  /// Vertical gap between the header and the first content block.
  static const double headerBottomGap = 10;

  /// Gap between major sections within a page.
  static const double sectionGap = 16;

  /// Gap between cards in a list.
  static const double cardGap = 12;

  /// Gap between tightly related items (e.g. icon + label).
  static const double itemGap = 8;

  /// Small gap for fine adjustments.
  static const double tightGap = 4;

  /// Standard horizontal padding for inline controls.
  static const double controlPaddingH = 14;

  /// Standard vertical padding for inline controls.
  static const double controlPaddingV = 10;

  /// Page padding as an EdgeInsets for scroll views.
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(
    pagePaddingH,
    pageContentTop,
    pagePaddingH,
    pageContentBottom,
  );
}

/// Centralized corner radius tokens.
class AppRadius {
  AppRadius._();

  /// Cards and panels.
  static const double card = 8;

  /// Modal sheets and large overlay surfaces.
  static const double sheet = 14;

  /// Buttons, inputs, and interactive surfaces.
  static const double control = 8;

  /// Pills, badges, and fully rounded elements.
  static const double pill = 999;
}
