import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/activity_csv.dart';
import '../../core/activity_report.dart';
import '../../core/dates.dart';
import '../../core/export_csv.dart';
import '../../core/export_json.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/activity_pdf.dart';
import '../../data/export_models.dart';
import '../../data/export_pdf.dart';
import '../../data/ledger_repository.dart';
import '../../data/models.dart';
import '../../data/statement_download.dart';
import '../../providers.dart';
import '../motion.dart';
import '../widgets/common.dart';
import '../widgets/date_picker.dart';
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
///
/// The sheet has two subjects. [ExportSubject.workspace] is the full one above,
/// reached from Profile: the formal ledger report, grouped by account.
/// [ExportSubject.activity] is the Activity screen's: the same architecture,
/// the same RPCs and the same words, producing the chronological journal that
/// screen actually shows — day, then everything that happened on it.
///
/// They are deliberately different documents, and the two must not converge.
Future<void> showExportSheet(
  BuildContext context,
  WidgetRef ref, {
  Person? person,
  ExportSubject subject = ExportSubject.workspace,
  ActivityView view = ActivityView.all,
  String? day,
}) {
  return showAppSheet<void>(
    context,
    (context) => _ExportSheet(
      person: person,
      subject: subject,
      view: view,
      day: day,
    ),
  );
}

/// What an export is of.
enum ExportSubject {
  /// Everything, grouped by account: the formal ledger report.
  workspace,

  /// The Activity feed, grouped by day: the chronological journal.
  activity,
}

/// Which dates an Activity export covers.
enum _DateScope { day, range, all }

enum _Format { pdf, csv, json }

enum _Period { all, month, quarter, year, custom }

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({
    this.person,
    this.subject = ExportSubject.workspace,
    this.view = ActivityView.all,
    this.day,
  });

  /// When the sheet is opened from a person's screen, that account is the
  /// default — the export the user is most likely to have come for.
  final Person? person;

  final ExportSubject subject;

  /// The Activity tab that was showing when this was opened.
  final ActivityView view;

  /// The day heading this was opened from, if any.
  final String? day;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  /// True for the Activity export: two choices, two formats, one journal.
  bool get _isActivity => widget.subject == ExportSubject.activity;

  late ActivityView _view;
  late _DateScope _dateScope;
  DateTimeRange? _pickedRange;

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
    _view = widget.view;
    // Opened from a day heading, that day is the scope; opened from the page
    // header there is no day in context and the scope is the whole feed.
    _dateScope = widget.day != null ? _DateScope.day : _DateScope.all;
  }

  /// The dates an Activity export covers, from the two controls above it.
  ActivityRange get _activityRange => switch (_dateScope) {
    _DateScope.all => ActivityRange.all,
    _DateScope.day => widget.day == null
        ? ActivityRange.all
        : ActivityRange.day(widget.day!),
    _DateScope.range => ActivityRange(
      from: _pickedRange == null ? null : isoDate(_pickedRange!.start),
      to: _pickedRange == null ? null : isoDate(_pickedRange!.end),
    ),
  };

  /// A half-picked range is not an error, it is an unfinished thought: nothing
  /// is counted or exported until both ends are there.
  bool get _blocked =>
      _isActivity &&
      (_activityRange.isBackwards ||
          (_dateScope == _DateScope.range && _pickedRange == null));

  ExportFilters get _filters {
    if (_isActivity) {
      final range = _activityRange;
      return ExportFilters.activity(
        kinds: _view.kinds,
        from: range.from,
        to: range.to,
      );
    }

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

    // Nothing to export is a state, not a failure: the action goes quiet and
    // the sheet says why rather than producing an empty file.
    final empty = !_blocked && preview.valueOrNull?.counts.entries == 0;

    return SheetScaffold(
      title: _isActivity ? 'Export activity' : 'Export',
      subtitle: _isActivity
          ? 'Day by day, newest first'
          : (_personName ?? 'Your whole workspace'),
      icon: AppIcons.download,
      error: _error,
      busy: _busy,
      primaryLabel: _done != null ? 'Done' : (_busy ? 'Preparing…' : 'Export'),
      cancelLabel: _done != null ? 'Close' : 'Cancel',
      onPrimary: _busy || ((empty || _blocked) && _done == null)
          ? null
          : (_done != null ? () => Navigator.of(context).pop() : _run),
      children: _done != null
          ? [_Done(message: _done!)]
          : _isActivity
          ? _activityBody(preview, palette)
          : _workspaceBody(preview, palette),
    );
  }

  /// The Activity export: two independent choices, then a format.
  List<Widget> _activityBody(AsyncValue<ExportHeader> preview, AccounicColors palette) => [
    _label('Date'),
    Segmented<_DateScope>(
      value: _dateScope,
      segments: [
        if (widget.day != null)
          (value: _DateScope.day, label: dayGroupLabel(widget.day!)),
        (value: _DateScope.range, label: 'Date range'),
        (value: _DateScope.all, label: 'All activity'),
      ],
      onChanged: (value) => setState(() => _dateScope = value),
    ),
    if (_dateScope == _DateScope.range) ...[
      const SizedBox(height: AppSpacing.sm),
      _rangeRow(palette),
    ],
    const SizedBox(height: AppSpacing.lg),

    _label('Category'),
    Segmented<ActivityView>(
      value: _view,
      segments: const [
        (value: ActivityView.all, label: 'Everything'),
        (value: ActivityView.transaction, label: 'Transactions'),
        (value: ActivityView.settlement, label: 'Settlements'),
      ],
      onChanged: (value) => setState(() => _view = value),
    ),
    const SizedBox(height: AppSpacing.lg),

    _label('Format'),
    _formatCards(),
    const SizedBox(height: AppSpacing.lg),

    _summary(preview, palette),
  ];

  /// The workspace export, unchanged: the formal ledger report.
  List<Widget> _workspaceBody(AsyncValue<ExportHeader> preview, AccounicColors palette) => [
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
  ];

  /// The custom range, picked with the product's own calendar.
  Widget _rangeRow(AccounicColors palette) {
    final range = _pickedRange;

    return Pressable(
      onTap: _busy
          ? null
          : () async {
              final picked = await showAccounicDateRangePicker(
                context,
                initialRange: range,
                firstDate: DateTime(2000),
                title: 'Which days?',
              );
              if (picked != null && mounted) {
                setState(() => _pickedRange = picked);
              }
            },
      scale: 0.99,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: palette.sunken,
          borderRadius: AppRadius.fieldAll,
          border: Border.all(color: palette.line),
        ),
        child: Row(
          children: [
            Icon(AppIcons.date, size: AppIconSize.sm, color: palette.inkFaint),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                range == null
                    ? 'Pick two dates'
                    : '${statementDate(isoDate(range.start))} → '
                          '${statementDate(isoDate(range.end))}',
                style: TextStyle(
                  fontSize: 13,
                  color: range == null
                      ? palette.inkFaint
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Icon(AppIcons.forward, size: AppIconSize.sm, color: palette.inkFaint),
          ],
        ),
      ),
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
              final picked = await showAccounicDateRangePicker(
                context,
                firstDate: DateTime(2000),
                initialRange: _custom,
                title: 'Which days?',
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

  /// The formats offered.
  ///
  /// JSON is absent from the Activity export on purpose. It is the backup
  /// format — versioned, relational, every account and the opening book — and
  /// offering it beside two views of the feed would present a workspace backup
  /// as though it were a third way to read the same days.
  List<(_Format, String, String)> get _formats => _isActivity
      ? const [
          (_Format.pdf, 'PDF', 'The activity report, day by day.'),
          (_Format.csv, 'CSV', 'One row per entry, for a spreadsheet.'),
        ]
      : const [
          (_Format.pdf, 'PDF', 'A printable report: position, accounts, ledger.'),
          (_Format.csv, 'CSV', 'One row per entry, for a spreadsheet.'),
          (_Format.json, 'JSON', 'A complete backup, every field kept.'),
        ];

  Widget _formatCards() => Column(
    children: [
      for (final option in _formats)
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

  /// The count and the scope, in the database's own numbers.
  ///
  /// For an Activity export it counts exactly the slice the file will hold —
  /// the same figure, from the same filters, so the number above the button and
  /// the number of rows in the document cannot disagree.
  String _summaryLine(ExportHeader header) {
    if (_isActivity) {
      final n = header.counts.entries;
      if (n == 0) return 'No activity to export';
      return '$n ${n == 1 ? 'entry' : 'entries'} · ${_view.label} · '
          '${activityScopeLabel(_activityRange).toLowerCase()}';
    }
    return '${header.counts.entries} entries · ${header.counts.people} '
        '${header.counts.people == 1 ? 'account' : 'accounts'} · '
        '${header.filters.description}';
  }

  /// The answer to "what am I exporting?", in the database's own numbers.
  Widget _summary(AsyncValue<ExportHeader> preview, AccounicColors palette) {
    final busyLine = _busy && _total > 0 ? 'Loading $_loaded of $_total entries…' : null;

    // A range that is half-picked or the wrong way round is answered here
    // rather than by counting something nobody asked for.
    if (_blocked) {
      final message = _activityRange.isBackwards
          ? 'The start of the range is after its end'
          : 'Pick both ends of the range';
      return _summaryBox(
        palette,
        Text(
          message,
          style: TextStyle(fontSize: 12, color: palette.payable),
        ),
      );
    }

    return _summaryBox(
      palette,
      preview.when(
        loading: () => Text(
          'Counting…',
          style: TextStyle(fontSize: 12, color: palette.inkMuted),
        ),
        error: (_, __) => Text(
          'The size of this export could not be checked. You can still try it.',
          style: TextStyle(fontSize: 12, color: palette.inkMuted),
        ),
        data: (header) => Text(
          busyLine ?? _summaryLine(header),
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }

  /// The bordered line under the choices, whatever it happens to say.
  Widget _summaryBox(AccounicColors palette, Widget child) => Container(
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
        Expanded(child: child),
      ],
    ),
  );

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
          // Two different documents, deliberately: the Activity journal and
          // the workspace ledger report. They must not converge.
          bytes = _isActivity
              ? await ActivityExportPdf.build(
                  bundle,
                  view: _view,
                  scopeLabel: activityScopeLabel(_activityRange),
                )
              : await WorkspaceExportPdf.build(bundle);
          extension = 'pdf';
          mime = 'application/pdf';
          label = 'PDF';
        case _Format.csv:
          // utf8.encode, never codeUnits: a note in Devanagari or a name in
          // Arabic is multi-byte, and codeUnits would write UTF-16 halves as
          // bytes and corrupt the file (Phase 5).
          bytes = Uint8List.fromList(
            utf8.encode(
              csvWithBom(
                _isActivity
                    ? activityEntriesToCsv(bundle.entries, bundle.header.baseCurrency)
                    : entriesToCsv(bundle.entries),
              ),
            ),
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
        // Named after what is in it, in the convention every other export
        // already follows: accounic-activity-2026-09-04.pdf.
        filename: _isActivity
            ? activityExportFilename(extension, _view, _activityRange)
            : exportFilename(extension, scope: _personName),
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
