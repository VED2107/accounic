import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../widgets/currency_field.dart';
import '../widgets/forms.dart';
import 'sheet_scaffold.dart';

/// Create or edit a person / business (context.md §5; upgrade §1, §3, §4, §12).
///
/// Beyond a name and a phone number this form now carries two things:
///
///   * **Currency.** Each account runs in its own, defaulting to the workspace's
///     base currency. People created before this feature have none stored,
///     which means exactly that default — so nothing changes for anyone using
///     one currency.
///   * **Opening balance.** So a user with real-world balances can start from
///     where they actually are, rather than inventing a transaction dated today
///     to fake it. Editing offers the same control: the current one is loaded,
///     and it can be changed or removed. Both paths go through the same
///     conversion arithmetic and the same RPC.
///
/// The form is also where the Android keyboard problem lived. What fixes it is
/// structural rather than cosmetic: the actions are pinned outside the scroll
/// view (see [SheetScaffold]), the sheet is padded by the live keyboard inset,
/// dragging or tapping away dismisses the keyboard, and every field hands focus
/// to the next one so the form can be completed without reaching for anything.
///
/// Returns the saved person, or null if cancelled.
Future<Person?> showPersonSheet(
  BuildContext context,
  WidgetRef ref, {
  Person? person,
  int openingMinor = 0,
}) {
  return showAppSheet<Person>(
    context,
    (context) => _PersonSheet(person: person, openingMinor: openingMinor),
  );
}

class _PersonSheet extends ConsumerStatefulWidget {
  const _PersonSheet({this.person, this.openingMinor = 0});

  final Person? person;

  /// The person's opening balance as a signed figure in their ledger currency —
  /// positive when they owe the user. `person_balances.opening_minor`. Only
  /// meaningful when editing.
  final int openingMinor;

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  late final _name = TextEditingController(text: widget.person?.name ?? '');
  late final _phone = TextEditingController(text: widget.person?.phone ?? '');
  late final _email = TextEditingController(text: widget.person?.email ?? '');
  late final _address = TextEditingController(text: widget.person?.address ?? '');
  late final _notes = TextEditingController(text: widget.person?.notes ?? '');
  final _opening = TextEditingController();

  // One node per field, so Next actually goes somewhere. Without them the
  // keyboard's Next key does nothing, which is the difference between a form
  // that can be filled with two thumbs and one that cannot.
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _notesFocus = FocusNode();
  final _openingFocus = FocusNode();

  late PartyType _type = widget.person?.type ?? PartyType.person;
  late String _currency = normaliseCode(widget.person?.currency ?? '');
  late OpeningDirection _direction = _initialDirection;

  /// What an opening balance is written in. On a create that follows the
  /// account picker; on an edit it is the frozen ledger currency, because that
  /// is what the database denominates the opening row in (db/migrations/0013).
  late String _openingTarget = _currency;

  /// The opening balance as it stood when the sheet opened, so an edit that
  /// only fixes a phone number does not retract and rewrite a perfectly good
  /// one — the database replaces rather than edits, and that would show in the
  /// history.
  int get _storedOpening => _isEdit ? widget.openingMinor : 0;

  OpeningDirection get _initialDirection => _storedOpening > 0
      ? OpeningDirection.theyOweMe
      : _storedOpening < 0
          ? OpeningDirection.iOweThem
          : OpeningDirection.none;

  bool get _openingDirty =>
      _isEdit &&
      (_direction != _initialDirection ||
          _openingCurrency != _openingTarget ||
          (_direction != OpeningDirection.none && _openingMinor != _storedOpening.abs()));

  /// Whether the opening balance's converted figure was replaced by what
  /// actually changed hands (upgrade 40).
  bool _openingManual = false;
  int? _openingActual;

  /// The same pair for the RATE: whether the user typed one, and which
  /// (upgrade 45). An opening balance is as likely as any entry to have been
  /// exchanged at a rate nobody publishes.
  bool _openingRateManual = false;
  int? _openingManualRateE9;
  late String _openingCurrency = _currency;

  bool _saving = false;
  String? _error;
  String? _openingError;

  /// Set once the database has explained what changing the currency does.
  /// Ticking the box and saving again goes through (db/migrations/0013).
  bool _currencyChangeOffered = false;
  bool _currencyChangeConfirmed = false;

  bool get _isEdit => widget.person != null;

  @override
  void initState() {
    super.initState();
    // A person with no stored currency is on the workspace's, which is what the
    // field must show — not an empty dropdown.
    final base = ref.read(currencyProvider);
    if (_currency.isEmpty) _currency = normaliseCode(base);
    _openingTarget = _isEdit
        ? normaliseCode(widget.person?.ledgerCurrencyOr(base) ?? base)
        : _currency;
    _openingCurrency = _openingTarget;
    if (_storedOpening != 0) {
      _opening.text = minorToInput(_storedOpening.abs(), currency: _openingTarget);
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _phone, _email, _address, _notes, _opening]) {
      controller.dispose();
    }
    for (final node in [
      _nameFocus,
      _phoneFocus,
      _emailFocus,
      _addressFocus,
      _notesFocus,
      _openingFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  int? get _openingMinor {
    final text = _opening.text.trim();
    if (text.isEmpty) return null;
    return parseAmountToMinor(text, currency: _openingCurrency);
  }

  /// Turns the opening-balance half of the form into RPC arguments, fetching a
  /// rate first when it is stated in a currency other than the one the row will
  /// be written in. Returns null after putting the reason on the field, which
  /// is the caller's signal to stop.
  ///
  /// Shared by create and edit so "I owe them" cannot come to mean two
  /// different things depending on which sheet you opened.
  Future<_OpeningArgs?> _resolveOpening() async {
    final entered = _direction == OpeningDirection.none ? null : _openingMinor;
    final foreign = entered != null && _openingCurrency != _openingTarget;

    // A hand-typed rate needs no lookup, and must not be replaced by one.
    final manualRate = foreign && _openingRateManual ? _openingManualRateE9 : null;
    final rate = foreign && manualRate == null
        ? await ref.read(ratesRepositoryProvider).rate(_openingCurrency, _openingTarget)
        : null;
    final rateE9 = manualRate ?? rate?.rateE9;
    final rateSource = manualRate != null ? kManualRateSource : rate?.source;

    if (foreign && rateE9 == null) {
      setState(() {
        _saving = false;
        _openingError =
            'No $_openingCurrency → $_openingTarget rate is available. Enter the opening '
            'balance in $_openingTarget.';
      });
      return null;
    }

    return _OpeningArgs(
      direction: _direction,
      amountMinor: foreign ? null : entered,
      enteredMinor: foreign ? entered : null,
      enteredCurrency: foreign ? _openingCurrency : null,
      rateE9: rateE9,
      rateSource: rateSource,
      convertedMinor: foreign && _openingManual ? _openingActual : null,
      conversionMode: foreign
          ? (_openingManual && _openingActual != null ? 'manual' : 'automatic')
          : null,
    );
  }

  Future<void> _save() async {
    // Guard against a second tap while the first is in flight. The button is
    // disabled too; this is the belt to that pair of braces, because a double
    // tap on a slow connection is how duplicate people get created.
    if (_saving) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      _nameFocus.requestFocus();
      return;
    }

    if (_direction != OpeningDirection.none) {
      if (_openingMinor == null || _openingMinor! <= 0) {
        setState(() => _openingError = 'Enter the amount you are starting from.');
        _openingFocus.requestFocus();
        return;
      }
    }

    // The keyboard has nothing left to contribute; putting it away lets the
    // user see the result of what they just pressed.
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _saving = true;
      _error = null;
      _openingError = null;
    });

    try {
      final repository = ref.read(ledgerRepositoryProvider);
      final Person person;

      if (_isEdit) {
        // The opening balance is resolved before the write, so a missing rate
        // is refused with the form intact rather than after the name has
        // already been saved.
        final opening = _openingDirty ? await _resolveOpening() : null;
        if (_openingDirty && opening == null) return;

        // Changing the currency needs no rate at all: it moves what future
        // entries default to and leaves every recorded figure exactly where it
        // is.
        person = await repository.updatePerson(
          personId: widget.person!.id,
          name: name,
          type: _type,
          phone: _clean(_phone),
          email: _clean(_email),
          address: _clean(_address),
          notes: _clean(_notes),
          currency: _currency,
          currencyChangeConfirmed: _currencyChangeConfirmed,
        );

        // Then the opening balance, through the same RPC the create path uses.
        // `none` clears it, which is how removing one works.
        if (opening != null) {
          await repository.setOpeningBalance(
            personId: person.id,
            direction: opening.direction,
            amountMinor: opening.amountMinor,
            enteredAmountMinor: opening.enteredMinor,
            enteredCurrency: opening.enteredCurrency,
            exchangeRateE9: opening.rateE9,
            rateSource: opening.rateSource,
            convertedAmountMinor: opening.convertedMinor,
            conversionMode: opening.conversionMode,
          );
        }
      } else {
        final opening = await _resolveOpening();
        if (opening == null) return;

        person = await repository.createPerson(
          name: name,
          type: _type,
          phone: _clean(_phone),
          email: _clean(_email),
          address: _clean(_address),
          notes: _clean(_notes),
          currency: _currency,
          opening: opening.direction,
          openingAmountMinor: opening.amountMinor,
          openingEnteredMinor: opening.enteredMinor,
          openingEnteredCurrency: opening.enteredCurrency,
          openingRateE9: opening.rateE9,
          openingRateSource: opening.rateSource,
          openingConvertedMinor: opening.convertedMinor,
          openingConversionMode: opening.conversionMode,
        );
      }

      ref.refreshLedger(personId: person.id);
      if (mounted) Navigator.of(context).pop(person);
    } on Failure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
        // The database refuses a currency change once and says what it will
        // do. That refusal is the confirmation step: the box appears, and the
        // same Save goes through when it is ticked. Nothing has been written
        // either way.
        if (failure.message.contains('affects future transactions only')) {
          _currencyChangeOffered = true;
          _currencyChangeConfirmed = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Phone and email share a line only where a line is wide enough to hold two
    // fields. On a phone that split leaves roughly 150px each, which is narrower
    // than the values they hold — a number wraps and an address truncates.
    final compact = context.isCompact;
    final base = normaliseCode(ref.watch(currencyProvider));
    final originalCurrency = normaliseCode(widget.person?.currency ?? base);
    // What this person's history is denominated in, which is what the balance
    // keeps being reported in after a switch. The same fallback chain the
    // database uses (db/migrations/0013).
    final ledgerCurrency =
        normaliseCode(widget.person?.ledgerCurrencyOr(base) ?? base);
    final currencyChanged = _isEdit && _currency != originalCurrency;

    final phone = AppTextField(
      label: 'Phone',
      controller: _phone,
      focusNode: _phoneFocus,
      icon: AppIcons.phone,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _emailFocus.requestFocus(),
      maxLength: 32,
      hint: '+91 98200 11223',
    );

    final email = AppTextField(
      label: 'Email',
      controller: _email,
      focusNode: _emailFocus,
      icon: AppIcons.email,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _addressFocus.requestFocus(),
      hint: 'Optional',
    );

    return SheetScaffold(
      title: _isEdit ? 'Edit details' : 'Add person or business',
      icon: _isEdit ? AppIcons.edit : AppIcons.addPerson,
      error: _error,
      busy: _saving,
      primaryLabel: _currencyChangeOffered
          ? 'Use $_currency from now on'
          : _isEdit
              ? 'Save changes'
              : 'Add person',
      onPrimary: _saving ? null : _save,
      children: [
        FormSection(
          first: true,
          title: 'Identity',
          children: [
            AppTextField(
              label: 'Name',
              controller: _name,
              focusNode: _nameFocus,
              autofocus: true,
              icon: AppIcons.person,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _phoneFocus.requestFocus(),
              maxLength: 120,
              hint: 'Rahul Traders',
            ),
            const SizedBox(height: AppSpacing.lg),
            _Labelled(
              label: 'Type',
              child: Row(
                children: [
                  for (final option in PartyType.values) ...[
                    Expanded(
                      child: _Choice(
                        label: option.label,
                        selected: _type == option,
                        onTap: () => setState(() => _type = option),
                      ),
                    ),
                    if (option != PartyType.values.last)
                      const SizedBox(width: AppSpacing.sm + 2),
                  ],
                ],
              ),
            ),
          ],
        ),

        FormSection(
          title: 'Currency',
          description: _isEdit
              ? 'This account’s history is denominated in $ledgerCurrency. Changing '
                  'the currency below only changes what new entries default to.'
              : 'What this account is kept in. Entries can still be made in another '
                  'currency.',
          children: [
            CurrencyField(
              label: 'Account currency',
              value: _currency,
              onChanged: (next) => setState(() {
                _currency = next;
                // On an edit the opening row stays in the frozen ledger
                // currency whatever new entries now default to, so the target
                // does not follow this picker.
                if (!_isEdit) {
                  _openingTarget = next;
                  if (_direction == OpeningDirection.none || _opening.text.trim().isEmpty) {
                    _openingCurrency = next;
                  }
                }
              }),
              helper: _currency == base ? 'Same as your workspace' : null,
            ),
            if (currencyChanged) ...[
              const SizedBox(height: AppSpacing.md),
              _CurrencyChangeNotice(
                from: ledgerCurrency,
                to: _currency,
                offered: _currencyChangeOffered,
                confirmed: _currencyChangeConfirmed,
                onConfirmed: (value) => setState(() => _currencyChangeConfirmed = value),
              ),
            ],
          ],
        ),

        FormSection(
            title: 'Opening balance',
            description: !_isEdit
                ? 'Already have an amount to settle with this person? Start from '
                    'it rather than recording a transaction that never happened.'
                : _storedOpening != 0
                    ? 'This account opened with '
                        '${formatMoney(_storedOpening.abs(), currency: _openingTarget)} '
                        '${_storedOpening > 0 ? 'in your favour' : 'against you'}. Change it, '
                        'or choose “No opening balance” to remove it.'
                    : 'This account has no opening balance. Add one if it started from a '
                        'figure rather than from zero.',
            children: [
              _OpeningBalance(
                direction: _direction,
                onDirection: (next) => setState(() {
                  _direction = next;
                  _openingError = null;
                }),
                controller: _opening,
                focusNode: _openingFocus,
                error: _openingError,
                accountCurrency: _openingTarget,
                openingCurrency: _openingCurrency,
                onOpeningCurrency: (next) => setState(() => _openingCurrency = next),
                onChanged: (_) => setState(() {}),
                manual: _openingManual,
                onManualChanged: (manual) => setState(() => _openingManual = manual),
                onActualChanged: (minor) => setState(() => _openingActual = minor),
                rateManual: _openingRateManual,
                onRateManualChanged: (manual) =>
                    setState(() => _openingRateManual = manual),
                onManualRateChanged: (rateE9) =>
                    setState(() => _openingManualRateE9 = rateE9),
              ),
            ],
          ),

        FormSection(
          title: 'Contact',
          aside: 'Optional',
          children: [
            if (compact) ...[
              phone,
              const SizedBox(height: AppSpacing.lg),
              email,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: phone),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: email),
                ],
              ),
          ],
        ),

        FormSection(
          title: 'Address & notes',
          aside: 'Optional',
          children: [
            AppTextField(
              label: 'Address',
              controller: _address,
              focusNode: _addressFocus,
              icon: AppIcons.address,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _notesFocus.requestFocus(),
              maxLength: 500,
              hint: 'Optional',
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Notes',
              controller: _notes,
              focusNode: _notesFocus,
              icon: AppIcons.note,
              maxLines: 3,
              maxLength: 2000,
              // The last field submits rather than offering another Next that
              // would go nowhere.
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              textCapitalization: TextCapitalization.sentences,
              hint: 'Payment terms, reference numbers, anything worth remembering.',
            ),
          ],
        ),
      ],
    );
  }
}

/// One opening balance, resolved into the arguments both RPCs take.
class _OpeningArgs {
  const _OpeningArgs({
    required this.direction,
    this.amountMinor,
    this.enteredMinor,
    this.enteredCurrency,
    this.rateE9,
    this.rateSource,
    this.convertedMinor,
    this.conversionMode,
  });

  final OpeningDirection direction;
  final int? amountMinor;
  final int? enteredMinor;
  final String? enteredCurrency;
  final int? rateE9;
  final String? rateSource;
  final int? convertedMinor;
  final String? conversionMode;
}

/// The existing-balance section (upgrade §4).
///
/// Direction is asked as a sentence — "I owe them" / "They owe me" — because
/// that is the question the user can answer without thinking about which way
/// the ledger runs. The mapping to a stored type happens in the database.
class _OpeningBalance extends StatelessWidget {
  const _OpeningBalance({
    required this.direction,
    required this.onDirection,
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.accountCurrency,
    required this.openingCurrency,
    required this.onOpeningCurrency,
    required this.onChanged,
    required this.manual,
    required this.onManualChanged,
    required this.onActualChanged,
    required this.rateManual,
    required this.onRateManualChanged,
    required this.onManualRateChanged,
  });

  final OpeningDirection direction;
  final ValueChanged<OpeningDirection> onDirection;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final String accountCurrency;
  final String openingCurrency;
  final ValueChanged<String> onOpeningCurrency;
  final ValueChanged<String> onChanged;
  final bool manual;
  final ValueChanged<bool> onManualChanged;
  final ValueChanged<int?> onActualChanged;

  /// Whether the RATE is the one the user typed, and what it is (upgrade 45).
  final bool rateManual;
  final ValueChanged<bool> onRateManualChanged;
  final ValueChanged<int?> onManualRateChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final amountMinor = parseAmountToMinor(controller.text, currency: openingCurrency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
          Column(
            children: [
              for (final option in OpeningDirection.values) ...[
                _Choice(
                  label: option.label,
                  selected: direction == option,
                  tone: option == OpeningDirection.iOweThem
                      ? palette.payable
                      : option == OpeningDirection.theyOweMe
                          ? palette.receivable
                          : null,
                  onTap: () => onDirection(option),
                ),
                if (option != OpeningDirection.values.last)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
          if (direction != OpeningDirection.none) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Opening amount',
              controller: controller,
              focusNode: focusNode,
              icon: AppIcons.amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: onChanged,
              error: error,
              hint: '0',
            ),
            const SizedBox(height: AppSpacing.md),
            CurrencyField(
              label: 'Stated in',
              value: openingCurrency,
              onChanged: onOpeningCurrency,
            ),
            if (openingCurrency != accountCurrency) ...[
              const SizedBox(height: AppSpacing.md),
              ConversionPanel(
                amountMinor: amountMinor,
                from: openingCurrency,
                to: accountCurrency,
                manual: manual,
                onManualChanged: onManualChanged,
                onActualChanged: onActualChanged,
                rateManual: rateManual,
                onRateManualChanged: onRateManualChanged,
                onManualRateChanged: onManualRateChanged,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Recorded as an opening balance dated to when this account starts, '
              'not as a transaction today.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.inkFaint),
            ),
          ],
      ],
    );
  }
}

/// What changing an existing account's currency actually does (upgrade §1).
class _CurrencyChangeNotice extends StatelessWidget {
  const _CurrencyChangeNotice({
    required this.from,
    required this.to,
    required this.offered,
    required this.confirmed,
    required this.onConfirmed,
  });

  final String from;
  final String to;
  final bool offered;
  final bool confirmed;
  final ValueChanged<bool> onConfirmed;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: AppRadius.fieldAll,
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Changing this person’s currency affects future transactions only.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.colors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Existing transactions will remain unchanged. This account’s history '
            'stays recorded in $from, exactly as it was entered, and its balance '
            'is still reported in $from. New entries will default to $to.',
            style: TextStyle(fontSize: 12, height: 1.45, color: palette.inkMuted),
          ),
          if (offered) ...[
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: () => onConfirmed(!confirmed),
              borderRadius: AppRadius.fieldAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    // A 44pt target: this sits in the thumb zone of a phone.
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Checkbox(
                        value: confirmed,
                        onChanged: (value) => onConfirmed(value ?? false),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Yes, use $to for new transactions.',
                        style: TextStyle(fontSize: 12.5, color: context.colors.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.money.inkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final accent = tone ?? context.colors.primary;

    return Material(
      color: selected
          ? (tone == null ? palette.accentSoft : accent.withValues(alpha: 0.12))
          : palette.sunken,
      borderRadius: AppRadius.fieldAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.fieldAll,
        child: Container(
          height: 46,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.fieldAll,
            border: Border.all(
              color: selected ? accent : palette.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: selected ? accent : palette.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
