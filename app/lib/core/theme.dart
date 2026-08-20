library;

import 'package:flutter/material.dart';

/// The Accounic visual language, shared with the web client (context.md §18).
///
/// The same tokens as `web/src/app/globals.css`, value for value: near-black
/// surfaces, clean white type, one brand blue for action, and money coloured
/// only by direction. Material 3 is the mechanism; the palette is ours. This is
/// not a stock Material app and it is not meant to look like accounting
/// software.
///
/// Dark is the product's face. The light scheme exists because a ledger gets
/// read in whatever light the reader is in, and it is tuned to the same rules
/// rather than mechanically inverted.

/// Everything Material's ColorScheme has no slot for.
@immutable
class AccounicColors extends ThemeExtension<AccounicColors> {
  const AccounicColors({
    required this.receivable,
    required this.receivableSoft,
    required this.receivableLine,
    required this.receivableInk,
    required this.payable,
    required this.payableSoft,
    required this.payableLine,
    required this.payableInk,
    required this.accentSoft,
    required this.accentLine,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.lineStrong,
    required this.sunken,
    required this.raised,
  });

  final Color receivable;
  final Color receivableSoft;
  final Color receivableLine;

  /// Text that sits *on* a filled receivable button.
  final Color receivableInk;

  final Color payable;
  final Color payableSoft;
  final Color payableLine;
  final Color payableInk;

  final Color accentSoft;
  final Color accentLine;

  final Color inkMuted;
  final Color inkFaint;
  final Color line;
  final Color lineStrong;
  final Color sunken;
  final Color raised;

  /// The logo's ramp. Used as an accent — a hairline, a mark, the primary
  /// action — and never as a field of colour behind content.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1D4ED8),
      Color(0xFF2563EB),
      Color(0xFF0EA5E9),
      Color(0xFF06B6D4),
      Color(0xFF14B8A6),
      Color(0xFF22C55E),
    ],
    stops: [0, 0.22, 0.46, 0.60, 0.80, 1],
  );

  /// The primary action's fill: a tonal gradient dark enough at both ends for
  /// white text to clear 4.5:1.
  static const actionGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2F6BEF), Color(0xFF1D4ED8)],
  );

  @override
  AccounicColors copyWith({
    Color? receivable,
    Color? receivableSoft,
    Color? receivableLine,
    Color? receivableInk,
    Color? payable,
    Color? payableSoft,
    Color? payableLine,
    Color? payableInk,
    Color? accentSoft,
    Color? accentLine,
    Color? inkMuted,
    Color? inkFaint,
    Color? line,
    Color? lineStrong,
    Color? sunken,
    Color? raised,
  }) =>
      AccounicColors(
        receivable: receivable ?? this.receivable,
        receivableSoft: receivableSoft ?? this.receivableSoft,
        receivableLine: receivableLine ?? this.receivableLine,
        receivableInk: receivableInk ?? this.receivableInk,
        payable: payable ?? this.payable,
        payableSoft: payableSoft ?? this.payableSoft,
        payableLine: payableLine ?? this.payableLine,
        payableInk: payableInk ?? this.payableInk,
        accentSoft: accentSoft ?? this.accentSoft,
        accentLine: accentLine ?? this.accentLine,
        inkMuted: inkMuted ?? this.inkMuted,
        inkFaint: inkFaint ?? this.inkFaint,
        line: line ?? this.line,
        lineStrong: lineStrong ?? this.lineStrong,
        sunken: sunken ?? this.sunken,
        raised: raised ?? this.raised,
      );

  @override
  AccounicColors lerp(ThemeExtension<AccounicColors>? other, double t) {
    if (other is! AccounicColors) return this;
    return AccounicColors(
      receivable: Color.lerp(receivable, other.receivable, t)!,
      receivableSoft: Color.lerp(receivableSoft, other.receivableSoft, t)!,
      receivableLine: Color.lerp(receivableLine, other.receivableLine, t)!,
      receivableInk: Color.lerp(receivableInk, other.receivableInk, t)!,
      payable: Color.lerp(payable, other.payable, t)!,
      payableSoft: Color.lerp(payableSoft, other.payableSoft, t)!,
      payableLine: Color.lerp(payableLine, other.payableLine, t)!,
      payableInk: Color.lerp(payableInk, other.payableInk, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentLine: Color.lerp(accentLine, other.accentLine, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      sunken: Color.lerp(sunken, other.sunken, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
    );
  }

  static const light = AccounicColors(
    receivable: Color(0xFF047857),
    receivableSoft: Color(0x14047857),
    receivableLine: Color(0x38047857),
    receivableInk: Color(0xFFFFFFFF),
    payable: Color(0xFFBE123C),
    payableSoft: Color(0x12BE123C),
    payableLine: Color(0x38BE123C),
    payableInk: Color(0xFFFFFFFF),
    accentSoft: Color(0x142563EB),
    accentLine: Color(0x3D2563EB),
    inkMuted: Color(0xFF596373),
    inkFaint: Color(0xFF8891A1),
    line: Color(0xFFE5E8EE),
    lineStrong: Color(0xFFD2D7E0),
    sunken: Color(0xFFF1F3F7),
    raised: Color(0xFFFFFFFF),
  );

  static const dark = AccounicColors(
    receivable: Color(0xFF34D399),
    receivableSoft: Color(0x2134D399),
    receivableLine: Color(0x4D34D399),
    receivableInk: Color(0xFF04140E),
    payable: Color(0xFFFB7185),
    payableSoft: Color(0x21FB7185),
    payableLine: Color(0x4DFB7185),
    payableInk: Color(0xFF2A0A10),
    accentSoft: Color(0x244D90F8),
    accentLine: Color(0x574D90F8),
    inkMuted: Color(0xFF98A2B3),
    inkFaint: Color(0xFF6A7382),
    line: Color(0xFF1D212A),
    lineStrong: Color(0xFF2B313D),
    sunken: Color(0xFF13161C),
    raised: Color(0xFF14171E),
  );
}

extension AccounicTheme on BuildContext {
  AccounicColors get money => Theme.of(this).extension<AccounicColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  /// Poppins, for the brand and for headings.
  TextStyle display(double size, {FontWeight weight = FontWeight.w600, Color? color}) => TextStyle(
        fontFamily: 'Poppins',
        fontSize: size,
        fontWeight: weight,
        letterSpacing: size > 24 ? -0.9 : -0.4,
        height: 1.1,
        color: color ?? colors.onSurface,
      );
}

class AppTheme {
  const AppTheme._();

  /// Corner radii, matching the web's --radius-* scale.
  static const radiusField = 10.0;
  static const radiusCard = 16.0;
  static const radiusPanel = 20.0;

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: Color(0xFF2563EB),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFE7EEFD),
          onPrimaryContainer: Color(0xFF1D4ED8),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0B0F17),
          surfaceContainerLowest: Color(0xFFF6F7F9),
          surfaceContainerHighest: Color(0xFFF1F3F7),
          outline: Color(0xFFD2D7E0),
          outlineVariant: Color(0xFFE5E8EE),
          error: Color(0xFFBE123C),
        ),
        money: AccounicColors.light,
        scaffold: const Color(0xFFF6F7F9),
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          // `primary` is the colour of text and icons that mean "interactive".
          // Filled controls use the darker action gradient instead, because
          // white on #4D90F8 does not clear contrast.
          primary: Color(0xFF4D90F8),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFF17223A),
          onPrimaryContainer: Color(0xFF4D90F8),
          surface: Color(0xFF0E1015),
          onSurface: Color(0xFFF2F5F9),
          surfaceContainerLowest: Color(0xFF08090C),
          surfaceContainerHighest: Color(0xFF13161C),
          outline: Color(0xFF2B313D),
          outlineVariant: Color(0xFF1D212A),
          error: Color(0xFFFB7185),
        ),
        money: AccounicColors.dark,
        scaffold: const Color(0xFF08090C),
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required AccounicColors money,
    required Color scaffold,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
    );

    // Tabular figures everywhere, so columns of money line up (context.md §18).
    const tnum = [FontFeature.tabularFigures()];

    return base.copyWith(
      extensions: [money],
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
          fontFeatures: tnum,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: money.line),
        ),
      ),
      dividerTheme: DividerThemeData(color: money.line, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: money.sunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: money.inkMuted, fontSize: 13.5),
        hintStyle: TextStyle(color: money.inkFaint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusField)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusField)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          foregroundColor: scheme.onSurface,
          backgroundColor: money.sunken,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          foregroundColor: scheme.primary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? scheme.primary : money.inkFaint,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: money.accentSoft,
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        unselectedLabelTextStyle: TextStyle(color: money.inkMuted, fontSize: 12.5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: money.raised,
        contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 13.5),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: money.lineStrong),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: money.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusPanel)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: money.raised,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.55),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusPanel)),
        ),
        showDragHandle: true,
        dragHandleColor: money.lineStrong,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: money.inkMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }
}
