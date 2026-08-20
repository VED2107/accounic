library;

import 'package:flutter/material.dart';

/// A stable colour per person (context.md §18), matching
/// `web/src/lib/avatar-color.ts` hue for hue and hash for hash.
///
/// Avatars used to be tinted by the balance, which meant a directory of people
/// was a wall of red and green — the two colours that are supposed to mean money
/// and nothing else. Tinting by identity instead gives each account a face you
/// recognise before you read the name, and hands red and green back to the
/// figures where they carry meaning.
///
/// The palette deliberately avoids the receivable green and the payable red: it
/// sits in the blues, cyans, violets and warm neutrals, so no avatar can be
/// mistaken for a balance state.
class AvatarColor {
  const AvatarColor._();

  /// Hue and saturation pairs, in the same order as the web client's, so the
  /// same person is the same colour on both.
  static const _hues = <({double h, double s})>[
    (h: 217, s: 0.85), // brand blue
    (h: 199, s: 0.88), // sky
    (h: 188, s: 0.82), // cyan
    (h: 258, s: 0.74), // violet
    (h: 280, s: 0.62), // plum
    (h: 32, s: 0.88), //  amber
    (h: 14, s: 0.72), //  clay
    (h: 172, s: 0.62), // muted teal
    (h: 228, s: 0.60), // indigo
    (h: 205, s: 0.30), // slate
  ];

  /// FNV-1a, 32 bit. Stable across runs and identical to the web client's.
  static int _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Background, ink and border for one name, resolved for the current scheme.
  static ({Color background, Color foreground, Color border}) of(
    String name,
    Brightness brightness,
  ) {
    final pick = _hues[_hash(name.trim().toLowerCase()) % _hues.length];
    final dark = brightness == Brightness.dark;

    final base = HSLColor.fromAHSL(1, pick.h, pick.s, 0.55).toColor();
    return (
      background: base.withValues(alpha: dark ? 0.16 : 0.12),
      // Light ink on a dark ground, deep ink on a light one — either way it
      // clears contrast against the wash behind it.
      foreground: HSLColor.fromAHSL(1, pick.h, pick.s, dark ? 0.68 : 0.38).toColor(),
      border: base.withValues(alpha: dark ? 0.34 : 0.26),
    );
  }
}
