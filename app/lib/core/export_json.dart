import 'dart:convert';

import '../data/export_models.dart';

/// The workspace export as JSON (milestone 1.9.0, Phase 5).
///
/// The mirror of `web/src/lib/export/json.ts`. This is the backup format — the
/// one an export exists for — and its obligations are stricter than the CSV's:
///
///   * VERSIONED. `schema_version` is the first key, so a future reader knows
///     what it is holding before it parses the rest.
///   * SELF-DESCRIBING. Every currency used is defined in the file, exponent
///     included, so an integer amount can be read without knowing Accounic.
///   * RELATIONAL. People, opening balances, transactions and settlements keep
///     their ids and their references to each other.
///   * NO SECRETS. The owner's own profile, and nothing else: no token, no key,
///     no session, nothing about any other user.
///
/// The ledger is split into three lists rather than shipped as one flat feed,
/// because opening balances, transactions and settlements are three different
/// things in this product and flattening them is the mistake a whole release
/// was spent undoing.

Map<String, dynamic> buildExportDocument(ExportBundle bundle) {
  final opening = bundle.entries.where((e) => e.isOpening).toList();
  final regular = bundle.entries.where((e) => !e.isOpening).toList();

  return {
    'schema_version': kExportSchemaVersion,
    'generator': bundle.header.generator,
    'exported_at': bundle.header.exportedAt,
    'filters': bundle.header.filters.toJson(),
    // Stated rather than implied: a file holding the first 20,000 of 50,000
    // entries must not look like a complete backup.
    'truncated': bundle.truncated,
    'workspace': bundle.header.workspace,
    'summary': bundle.header.summary,
    'currencies': bundle.header.currencies.map((c) => c.toJson()).toList(),
    'people': bundle.header.people,
    'opening_balances': opening.map((e) => e.raw).toList(),
    'transactions': regular.where((e) => !e.isSettlement).map((e) => e.raw).toList(),
    'settlements': regular.where((e) => e.isSettlement).map((e) => e.raw).toList(),
    'counts': bundle.header.counts.toJson(),
  };
}

/// The document as a file's contents. Indented: a backup gets read by people.
String exportDocumentToJson(Map<String, dynamic> document) =>
    '${const JsonEncoder.withIndent('  ').convert(document)}\n';

/// The filename an export is offered under.
///
/// Dated, so a folder of them sorts chronologically, and named after what is in
/// it rather than after the app.
String exportFilename(String extension, {String? scope, DateTime? date}) {
  final day = (date ?? DateTime.now()).toUtc().toIso8601String().substring(0, 10);
  final slug = (scope ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty
      ? 'accounic-export-$day.$extension'
      : 'accounic-$slug-$day.$extension';
}
