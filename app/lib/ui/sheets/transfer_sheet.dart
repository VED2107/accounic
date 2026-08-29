import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/ledger_repository.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../widgets/amount_field.dart';
import '../widgets/currency_field.dart';
import '../widgets/forms.dart';
import 'sheet_scaffold.dart';

/// Move money from one person to another (upgrade 46).
///
/// The sheet is shaped like the sentence a user would say — from whom, to whom,
/// how much — and it never asks for a direction, because a transfer has one by
/// construction: it leaves the first account and arrives in the second.
///
/// Two conversions can be involved and usually neither is:
///
///     what you typed → what leaves the source → what reaches the destination
///
/// Each panel appears only when its two currencies differ, so a single-currency
/// transfer — which is nearly all of them — is four fields and a button.
///
/// The client never computes a figure that gets stored. Amounts and rates
/// travel; the database derives both converted amounts, exactly as it does for
/// every other money RPC (context.md §7). The one exception is "what actually
/// arrived", which is not derived from anything.
Future<bool> showTransferSheet(
  BuildContext context,
  WidgetRef ref, {
  PersonBalance? from,
}) async {
  final result = await showAppSheet<bool>(
    context,
    (context) => _TransferSheet(from: from),
  );
  return result ?? false;
}

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet({this.from});

  /// Pre-selected source, when opened from a person's screen.
  final PersonBalance? from;

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  late PersonBalance? _source = widget.from;
  PersonBalance? _destination;

  final String _date = todayIso();
  final _note = TextEditingController();

  String? _entryCurrency;
  int? _amount;

  // The overrides on the SECOND step: what reaches the other account.
  bool _manualAmount = false;
  int? _actualMinor;
  bool _manualRate = false;
  int? _typedRateE9;

  // And the rate override on the FIRST step — what leaves the source account
  // when the amount was typed in some third currency.
  //
  // This was missing, and it was the only conversion in either client that
  // offered the automatic rate without the manual one beside it. The web has
  // had it all along (`allowAmountOverride={false}` there turns off the AMOUNT
  // override, not the rate), so the two clients disagreed about what a transfer
  // could say. `create_transfer()` takes `p_entry_rate_e9` for exactly this
  // leg — the write path was ready and only the sheet was not asking.
  //
  // There is still no AMOUNT override here, and that is deliberate rather than
  // an omission: `create_transfer()` accepts a converted amount for the second
  // leg only, so a control here would promise something the write path cannot
  // keep.
  bool _manualEntryRate = false;
  int? _typedEntryRateE9;

  /// One token per opened sheet, so a double tap moves the money once.
  ///
  /// Minted here rather than on the server: the point is that the SECOND
  /// request carries the same value as the first, which only the client can
  /// arrange. The database refuses to create a second transfer for a token it
  /// has already seen and returns the first one instead.
  final String _token = _mintToken();

  bool _saving = false;
  String? _error;

  static String _mintToken() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The two ledger denominations.
  ///
  /// `currency` on a balance row is the person's LEDGER currency — what their
  /// stored figures are in — which is what a transfer moves, so it is the right
  /// one here and `defaultCurrency` is not.
  String get _fromCurrency =>
      normaliseCode(_source?.currency ?? ref.read(currencyProvider));
  String get _toCurrency => normaliseCode(_destination?.currency ?? _fromCurrency);
  String get _typedCurrency => normaliseCode(_entryCurrency ?? _fromCurrency);

  bool get _samePerson =>
      _source != null && _destination != null && _source!.personId == _destination!.personId;

  /// What leaves the source, previewed. The stored figure is the database's.
  /// The rate the first step converts at: the one the user typed, or the
  /// fetched one. A hand-typed rate is used as given and never quietly
  /// replaced — it is the rate for this transfer.
  int? get _entryRateE9 {
    if (_typedCurrency == _fromCurrency) return null;
    if (_manualEntryRate) return _typedEntryRateE9;
    return ref.read(rateProvider((from: _typedCurrency, to: _fromCurrency))).value?.rateE9;
  }

  int? get _sourceMinor {
    final amount = _amount;
    if (amount == null) return null;
    if (_typedCurrency == _fromCurrency) return amount;
    final rateE9 = _entryRateE9;
    if (rateE9 == null) return null;
    return convertMinor(amount, _typedCurrency, _fromCurrency, rateE9);
  }

  bool get _ready =>
      _source != null &&
      _destination != null &&
      !_samePerson &&
      _amount != null &&
      (_typedCurrency == _fromCurrency || _sourceMinor != null) &&
      // A rate override with nothing valid typed into it is not savable: the
      // transfer would be written at a rate the user has just said is wrong.
      !(_manualEntryRate && _typedCurrency != _fromCurrency && _typedEntryRateE9 == null) &&
      !(_manualRate && _fromCurrency != _toCurrency && _typedRateE9 == null);

  Future<void> _save() async {
    if (!_ready || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final entryRate = _entryRateE9;

      // A hand-typed rate is used as given and never quietly replaced: it is
      // the rate for this transfer.
      final crossRate = _fromCurrency == _toCurrency
          ? null
          : _manualRate && _typedRateE9 != null
              ? _typedRateE9
              : ref.read(rateProvider((from: _fromCurrency, to: _toCurrency))).value?.rateE9;

      await ref.read(ledgerRepositoryProvider).createTransfer(
            fromPersonId: _source!.personId,
            toPersonId: _destination!.personId,
            amountMinor: _amount!,
            currency: _typedCurrency,
            date: _date,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            entryRateE9: entryRate,
            exchangeRateE9: crossRate,
            rateSource:
                _manualRate || _manualEntryRate ? kManualRateSource : null,
            convertedAmountMinor: _manualAmount ? _actualMinor : null,
            conversionMode: _manualAmount ? 'manual' : null,
            clientToken: _token,
          );

      // Both accounts moved, so both are invalidated.
      ref.refreshLedger(personId: _source!.personId);
      ref.refreshLedger(personId: _destination!.personId);
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final people = ref.watch(peopleProvider(
      (query: '', includeArchived: false, sort: PeopleSort.name),
    ));

    return SheetScaffold(
      title: 'Transfer money',
      subtitle: 'Moves money between two of your accounts. '
          'One transaction, recorded on both.',
      error: _error,
      busy: _saving,
      primaryLabel: 'Record transfer',
      onPrimary: _ready ? _save : null,
      children: [
        FormSection(
          first: true,
          title: 'From',
          children: [
            _PersonChoice(
              value: _source,
              people: people.value ?? const [],
              loading: people.isLoading,
              hint: 'Who the money is coming from',
              onChanged: (person) => setState(() {
                _source = person;
                // Following the source keeps the ordinary case free of
                // decisions: pick a dirham account and you are typing dirhams
                // until you say otherwise.
                _entryCurrency = null;
                _manualRate = false;
                _manualAmount = false;
                _manualEntryRate = false;
                _typedEntryRateE9 = null;
              }),
            ),
          ],
        ),
        FormSection(
          title: 'To',
          children: [
            _PersonChoice(
              value: _destination,
              people: people.value ?? const [],
              loading: people.isLoading,
              hint: 'Who it is going to',
              onChanged: (person) => setState(() => _destination = person),
            ),
            if (_samePerson) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Money cannot be transferred to the account it came from. '
                'Choose someone else.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.payable,
                ),
              ),
            ],
            // The sentence, before any of the arithmetic: who loses it and who
            // gains it. The arrow does the work a "direction" toggle would
            // otherwise have to, and it cannot be set wrong — it is read from
            // the two choices rather than chosen.
            if (_source != null && _destination != null && !_samePerson) ...[
              const SizedBox(height: AppSpacing.md),
              _Direction(
                from: _source!.name,
                to: _destination!.name,
                fromCurrency: _fromCurrency,
                toCurrency: _toCurrency,
              ),
            ],
          ],
        ),
        FormSection(
          title: 'Amount',
          children: [
            AmountField(
              currency: _typedCurrency,
              autofocus: widget.from != null,
              onChanged: (minor) => setState(() => _amount = minor),
            ),
            const SizedBox(height: AppSpacing.md),
            CurrencyField(
              value: _typedCurrency,
              label: 'Entered in',
              helper: _typedCurrency == _fromCurrency
                  ? 'Source account currency'
                  : 'Leaves the account in $_fromCurrency',
              onChanged: (code) => setState(() => _entryCurrency = code),
            ),

            // Step one — only when the user typed in something other than the
            // source account's own denomination.
            //
            // The rate can be overridden here exactly as on every other sheet;
            // the AMOUNT cannot, because create_transfer() has nowhere to put a
            // converted figure for this leg. Same rule, same flag name, as the
            // web's panel.
            if (_typedCurrency != _fromCurrency) ...[
              const SizedBox(height: AppSpacing.md),
              ConversionPanel(
                amountMinor: _amount,
                from: _typedCurrency,
                to: _fromCurrency,
                allowAmountOverride: false,
                manual: false,
                onManualChanged: (_) {},
                onActualChanged: (_) {},
                rateManual: _manualEntryRate,
                onRateManualChanged: (on) => setState(() => _manualEntryRate = on),
                onManualRateChanged: (rate) => setState(() => _typedEntryRateE9 = rate),
              ),
            ],

            // Step two — what reaches the other account, and the one place a
            // user can say the counter handed over something else.
            if (_fromCurrency != _toCurrency) ...[
              const SizedBox(height: AppSpacing.md),
              ConversionPanel(
                amountMinor: _sourceMinor,
                from: _fromCurrency,
                to: _toCurrency,
                manual: _manualAmount,
                onManualChanged: (on) => setState(() => _manualAmount = on),
                onActualChanged: (minor) => setState(() => _actualMinor = minor),
                rateManual: _manualRate,
                onRateManualChanged: (on) => setState(() => _manualRate = on),
                onManualRateChanged: (rate) => setState(() => _typedRateE9 = rate),
              ),
            ],
          ],
        ),
        FormSection(
          title: 'Details',
          children: [
            AppTextField(
              controller: _note,
              label: 'Reference',
              hint: 'Rent share',
              maxLength: 500,
            ),
          ],
        ),
      ],
    );
  }
}

/// Who loses it and who gains it, stated in one line.
class _Direction extends StatelessWidget {
  const _Direction({
    required this.from,
    required this.to,
    required this.fromCurrency,
    required this.toCurrency,
  });

  final String from;
  final String to;
  final String fromCurrency;
  final String toCurrency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Container(
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
          Expanded(
            child: _Party(name: from, currency: fromCurrency, incoming: false),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Icon(AppIcons.forward, size: AppIconSize.sm, color: palette.inkFaint),
          ),
          Expanded(
            child: _Party(name: to, currency: toCurrency, incoming: true),
          ),
        ],
      ),
    );
  }
}

class _Party extends StatelessWidget {
  const _Party({required this.name, required this.currency, required this.incoming});

  final String name;
  final String currency;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        Text(
          '${incoming ? 'receives' : 'pays'} · $currency',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: incoming ? palette.receivable : palette.payable,
          ),
        ),
      ],
    );
  }
}

/// Picking one of the workspace's people.
///
/// A dropdown rather than a search field: a transfer is between two accounts
/// the user already keeps, and the list is bounded by how many people they
/// have. The balance beside each name is what tells them which one they meant.
class _PersonChoice extends StatelessWidget {
  const _PersonChoice({
    required this.value,
    required this.people,
    required this.loading,
    required this.hint,
    required this.onChanged,
  });

  final PersonBalance? value;
  final List<PersonBalance> people;
  final bool loading;
  final String hint;
  final ValueChanged<PersonBalance?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    if (loading && people.isEmpty) {
      return Text(
        'Loading your people…',
        style: TextStyle(fontSize: 13, color: palette.inkMuted),
      );
    }

    if (people.length < 2) {
      return Text(
        'A transfer needs two accounts. Add another person first.',
        style: TextStyle(fontSize: 13, color: palette.inkMuted),
      );
    }

    return DropdownButtonFormField<String?>(
      value: value?.personId,
      isExpanded: true,
      hint: Text(hint),
      items: [
        for (final person in people)
          DropdownMenuItem<String?>(
            value: person.personId,
            child: Text(
              '${person.name} · '
              '${formatMoney(person.netBalance.abs(), currency: person.currency)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (id) => onChanged(
        id == null ? null : people.where((p) => p.personId == id).firstOrNull,
      ),
    );
  }
}
