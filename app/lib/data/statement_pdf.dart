library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/currencies.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../core/statement.dart';
import 'models.dart';

/// The account statement, as a PDF.
///
/// ONE RULE GOVERNS THIS FILE: **it computes no money.** Every figure it prints
/// is a string `core/statement.dart` produced from a number the database
/// returned. There is no arithmetic here, no second definition of what a credit
/// is, and no second idea of which figure belongs in which section — the row
/// rules live in `core/statement.dart` and are unit-tested without a PDF reader.
///
/// The structure mirrors the person screen exactly, and for the same reason:
///
///     Cash in hand           the regular position, and the rows behind it
///     Opening balance        its own block and its own activity, never a row
///                            in the table below
///
/// Layout is hand-set. The `pdf` package flows widgets, but column positions
/// and the table's shape are decided here and nowhere else.
class PersonStatement {
  const PersonStatement._();

  static const _pageFormat = PdfPageFormat.a4;

  /// Builds the statement for [page]. [ownerName] is whose ledger it is.
  static Future<Uint8List> build({
    required PersonPage page,
    required String ownerName,
    DateTime? generatedAt,
  }) async {
    // The typeface FIRST, because `_format` below asks it whether a currency
    // symbol can be drawn. Resolving the rows before the font is loaded would
    // silently answer "no" and print every figure without its symbol.
    final theme = await _theme();

    final now = generatedAt ?? DateTime.now();
    final currency = page.currency;
    final base = page.baseCurrency;
    final regular = page.regular;
    final opening = page.openingPosition;

    final rows = buildStatementRows(
      page.timeline,
      closingMinor: regular.positionMinor,
      currency: currency,
      baseCurrency: base,
      format: _format,
    );
    final openingRows = buildStatementRows(
      page.openingActivity,
      closingMinor: opening.positionMinor,
      currency: currency,
      baseCurrency: base,
      format: _format,
    );

    final doc = pw.Document(
      title: '${page.person.name} — statement',
      author: ownerName,
      theme: theme,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
        header: (context) =>
            context.pageNumber == 1 ? pw.SizedBox() : _runningHeader(page.person.name),
        footer: (context) => _footer(context, now),
        build: (context) => [
          _title(page, ownerName, now),
          pw.SizedBox(height: 18),
          _positions(page, regular, opening, currency),
          pw.SizedBox(height: 18),
          ..._openingSection(page, opening, openingRows, currency, base),
          pw.SizedBox(height: 18),
          _sectionHeading('Regular transactions'),
          pw.SizedBox(height: 2),
          pw.Text(
            'Credits, debits, transfers and their settlements. Nothing from the '
            'opening balance appears here.',
            style: _muted(8.5),
          ),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text('No regular transactions recorded.', style: _muted(9))
          else
            _rowsTable(rows, currency),
          if (page.timelineTotal > rows.length) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Showing the most recent ${rows.length} of ${page.timelineTotal} entries.',
              style: _muted(8),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /* ---------------------------------------------------------------------- */

  /// The typeface, and why it is not optional.
  ///
  /// The `pdf` package defaults to the PDF standard-14 fonts, whose encoding
  /// has no glyph for `₹` — every rupee figure printed as a tofu box, which is
  /// not a cosmetic problem on a financial document: the reader cannot tell
  /// what currency the number is in. Poppins is already bundled for the app's
  /// own headings and covers `₹`, so the statement embeds it.
  ///
  /// Loaded once and cached: a multi-page statement asks for the theme twice,
  /// and parsing a megabyte of TTF for each is wasted work.
  ///
  /// The web statement solves the same problem the same way — see
  /// `web/src/lib/pdf/typeface.ts`, which embeds these exact files.
  static pw.ThemeData? _cachedTheme;

  static Future<pw.ThemeData> _theme() async {
    final cached = _cachedTheme;
    if (cached != null) return cached;

    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-Medium.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'));
      return _cachedTheme = pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      );
    } catch (_) {
      // The asset is missing from this build. Fall back to the built-in face
      // rather than refusing to produce a statement at all — the figures are
      // still right, and `_money` below drops the symbols it cannot draw.
      return _cachedTheme = pw.ThemeData.base();
    }
  }

  /// True once the embedded face is in use, so symbols are safe to print.
  static bool get _hasGlyphs => _cachedTheme?.defaultTextStyle.font != null;

  /// An amount, with its symbol only when the face can actually draw one.
  ///
  /// Not a second money formatter: `formatMoney` does all of it. The single
  /// thing added is the fallback the web statement also carries — `6,000.00
  /// INR` rather than a tofu box followed by `6,000.00 INR`. Nothing about the
  /// amount changes; only whether a symbol precedes it.
  static String _money(int minor, String currency, {bool compactDecimals = true}) {
    if (_hasGlyphs) {
      return formatMoney(minor, currency: currency, compactDecimals: compactDecimals);
    }
    return formatMinor(
      minor,
      currency: currency,
      compactDecimals: compactDecimals,
      withSymbol: false,
      withCode: true,
    );
  }

  /// The statement's own money formatter, handed to the pure row rules in
  /// `core/statement.dart` so that they stay testable without a PDF and this
  /// file stays the only place that knows anything about glyphs.
  static final StatementFormatter _format = StatementFormatter(
    money: (minor, {currency, compactDecimals = true}) =>
        _money(minor, currency ?? kFallbackCurrency, compactDecimals: compactDecimals),
    approx: (minor, {currency}) => _hasGlyphs
        ? formatApprox(minor, currency: currency)
        : '≈ ${formatMinor(minor, currency: currency ?? kFallbackCurrency, compactDecimals: false, withSymbol: false, withCode: true)}',
  );

  static pw.TextStyle _muted(double size) =>
      pw.TextStyle(fontSize: size, color: PdfColors.grey700);

  static pw.TextStyle _label() => pw.TextStyle(
        fontSize: 7.5,
        letterSpacing: 0.7,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey600,
      );

  static PdfColor _tone(bool receivable, bool settled) => settled
      ? PdfColors.grey700
      : receivable
          ? PdfColors.green800
          : PdfColors.red800;

  static pw.Widget _sectionHeading(String text) => pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: pw.FontWeight.bold,
        ),
      );

  static pw.Widget _runningHeader(String name) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        margin: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text('$name — account statement', style: _muted(8)),
      );

  static pw.Widget _footer(pw.Context context, DateTime now) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'Accounic · generated ${statementDate(isoDate(now))} at '
          '${timeOfDay(now.toIso8601String())} · page ${context.pageNumber} of ${context.pagesCount}',
          style: _muted(7.5),
        ),
      );

  static pw.Widget _title(PersonPage page, String ownerName, DateTime now) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ACCOUNT STATEMENT', style: _label()),
                pw.SizedBox(height: 3),
                pw.Text(
                  page.person.name,
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  [
                    page.person.type.label,
                    currencyLabel(page.currency),
                    if (page.person.phone != null) page.person.phone!,
                  ].join('  ·  '),
                  style: _muted(9),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('GENERATED', style: _label()),
                pw.SizedBox(height: 3),
                pw.Text(statementDate(isoDate(now)), style: const pw.TextStyle(fontSize: 10)),
                pw.Text(timeOfDay(now.toIso8601String()), style: _muted(9)),
                pw.SizedBox(height: 4),
                if (ownerName.isNotEmpty) pw.Text(ownerName, style: _muted(9)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(height: 1, color: PdfColors.grey400),
      ],
    );
  }

  /// The two positions, printed side by side and never added into one figure.
  static pw.Widget _positions(
    PersonPage page,
    PositionSplit regular,
    PositionSplit opening,
    String currency,
  ) {
    pw.Widget block(String label, int minor, String caption, {bool quiet = false}) =>
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: _label()),
              pw.SizedBox(height: 3),
              pw.Text(
                _money(minor.abs(), currency),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: quiet ? PdfColors.grey800 : _tone(minor >= 0, minor == 0),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(caption, style: _muted(8)),
            ],
          ),
        );

    final first = page.person.name.split(' ').first;

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          block(
            'CASH IN HAND',
            regular.positionMinor,
            regular.positionMinor == 0
                ? 'Regular activity is settled'
                : regular.positionMinor > 0
                    ? '$first owes you, on regular activity'
                    : 'You owe $first, on regular activity',
          ),
          block(
            'OPENING BALANCE',
            opening.positionMinor,
            opening.positionMinor == 0
                ? page.balance.hasOpening
                    ? 'Settled in full'
                    : 'This account started at zero'
                : opening.positionMinor > 0
                    ? 'Owed to you when the account opened'
                    : 'Owed by you when the account opened',
          ),
          block(
            'ACCOUNT POSITION',
            page.balance.netBalance,
            'Cash in hand and the opening balance together',
            quiet: true,
          ),
        ],
      ),
    );
  }

  /// The opening balance: its own block, its own activity, and never a row in
  /// the regular table.
  static List<pw.Widget> _openingSection(
    PersonPage page,
    PositionSplit position,
    List<StatementRow> rows,
    String currency,
    String base,
  ) {
    final opening = page.opening;
    if (opening == null && rows.isEmpty && page.openingHistory.isEmpty) {
      return [
        _sectionHeading('Opening balance'),
        pw.SizedBox(height: 4),
        pw.Text('This account has no opening balance. It started at zero.', style: _muted(9)),
      ];
    }

    final lines = opening == null
        ? null
        : openingLines(opening, position, currency, base, format: _format);

    return [
      _sectionHeading('Opening balance'),
      pw.SizedBox(height: 6),
      if (lines != null)
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        lines.original,
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                      if (lines.equivalent != null)
                        pw.Text(lines.equivalent!, style: _muted(8.5)),
                      pw.SizedBox(height: 2),
                      pw.Text(lines.direction, style: _muted(8.5)),
                      if (lines.rate != null) pw.Text(lines.rate!, style: _muted(8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Dated ${lines.dated}', style: _muted(8.5)),
                      pw.Text('Recorded ${lines.recorded}', style: _muted(8)),
                      if (lines.settlement != null)
                        pw.Text(lines.settlement!, style: _muted(8.5)),
                      pw.SizedBox(height: 2),
                      pw.Text('Outstanding ${lines.outstanding}', style: _muted(8.5)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      if (rows.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        pw.Text('OPENING BALANCE ACTIVITY', style: _label()),
        pw.SizedBox(height: 4),
        _rowsTable(rows, currency),
      ],
      if (page.openingHistory.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        pw.Text('REPLACED', style: _label()),
        pw.SizedBox(height: 3),
        for (final row in page.openingHistory)
          pw.Text(
            '${_money(row.entryAmountMinor, row.entryCurrency)}'
            '  ·  retracted  ·  dated ${statementDate(row.entryDate)}',
            style: _muted(8.5),
          ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Replacing an opening balance retracts the previous one rather than '
          'editing it. These affect no balance.',
          style: _muted(8),
        ),
      ],
    ];
  }

  static pw.Widget _rowsTable(List<StatementRow> rows, String currency) {
    pw.Widget head(String text, {pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
          child: pw.Text(text.toUpperCase(), style: _label()),
        );

    pw.Widget cell(
      String text, {
      pw.Alignment align = pw.Alignment.centerLeft,
      double size = 8.5,
      PdfColor? color,
      bool strike = false,
      bool bold = false,
    }) =>
        pw.Container(
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: size,
              color: color ?? PdfColors.black,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              decoration:
                  strike ? pw.TextDecoration.lineThrough : pw.TextDecoration.none,
            ),
          ),
        );

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.5), // date + time
        1: pw.FlexColumnWidth(1.5), // type
        2: pw.FlexColumnWidth(2.0), // description
        3: pw.FlexColumnWidth(1.8), // original + equivalent
        4: pw.FlexColumnWidth(1.4), // balance
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            head('Date'),
            head('Type'),
            head('Details'),
            head('Amount', align: pw.Alignment.centerRight),
            head('Balance', align: pw.Alignment.centerRight),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(row.date, style: const pw.TextStyle(fontSize: 8.5)),
                    if (row.time.isNotEmpty) pw.Text(row.time, style: _muted(7.5)),
                  ],
                ),
              ),
              cell(
                row.isVoid ? '${row.type} (retracted)' : row.type,
                color: row.isVoid ? PdfColors.grey600 : null,
                strike: row.isVoid,
              ),
              cell(row.description, size: 8, color: PdfColors.grey800),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      row.original,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        decoration: row.isVoid
                            ? pw.TextDecoration.lineThrough
                            : pw.TextDecoration.none,
                      ),
                    ),
                    if (row.equivalent != null)
                      pw.Text(row.equivalent!, style: _muted(7.5)),
                    if (row.rate != null) pw.Text(row.rate!, style: _muted(7)),
                  ],
                ),
              ),
              cell(
                row.balance,
                align: pw.Alignment.centerRight,
                color: _tone(row.balanceReceivable, false),
                bold: true,
              ),
            ],
          ),
      ],
    );
  }
}
