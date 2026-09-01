import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/export_csv.dart';
import '../../core/export_json.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/export_models.dart';
import '../../data/export_pdf.dart';
import '../../data/ledger_repository.dart';
import '../../data/models.dart';
import '../../data/statement_download.dart';
import '../../providers.dart';
import '../motion.dart';
import '../widgets/common.dart';
import 'sheet_scaffold.dart';

/// Exporting the workspace (Phase 4 and 5).
///
/// The sheet answers one question before it does anything: **what am I
/// exporting?** The counts above the button come from `export_workspace()` and
/// move as the filters move, so the answer is the database's, not a guess, and
/// the user sees it before a file exists rather than after.
///
/// Mobile-first, and unlike the web's version deliberately not a form:
///
///   * choices are chips and segments, sized for a thumb, never dropdowns;
///   * the period is offered as the four ranges people actually ask for, with
///     a date picker behind "Custom" for the fifth;
///   * the format is picked last, as three tappable cards with one line each
///     saying what the file is for;
///   * progress is real — pages loaded out of the total the header reported —
///     because a large workspace takes long enough that a spinner would be a
///     lie about how much is left;
///   * every ending is stated in words, including the one where the user
///     cancels the save dialog, which is not an error.
Future<void> showExportSheet(
  BuildContext context,
  WidgetRef ref, {
  Person? person,
}) {
  return showAppSheet<void>(
    context,
    (context) => _ExportSheet(person: person),
  );
}

enum _Format { pdf, csv, json }

enum _Period { all, month, quarter, year, custom }

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({this.person});

  /// When the sheet is opened from a person's screen, that account is the
  /// default — the export the user is most likely to have come for.
  final Person? person;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  _Format _format = _Format.pdf;
  _Period _period = _Period.all;
  String _scope = 'all';
  bool _includeVoid = false;
  String? _personId;
  String? _personName;
  DateTimeRange? _custom;

  bool _busy = false;
  int _loaded = 0;
  int _total = 0;
  String? _error;
  String? _done;

  @override
  void initState() {
    super.initState();
    _personId = widget.person?.id;
    _personName = widget.person?.name;
  }

  ExportFilters get _filters {
    final range = _range();
    return ExportFilters(
      from: range?.start == null ? null : isoDate(range!.start),
      to: range?.end == null ? null : isoDate(range!.end),
      personId: _personId,
      scope: _scope,
      includeVoid: _includeVoid,
    );
  }

  DateTimeRange? _range() {
    final now = DateTime.now();
    return switch (_period) {
      _Period.all => null,
      _Period.month => DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      _Period.quarter => DateTimeRange(
        start: DateTime(now.year, now.month - 2, 1),
        end: now,
      ),
      _Period.year => DateTimeRange(start: DateTime(now.year, 1, 1), end: now),
      _Period.custom => _custom,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final preview = ref.watch(exportPreviewProvider(_filters));

    return SheetScaffold(
      title: 'Export',
      subtitle: _personName ?? 'Your whole workspace',
      icon: AppIcons.download,
      error: _error,
      busy: _busy,
      primaryLabel: _done != null ? 'Done' : (_busy ? 'Preparing…' : 'Export'),
      cancelLabel: _done != null ? 'Close' : 'Cancel',
      onPrimary: _busy ? null : (_done != null ? () => Navigator.of(context).pop() : _run),
      children: _done != null
          ? [_Done(message: _done!)]
          : [
              _label('What'),
              _accountRow(),
              const SizedBox(height: AppSpacing.lg),

              _label('Period'),
              _periodChips(),
              if (_period == _Period.custom) ...[
                const SizedBox(height: AppSpacing.sm),
                _customRange(),
              ],
              const SizedBox(height: AppSpacing.lg),

              _label('Include'),
              Segmented<String>(
                value: _scope,
                segments: const [
                  (value: 'all', label: 'Everything'),
                  (value: 'regular', label: 'Transactions'),
                  (value: 'opening', label: 'Opening'),
                ],
                onChanged: (value) => setState(() => _scope = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              _voidToggle(),
              const SizedBox(height: AppSpacing.lg),

              _label('Format'),
              _formatCards(),
              const SizedBox(height: AppSpacing.lg),

              _summary(preview, palette),
            ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: context.money.inkFaint,
      ),
    ),
  );

  Widget _accountRow() => Segmented<bool>(
    value: _personId == null,
    segments: [
      (value: true, label: 'Whole workspace'),
      (value: false, label: _personName ?? 'One account'),
    ],
    onChanged: (whole) async {
      if (whole) {
        setState(() {
          _personId = null;
          _personName = null;
        });
        return;
      }
      if (_personId != null) return;
      await _pickPerson();
    },
  );

  Future<void> _pickPerson() async {
    final people = await ref.read(
      peopleProvider((
        query: '',
        includeArchived: true,
        sort: PeopleSort.name,
      )).future,
    );
    if (!mounted) return;

    final chosen = await showAppSheet<PersonBalance>(
      context,
      (context) => SheetScaffold(
        title: 'Which account?',
        primaryLabel: 'Close',
        onPrimary: () => Navigator.of(context).pop(),
        children: [
          for (final person in people)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(person.name, size: 34),
              title: Text(person.name),
              subtitle: Text(person.currency),
              onTap: () => Navigator.of(context).pop(person),
            ),
        ],
      ),
    );

    if (chosen != null && mounted) {
      setState(() {
        _personId = chosen.personId;
        _personName = chosen.name;
      });
    }
  }

  Widget _periodChips() => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final option in const [
        (_Period.all, 'All time'),
        (_Period.month, 'This month'),
        (_Period.quarter, 'Last 3 months'),
        (_Period.year, 'This year'),
        (_Period.custom, 'Custom'),
      ])
        _Chip(
          label: option.$2,
          selected: _period == option.$1,
          onTap: () async {
            if (option.$1 == _Period.custom) {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                initialDateRange: _custom,
              );
              if (picked == null) return;
              setState(() {
                _custom = picked;
                _period = _Period.custom;
              });
              return;
            }
            setState(() => _period = option.$1);
          },
        ),
    ],
  );

  Widget _customRange() {
    final range = _custom;
    return Text(
      range == null
          ? 'Pick the dates to include.'
          : '${statementDate(isoDate(range.start))} — ${statementDate(isoDate(range.end))}',
      style: TextStyle(fontSize: 12, color: context.money.inkMuted),
    );
  }

  Widget _voidToggle() => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    value: _includeVoid,
    onChanged: (value) => setState(() => _includeVoid = value),
    title: const Text('Include voided history'),
    subtitle: Text(
      'Entries that were reversed. Off by default.',
      style: TextStyle(fontSize: 11, color: context.money.inkFaint),
    ),
  );

  Widget _formatCards() => Column(
    children: [
      for (final option in const [
        (_Format.pdf, 'PDF', 'A printable report: position, accounts, ledger.'),
        (_Format.csv, 'CSV', 'One row per entry, for a spreadsheet.'),
        (_Format.json, 'JSON', 'A complete backup, every field kept.'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _FormatCard(
            title: option.$2,
            description: option.$3,
            selected: _format == option.$1,
            onTap: () => setState(() => _format = option.$1),
          ),
        ),
    ],
  );

  /// The answer to "what am I exporting?", in the database's own numbers.
  Widget _summary(AsyncValue<ExportHeader> preview, AccounicColors palette) {
    final busyLine = _busy && _total > 0 ? 'Loading $_loaded of $_total entries…' : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Icon(AppIcons.note, size: 16, color: palette.inkFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: preview.when(
              loading: () => Text(
                'Counting…',
                style: TextStyle(fontSize: 12, color: palette.inkMuted),
              ),
              error: (_, __) => Text(
                'The size of this export could not be checked. You can still try it.',
                style: TextStyle(fontSize: 12, color: palette.inkMuted),
              ),
              data: (header) => Text(
                busyLine ??
                    '${header.counts.entries} entries · ${header.counts.people} '
                        '${header.counts.people == 1 ? 'account' : 'accounts'} · '
                        '${header.filters.description}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _loaded = 0;
      _total = 0;
    });

    try {
      final bundle = await ref.read(exportRepositoryProvider).load(
        _filters,
        onProgress: (loaded, total) {
          if (!mounted) return;
          setState(() {
            _loaded = loaded;
            _total = total;
          });
        },
      );

      final Uint8List bytes;
      final String extension;
      final String mime;
      final String label;

      switch (_format) {
        case _Format.pdf:
          bytes = await WorkspaceExportPdf.build(bundle);
          extension = 'pdf';
          mime = 'application/pdf';
          label = 'PDF';
        case _Format.csv:
          // utf8.encode, never codeUnits: a note in Devanagari or a name in
          // Arabic is multi-byte, and codeUnits would write UTF-16 halves as
          // bytes and corrupt the file (Phase 5).
          bytes = Uint8List.fromList(
            utf8.encode(csvWithBom(entriesToCsv(bundle.entries))),
          );
          extension = 'csv';
          mime = 'text/csv';
          label = 'CSV';
        case _Format.json:
          bytes = Uint8List.fromList(
            utf8.encode(exportDocumentToJson(buildExportDocument(bundle))),
          );
          extension = 'json';
          mime = 'application/json';
          label = 'JSON';
      }

      final result = await const StatementDownloader().saveBytes(
        bytes: bytes,
        filename: exportFilename(extension, scope: _personName),
        typeLabel: label,
        extension: extension,
        mimeType: mime,
      );

      if (!mounted) return;

      switch (result) {
        case StatementSaved(:final path, :final chosen):
          Haptics.success();
          setState(() {
            _busy = false;
            _done = chosen
                ? 'Saved to $path'
                : 'Saved to your device: $path';
          });
        case StatementSaveCancelled():
          // Not an error. The filters are still here and the sheet stays open.
          setState(() => _busy = false);
        case StatementSaveFailed(:final message):
          setState(() {
            _busy = false;
            _error = message;
          });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is Exception
            ? 'The export could not be built. Nothing has been saved.'
            : '$error';
      });
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: AnimatedContainer(
        duration: Motion.fast,
        // 44 high: a chip a thumb can hit without aiming.
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.raised : palette.sunken,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? palette.lineStrong : palette.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Theme.of(context).colorScheme.onSurface : palette.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $description',
      child: Pressable(
        onTap: onTap,
        scale: 0.99,
        child: AnimatedContainer(
          duration: Motion.fast,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.raised : palette.sunken,
            borderRadius: AppRadius.cardAll,
            border: Border.all(
              color: selected ? palette.lineStrong : palette.line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(fontSize: 11.5, color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? AppIcons.check : AppIcons.forward,
                size: 18,
                color: selected ? palette.receivable : palette.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.check, size: 34, color: palette.receivable),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Export saved',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: palette.inkMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: message)),
                child: const Text('Copy path'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
