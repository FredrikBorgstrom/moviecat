import 'package:flutter/material.dart';

/// The orange of the MovieCat logo and icon.
const brandOrange = Color(0xFFFD6F10);

/// A lighter tint of [brandOrange] for small accents on dark backgrounds.
const brandOrangeLight = Color(0xFFFF9A55);

/// Dark theme: logo orange as the accent on warm charcoal surfaces that share
/// the orange's hue (instead of Material's default olive-brown neutrals).
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandOrange,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  ).copyWith(
    primary: brandOrange,
    onPrimary: const Color(0xFF1C0A00),
    surface: const Color(0xFF15110F),
    surfaceContainerLowest: const Color(0xFF0F0C0A),
    surfaceContainerLow: const Color(0xFF1B1613),
    surfaceContainer: const Color(0xFF221B17),
    surfaceContainerHigh: const Color(0xFF2C241F),
    surfaceContainerHighest: const Color(0xFF372D27),
    onSurface: const Color(0xFFF3EAE4),
    onSurfaceVariant: const Color(0xFFD8C4B8),
    outline: const Color(0xFF9E8B80),
    outlineVariant: const Color(0xFF4F423A),
  );
  return ThemeData(colorScheme: scheme, useMaterial3: true);
}
