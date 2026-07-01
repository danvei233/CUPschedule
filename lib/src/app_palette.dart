import 'package:flutter/material.dart';

BlackbookPalette blackbookPalette(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? BlackbookPalette.dark
      : BlackbookPalette.light;
}

class BlackbookPalette {
  const BlackbookPalette({
    required this.pageBackground,
    required this.surface,
    required this.surfaceAlt,
    required this.sheet,
    required this.ink,
    required this.subtle,
    required this.muted,
    required this.divider,
    required this.weakDivider,
    required this.primary,
    required this.primarySoft,
    required this.onPrimary,
    required this.danger,
    required this.success,
    required this.warning,
    required this.handle,
    required this.dockBackground,
    required this.dockBorder,
    required this.dockText,
    required this.dockMuted,
    required this.courseBorder,
    required this.courseShadow,
  });

  final Color pageBackground;
  final Color surface;
  final Color surfaceAlt;
  final Color sheet;
  final Color ink;
  final Color subtle;
  final Color muted;
  final Color divider;
  final Color weakDivider;
  final Color primary;
  final Color primarySoft;
  final Color onPrimary;
  final Color danger;
  final Color success;
  final Color warning;
  final Color handle;
  final Color dockBackground;
  final Color dockBorder;
  final Color dockText;
  final Color dockMuted;
  final Color courseBorder;
  final Color courseShadow;

  static const light = BlackbookPalette(
    pageBackground: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6F8FC),
    sheet: Color(0xFFFFFFFF),
    ink: Color(0xFF101525),
    subtle: Color(0xFF687083),
    muted: Color(0xFF9AA2B4),
    divider: Color(0xFFE9EDF6),
    weakDivider: Color(0x52E9EDF6),
    primary: Color(0xFFB51E23),
    primarySoft: Color(0xFFFFE9EA),
    onPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFCF3D3D),
    success: Color(0xFF25A985),
    warning: Color(0xFFE4863E),
    handle: Color(0xFFD2D6DE),
    dockBackground: Color(0xF7FFFFFF),
    dockBorder: Color(0xFFE9EDF6),
    dockText: Color(0xFF101525),
    dockMuted: Color(0xFF81889A),
    courseBorder: Color(0xD1FFFFFF),
    courseShadow: Color(0x0A101525),
  );

  static const dark = BlackbookPalette(
    pageBackground: Color(0xFF0B0C10),
    surface: Color(0xFF11131A),
    surfaceAlt: Color(0xFF181B24),
    sheet: Color(0xFF101116),
    ink: Color(0xFFF2F4FA),
    subtle: Color(0xFFB4BBCB),
    muted: Color(0xFF727A8D),
    divider: Color(0xFF222631),
    weakDivider: Color(0x12FFFFFF),
    primary: Color(0xFFFF7A7D),
    primarySoft: Color(0xFF3B1B20),
    onPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFFF8F88),
    success: Color(0xFF35C6A5),
    warning: Color(0xFFFFB75B),
    handle: Color(0xFF585F70),
    dockBackground: Color(0xF2111219),
    dockBorder: Color(0x00000000),
    dockText: Color(0xFFD7DDFF),
    dockMuted: Color(0xFF858B9D),
    courseBorder: Color(0x2EFFFFFF),
    courseShadow: Color(0x66000000),
  );
}
