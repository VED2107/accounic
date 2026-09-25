library;


import 'package:flutter/material.dart';

/// The Accounic visual language: COUNTERFOIL & SEAL, printed INK ONLY (v1.16).
///
/// Every account is an instrument of value, drawn from the counter where
/// instruments are issued and stamped: neutral carbon after dark, neutral paper
/// by day — zero chroma, so nothing reads gold or blue. There is no accent hue. Actions are solid
/// plates of the same ink the text is printed in, inverting with the scheme;
/// the only colour on screen is money — green for what you are owed, red for
/// what you owe — and the stamps struck in those inks. The brand's ramp lives
/// in the logo mark alone. Material 3 is the mechanism.
///
/// Both schemes are first-class and follow the system — a counter in daylight
/// and a desk at night are both real scenes for this product. The web client
/// keeps its own look; parity between the two is behavioural (PRODUCT.md).

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
    required this.inkSubtle,
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

  /// Secondary text. Both of these clear 4.5:1 on the page ground. `inkFaint`
  /// used to be #6A7382, which measures 4.03:1 on the dark surface and is under
  /// the line for the 11-12px metadata it mostly carries — a contrast that
  /// looks restrained on a desk monitor and vanishes on a phone outdoors.
  final Color inkMuted;
  final Color inkFaint;

  /// Purely decorative text that carries no information on its own: a separator
  /// dot, a unit suffix. Not for anything the user has to read.
  final Color inkSubtle;

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
  ///
  /// Counterfoil & Seal: solid intaglio blue with only a one-step darkening at
  /// the foot — an engraved plate, not a glossy button.
  static const actionGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF161616), Color(0xFF161616)],
  );

  /// Legacy: the light scheme's text-on-plate. Widgets use
  /// [AccounicTheme.onAction], which inverts with the scheme.
  static const onAction = Color(0xFFF7F7F5);

  /// The gradient's deep end, which is also the colour every hover glow under a
  /// primary action is tinted with. It was written out as a literal in four
  /// separate widgets — the sheet footer, the person screen, the shell's add
  /// button and the settings save button — which is exactly how a palette stops
  /// being a palette.
  static const actionGlow = Color(0xFF000000);

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
    Color? inkSubtle,
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
        inkSubtle: inkSubtle ?? this.inkSubtle,
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
      inkSubtle: Color.lerp(inkSubtle, other.inkSubtle, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      sunken: Color.lerp(sunken, other.sunken, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
    );
  }

  static const light = AccounicColors(
    receivable: Color(0xFF1B6A45),
    receivableSoft: Color(0x171B6A45),
    receivableLine: Color(0x471B6A45),
    receivableInk: Color(0xFFFFFFFF),
    payable: Color(0xFFB0301C),
    payableSoft: Color(0x14B0301C),
    payableLine: Color(0x47B0301C),
    payableInk: Color(0xFFFFFFFF),
    accentSoft: Color(0x12161616),
    accentLine: Color(0x3D161616),
    inkMuted: Color(0xFF3E3E3C),
    inkFaint: Color(0xFF565654),
    inkSubtle: Color(0xFF84847F),
    line: Color(0xFFD7D7D3),
    lineStrong: Color(0xFFBEBEBA),
    sunken: Color(0xFFE3E3E0),
    raised: Color(0xFFFFFFFF),
  );

  static const dark = AccounicColors(
    receivable: Color(0xFF6CD3A0),
    receivableSoft: Color(0x1F6CD3A0),
    receivableLine: Color(0x4D6CD3A0),
    receivableInk: Color(0xFF03150D),
    payable: Color(0xFFF2795E),
    payableSoft: Color(0x1FF2795E),
    payableLine: Color(0x4DF2795E),
    payableInk: Color(0xFF2A0905),
    accentSoft: Color(0x17F2F2F0),
    accentLine: Color(0x42F2F2F0),
    inkMuted: Color(0xFFC6C6C3),
    inkFaint: Color(0xFFA2A29F),
    inkSubtle: Color(0xFF70706D),
    line: Color(0xFF262626),
    lineStrong: Color(0xFF383837),
    sunken: Color(0xFF0B0B0B),
    raised: Color(0xFF202020),
  );
}

extension AccounicTheme on BuildContext {
  AccounicColors get money => Theme.of(this).extension<AccounicColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  /// The action plate: solid ink, inverting with the scheme — carbon on kraft
  /// by day, paper-white on carbon by night.
  Color get actionFill => colors.primary;

  /// What is printed on [actionFill].
  Color get onAction => colors.onPrimary;

  /// Poppins, for the brand and for headings.
  TextStyle display(double size, {FontWeight weight = FontWeight.w600, Color? color}) => TextStyle(
        fontFamily: 'Poppins',
        fontSize: size,
        fontWeight: weight,
        letterSpacing: size > 24 ? -0.9 : -0.4,
        height: 1.1,
        color: color ?? colors.onSurface,
      );

  /// A financial figure. Not body text: a balance is the thing the reader came
  /// for, so it is tighter, heavier and always tabular — a column of amounts
  /// that does not align is a column that has to be read twice.
  ///
  /// Four sizes and nothing between them, so a figure is never styled ad hoc:
  ///
  ///   [MoneySize.hero]  the one number a screen is about (net position)
  ///   [MoneySize.large] a card's headline figure
  ///   [MoneySize.row]   a list row's figure
  ///   [MoneySize.small] a secondary figure (the approximate conversion)
  TextStyle moneyStyle(MoneySize size, {Color? color}) {
    final spec = switch (size) {
      MoneySize.hero => (34.0, FontWeight.w600, -1.1, 1.05),
      MoneySize.large => (24.0, FontWeight.w600, -0.7, 1.1),
      MoneySize.row => (15.0, FontWeight.w600, -0.25, 1.2),
      MoneySize.small => (12.5, FontWeight.w500, -0.1, 1.25),
    };
    return TextStyle(
      fontFamily: 'Poppins',
      fontSize: spec.$1,
      fontWeight: spec.$2,
      letterSpacing: spec.$3,
      height: spec.$4,
      color: color ?? colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// The small upper-case label above a figure. It says what the number is
  /// without competing with it for the eye.
  TextStyle get statLabel => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        height: 1.2,
        color: money.inkFaint,
      );

  /// The one line under a figure that qualifies it. Deliberately a step above
  /// the old faint grey: it is information, not decoration.
  TextStyle get statNote => TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: money.inkMuted,
      );
}

/// The four sizes a financial figure is allowed to be. See [AccounicTheme.money].
enum MoneySize { hero, large, row, small }

class AppTheme {
  const AppTheme._();

  /// Corner radii, matching the web's --radius-* scale.
  static const radiusField = 8.0;
  static const radiusCard = 12.0;
  static const radiusPanel = 16.0;

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          // INK ONLY: interactive things are printed in the same ink as
          // everything else; colour is reserved for money and stamps.
          primary: Color(0xFF161616),
          onPrimary: Color(0xFFF7F7F5),
          primaryContainer: Color(0xFFE3E3E0),
          onPrimaryContainer: Color(0xFF161616),
          surface: Color(0xFFF7F7F5),
          onSurface: Color(0xFF161616),
          surfaceContainerLowest: Color(0xFFECECEA),
          surfaceContainerHighest: Color(0xFFE3E3E0),
          outline: Color(0xFFBEBEBA),
          outlineVariant: Color(0xFFD7D7D3),
          error: Color(0xFFB0301C),
        ),
        money: AccounicColors.light,
        // Paper: neutral, so the only colour on it is money.
        scaffold: const Color(0xFFECECEA),
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: Color(0xFFF2F2F0),
          onPrimary: Color(0xFF111111),
          primaryContainer: Color(0xFF262626),
          onPrimaryContainer: Color(0xFFF2F2F0),
          surface: Color(0xFF181818),
          onSurface: Color(0xFFF2F2F0),
          surfaceContainerLowest: Color(0xFF111111),
          surfaceContainerHighest: Color(0xFF0B0B0B),
          outline: Color(0xFF383837),
          outlineVariant: Color(0xFF262626),
          error: Color(0xFFF2795E),
        ),
        money: AccounicColors.dark,
        // Carbon: neutral black, the ink engraved into it.
        scaffold: const Color(0xFF111111),
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
      // A sparkle ripple is a toy on a financial instrument. Presses answer
      // with an immediate tint (and a scale where the widget owns one).
      splashFactory: InkRipple.splashFactory,
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
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
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
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusField),
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
