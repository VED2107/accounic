import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/activity_report.dart';
import '../core/dates.dart';
import 'export_models.dart';
import 'statement_pdf.dart';

/// The Activity feed, as a PDF.
///
/// The document a person expects when they press Export on the Activity
/// screen: the same page, typeset. A day heading with its entry count, a rule
/// under it, then the entries of that day — account, what kind of entry, the
/// amount as it was entered — then the next day.
///
/// It is deliberately a different document from `export_pdf.dart`, which groups
/// the same rows by account and opens with the workspace position. That one
/// answers "where does each account stand?"; this one answers "what happened,
/// and when?", and a reader should be able to lay it beside the screen and find
/// the same rows in the same order.
///
/// The same rule as every other writer here: **it computes no money.** Every
/// string below came out of `core/activity_report.dart`.
///
/// Mirrors `web/src/lib/pdf/activity.ts` — same sections, same order, same
/// words, laid out with the `pdf` package's flow layout rather than by hand.
class ActivityExportPdf {
  const ActivityExportPdf._();

  static const _pageFormat = PdfPageFormat.a4;

  static const _ink = PdfColor.fromInt(0xFF14161A);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _faint = PdfColor.fromInt(0xFF94A0AD);
  static const _line = PdfColor.fromInt(0xFFE3E6EA);
  static const _hairline = PdfColor.fromInt(0xFFF1F3F5);
  static const _brand = PdfColor.fromInt(0xFF2563EB);
  static const _receivable = PdfColor.fromInt(0xFF11804A);
  static const _payable = PdfColor.fromInt(0xFFB4232B);

  static Future<Uint8List> build(
    ExportBundle bundle, {
    required ActivityView view,
    required String scopeLabel,
    DateTime? generatedAt,
  }) async {
    // The typeface first: the formatter asks it whether a currency symbol can
    // be drawn, and resolving the rows before it is loaded would silently
    // answer "no" for every figure in the file.
    final theme = await PersonStatement.pdfTheme();
    final report = buildActivityReport(bundle, view: view, scopeLabel: scopeLabel);
    final now = generatedAt ?? DateTime.now();

    final doc = pw.Document(
      title: '${report.workspaceName} — activity report',
      author: report.ownerName ?? report.workspaceName,
      theme: theme,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : _runningHeader(report),
        footer: (context) => _footer(context, now),
        build: (context) => [
          _cover(report, now),
          if (report.truncated) _truncationNotice(),
          pw.SizedBox(height: 14),
          if (report.days.isEmpty)
            pw.Text(
              'No entries in this view.',
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            )
          else
            for (final day in report.days) _day(day),
        ],
      ),
    );

    return doc.save();
  }

  /* ---------------------------------------------------------------------- */

  static pw.Widget _cover(ActivityReport report, DateTime now) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        report.workspaceName,
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink),
      ),
      pw.SizedBox(height: 2),
      pw.Text(report.title, style: const pw.TextStyle(fontSize: 12, color: _brand)),
      pw.SizedBox(height: 12),
      pw.Container(height: 1, color: _line),
      pw.SizedBox(height: 12),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _fact('Showing', report.scope),
                _fact('Category', report.category),
                _fact('Base currency', report.baseCurrency),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _fact('Generated', statementDate(isoDate(now))),
                _fact('Entries', '${report.entryCount}'),
                _fact('Days', '${report.dayCount}'),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  static pw.Widget _fact(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _muted)),
        pw.SizedBox(height: 1),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10, color: _ink)),
      ],
    ),
  );

  static pw.Widget _truncationNotice() => pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _payable, width: 0.5),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      'This export reached its size limit. Older entries are not included.',
      style: const pw.TextStyle(fontSize: 8.5, color: _payable),
    ),
  );

  /// One day: its heading, its count, and its entries.
  ///
  /// Wrapped so the heading cannot be orphaned at the foot of a page with its
  /// first entry stranded overleaf.
  static pw.Widget _day(ActivityReportDay day) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          // One label, the screen's own. Printing "28 AUGUST" beside
          // "28 August 2026" said the same thing twice; the year is on the
          // cover.
          pw.Text(
            day.label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
              letterSpacing: 0.4,
            ),
          ),
          pw.Text(
            '${day.count} ${day.count == 1 ? 'entry' : 'entries'}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Container(height: 0.5, color: _line),
      for (final row in day.rows) _row(row),
      pw.SizedBox(height: 6),
    ],
  );

  /// One entry, as two columns of stacked lines.
  ///
  /// The left column carries the account and what happened; the right carries
  /// the money. Each is its own `Column`, so the converted amount and the
  /// settlement status can never land on the same line and overlap — the defect
  /// the hand-laid web version had to be rebuilt to avoid.
  static pw.Widget _row(ActivityReportRow row) {
    final tone = row.isSettlement
        ? _faint
        : row.receivable
        ? _receivable
        : _payable;

    final detail = [row.type, row.description].where((s) => s.isNotEmpty).join(' · ');
    final meta = [row.rate, row.rateNote].whereType<String>().join(' · ');

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _hairline, width: 0.5)),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // The tint the screen puts behind the glyph, here as a 2pt spine.
          pw.Container(width: 2, height: 26, color: tone),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  row.person,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    detail,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    meta,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: const pw.TextStyle(fontSize: 7.5, color: _faint),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.ConstrainedBox(
            constraints: const pw.BoxConstraints(maxWidth: 150),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  row.amount,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: row.isSettlement ? _ink : tone,
                  ),
                ),
                if (row.equivalent != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    row.equivalent!,
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                ],
                if (row.settlement != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    row.settlement!,
                    style: const pw.TextStyle(fontSize: 8, color: _faint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _runningHeader(ActivityReport report) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(report.workspaceName, style: const pw.TextStyle(fontSize: 8, color: _muted)),
        pw.Text(
          'Activity report · ${report.category}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );

  static pw.Widget _footer(pw.Context context, DateTime now) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Generated by Accounic · ${statementDate(isoDate(now))}',
          style: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
      ],
    ),
  );
}
