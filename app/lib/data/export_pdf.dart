import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/dates.dart';
import '../core/export_report.dart';
import 'export_models.dart';
import 'statement_pdf.dart';

/// The workspace accounting export, as a PDF (Phase 4).
///
/// The same rule that governs `statement_pdf.dart` governs this file: **it
/// computes no money.** Every figure below is a string `export_report.dart`
/// produced from a number the database returned. There is no arithmetic here.
///
/// It is a different document from the account statement, and deliberately so:
///
///     Cover        who, when, what period, which filters, how many entries
///     Position     the workspace position PER CURRENCY, never summed across
///     Accounts     every person with their balances
///     Ledger       each person's entries, opening balances in their own block
///
/// The statement PDF is unchanged and still reached from a person's screen.
class WorkspaceExportPdf {
  const WorkspaceExportPdf._();

  static const _pageFormat = PdfPageFormat.a4;

  static const _ink = PdfColor.fromInt(0xFF14161A);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFE3E6EA);
  static const _band = PdfColor.fromInt(0xFFF6F7F9);
  static const _brand = PdfColor.fromInt(0xFF2563EB);
  static const _receivable = PdfColor.fromInt(0xFF11804A);
  static const _payable = PdfColor.fromInt(0xFFB4232B);

  static Future<Uint8List> build(ExportBundle bundle, {DateTime? generatedAt}) async {
    // The typeface first: the formatter asks it whether a currency symbol can
    // be drawn, and resolving the rows before it is loaded would silently
    // answer "no" for every figure in the file.
    final theme = await PersonStatement.pdfTheme();
    final report = buildWorkspaceReport(bundle, PersonStatement.pdfFormat);
    final now = generatedAt ?? DateTime.now();

    final doc = pw.Document(
      title: '${report.workspaceName} — accounting export',
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
            : _runningHeader(report.workspaceName),
        footer: (context) => _footer(context, now),
        build: (context) => [
          _cover(report, now),
          if (report.truncated) _truncationNotice(report),
          pw.SizedBox(height: 18),
          _positions(report),
          pw.SizedBox(height: 18),
          _accounts(report),
          ..._ledger(report),
        ],
      ),
    );

    return doc.save();
  }

  /* ---------------------------------------------------------------------- */

  static pw.Widget _cover(WorkspaceReport report, DateTime now) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        report.workspaceName,
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        report.title,
        style: const pw.TextStyle(fontSize: 12, color: _brand),
      ),
      pw.SizedBox(height: 12),
      pw.Container(height: 1, color: _line),
      pw.SizedBox(height: 12),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _facts(report)),
          pw.SizedBox(width: 16),
          pw.Expanded(child: _countFacts(report, now)),
        ],
      ),
    ],
  );

  static pw.Widget _facts(WorkspaceReport report) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _fact('Period', report.period),
      _fact('Contents', report.filters),
      _fact('Base currency', report.baseCurrency),
    ],
  );

  static pw.Widget _countFacts(WorkspaceReport report, DateTime now) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _fact('Generated', '${statementDate(isoDate(now))} · ${timeOfDay(now.toIso8601String())}'),
      _fact('Accounts', '${report.counts.people}'),
      _fact(
        'Entries',
        '${report.counts.entries} · ${report.counts.transactions} transactions, '
            '${report.counts.settlements} settlements',
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

  static pw.Widget _truncationNotice(WorkspaceReport report) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 12),
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: _band,
      border: pw.Border.all(color: _payable, width: 0.5),
    ),
    child: pw.Text(
      'This export reached its size limit and holds the first '
      '${report.counts.entries} entries. Narrow the period or export one '
      'account at a time for a complete file.',
      style: const pw.TextStyle(fontSize: 9, color: _payable),
    ),
  );

  /// The position, per currency. Never summed across currencies — the whole
  /// point of the per-currency breakdown is that such a sum means nothing.
  static pw.Widget _positions(WorkspaceReport report) {
    if (report.positions.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Position', 'As it stands today, in each currency'),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(1.4),
            4: pw.FlexColumnWidth(1.4),
            5: pw.FlexColumnWidth(1.4),
          },
          children: [
            _headerRow(const [
              'Currency',
              'They owe me',
              'I owe them',
              'Net',
              'Cash in hand',
              'Opening',
            ]),
            for (final position in report.positions)
              pw.TableRow(
                children: [
                  _cell(position.currency, bold: true),
                  _cell(position.receivable, color: _receivable, align: pw.TextAlign.right),
                  _cell(position.payable, color: _payable, align: pw.TextAlign.right),
                  _cell(
                    position.net,
                    color: position.netReceivable ? _receivable : _payable,
                    align: pw.TextAlign.right,
                    bold: true,
                  ),
                  _cell(position.cash ?? '—', align: pw.TextAlign.right),
                  _cell(position.opening ?? '—', align: pw.TextAlign.right),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _accounts(WorkspaceReport report) {
    if (report.people.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Accounts', 'Every person, in their own ledger currency'),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FlexColumnWidth(0.8),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.3),
            4: pw.FlexColumnWidth(1.3),
            5: pw.FlexColumnWidth(1.2),
          },
          children: [
            _headerRow(const [
              'Account',
              'Currency',
              'They owe me',
              'I owe them',
              'Net',
              'Opening',
            ]),
            for (final person in report.people)
              pw.TableRow(
                children: [
                  _cell(person.archived ? '${person.name} (archived)' : person.name),
                  _cell(person.currency),
                  _cell(person.receivable, color: _receivable, align: pw.TextAlign.right),
                  _cell(person.payable, color: _payable, align: pw.TextAlign.right),
                  _cell(
                    person.net,
                    color: person.netReceivable ? _receivable : _payable,
                    align: pw.TextAlign.right,
                    bold: true,
                  ),
                  _cell(person.opening ?? '—', align: pw.TextAlign.right),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static List<pw.Widget> _ledger(WorkspaceReport report) {
    final sections = report.sections.where((s) => !s.isEmpty).toList();
    if (sections.isEmpty) {
      return [
        pw.SizedBox(height: 18),
        _sectionTitle('Ledger', 'No entries fall inside this export'),
      ];
    }

    return [
      pw.SizedBox(height: 18),
      _sectionTitle('Ledger', 'Each account, opening balances kept apart'),
      for (final section in sections) ...[
        pw.SizedBox(height: 12),
        pw.Text(
          '${section.personName} · ${section.currency}',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink),
        ),
        if (section.openingRows.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text('Opening balance', style: const pw.TextStyle(fontSize: 8, color: _muted)),
          pw.SizedBox(height: 3),
          _rowsTable(section.openingRows),
        ],
        if (section.rows.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          if (section.openingRows.isNotEmpty)
            pw.Text('Transactions', style: const pw.TextStyle(fontSize: 8, color: _muted)),
          pw.SizedBox(height: 3),
          _rowsTable(section.rows),
        ],
      ],
    ];
  }

  static pw.Widget _rowsTable(List<ReportRow> rows) => pw.Table(
    border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.3),
      1: pw.FlexColumnWidth(1.5),
      2: pw.FlexColumnWidth(2.4),
      3: pw.FlexColumnWidth(1.6),
      4: pw.FlexColumnWidth(1.5),
    },
    children: [
      _headerRow(const ['Date', 'Type', 'Description', 'Amount', 'Settled']),
      for (final row in rows)
        pw.TableRow(
          children: [
            _cell(row.date),
            _cell(row.isVoid ? '${row.type} (void)' : row.type),
            _cell(row.description),
            _cell(
              row.equivalent == null ? row.amount : '${row.amount}\n${row.equivalent}',
              align: pw.TextAlign.right,
              color: row.isVoid ? _muted : (row.isReceivable ? _receivable : _payable),
            ),
            _cell(row.settlement ?? '—', align: pw.TextAlign.right, color: _muted),
          ],
        ),
    ],
  );

  static pw.TableRow _headerRow(List<String> labels) => pw.TableRow(
    decoration: const pw.BoxDecoration(color: _band),
    children: [
      for (final label in labels)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(
            label.toUpperCase(),
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ),
    ],
  );

  static pw.Widget _cell(
    String value, {
    bool bold = false,
    PdfColor color = _ink,
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      value,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 8.5,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  static pw.Widget _sectionTitle(String title, String subtitle) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink),
      ),
      pw.Text(subtitle, style: const pw.TextStyle(fontSize: 8, color: _muted)),
    ],
  );

  static pw.Widget _runningHeader(String workspace) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(workspace, style: const pw.TextStyle(fontSize: 8, color: _muted)),
        pw.Text('Accounting export', style: const pw.TextStyle(fontSize: 8, color: _muted)),
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
