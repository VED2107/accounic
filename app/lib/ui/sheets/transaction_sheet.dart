import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/direction.dart';
import '../../core/icons.dart';
import '../../core/failure.dart';
import '../../core/theme.dart';
import '../../data/ledger_repository.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../../core/currencies.dart';
import '../widgets/amount_field.dart';
import '../widgets/common.dart';
import '../widgets/currency_field.dart';
import 'sheet_scaffold.dart';

/// Fast transaction entry (context.md §14).
///
/// Who → type → amount → date → note → save. The same five steps as the web
/// client, in the same order, because that is the order a person thinks about a
/// transaction.
///
/// Returns true when something was saved.
Future<bool> showTransactionSheet(
  BuildContext context,
  WidgetRef ref, {
  PersonRef? person,
  EditableTransaction? transaction,
  TxnType? defaultType,
}) async {
  final result = await showAppSheet<bool>(
    context,
    (context) => _TransactionSheet(
      person: person,
      transaction: transaction,
      defaultType: defaultType,
    ),
  );
  return result ?? false;
}

class PersonRef {
  const PersonRef(this.id, this.name, {this.currency});
  final String id;
  final String name;

  /// The account currency. Null falls back to the workspace's, which is what a
  /// person with none stored means (upgrade 1).
  final String? currency;
}

class EditableTransaction {
  const EditableTransaction({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.date,
    this.description,
    this.enteredAmountMinor,
    this.enteredCurrency,
  });

  final String id;
  final TxnType type;
  final int amountMinor;
  final String date;
  final String? description;

  /// What was originally typed, when that was not the account's currency. An
  /// edit reopens on those figures rather than on the converted ones, so a
  /// correction is made to what the user actually remembers (upgrade 2).
  final int? enteredAmountMinor;
  final String? enteredCurrency;
}

class _TransactionSheet extends ConsumerStatefulWidget {
  const _TransactionSheet({this.person, this.transaction, this.defaultType});

  final PersonRef? person;
  final EditableTransaction? transaction;
  final TxnType? defaultType;

  @override
  ConsumerState<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends ConsumerState<_TransactionSheet> {
  late PersonRef? _person = widget.person;
  late TxnType _type = widget.defaultType ?? widget.transaction?.type ?? TxnType.credit;
  late String _date = widget.transaction?.date ?? todayIso();
  late final TextEditingController _note =
      TextEditingController(text: widget.transaction?.description ?? '');

  int? _amount;
  bool _saving = false;
  String? _error;

  /// The currency the user is typing in. Follows the account until they say
  /// otherwise, because the ordinary case should cost no decisions.
  String? _entryCurrency;

  bool get _isEdit => widget.transaction != null;
  bool get _canSave => _amount != null && _person != null && !_saving;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;

    final account = _accountCurrency;
    final entry = _entryCurrency ?? account;
    // The keyboard has nothing left to contribute, and the result of this press
    // is behind it.
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(ledgerRepositoryProvider);
      final note = _note.text.trim().isEmpty ? null : _note.text.trim();

      // A cross-currency entry sends what was typed and the rate; the database
      // derives the account amount from them. The client never sends a
      // converted number it worked out itself (upgrade 2, 5).
      final foreign = entry != account;
      final rate =
          foreign ? await ref.read(ratesRepositoryProvider).rate(entry, account) : null;

      if (foreign && rate == null) {
        setState(() {
          _saving = false;
          _error = 'No $entry to $account rate is available. Enter the amount in '
              '$account instead — nothing has been saved.';
        });
        return;
      }

      if (_isEdit) {
        await repository.updateTransaction(
          transactionId: widget.transaction!.id,
          type: _type,
          amountMinor: foreign ? null : _amount,
          date: _date,
          description: note,
          enteredAmountMinor: foreign ? _amount : null,
          enteredCurrency: foreign ? entry : null,
          exchangeRateE9: rate?.rateE9,
          rateSource: rate?.source,
        );
      } else {
        await repository.createTransaction(
          personId: _person!.id,
          type: _type,
          amountMinor: foreign ? null : _amount,
          date: _date,
          description: note,
          enteredAmountMinor: foreign ? _amount : null,
          enteredCurrency: foreign ? entry : null,
          exchangeRateE9: rate?.rateE9,
          rateSource: rate?.source,
        );
      }

      ref.refreshLedger(personId: _person!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  /// The account's currency, which is the person's — not the workspace's.
  String get _accountCurrency {
    final person = _person?.currency;
    if (person != null && person.isNotEmpty) return normaliseCode(person);
    return normaliseCode(ref.read(currencyProvider));
  }

  @override
  Widget build(BuildContext context) {
    final account = _accountCurrency;
    final entry = _entryCurrency ?? account;

    return SheetScaffold(
      title: _isEdit ? 'Edit transaction' : 'Add transaction',
      subtitle: _isEdit ? 'Changes are checked against anything already settled.' : null,
      error: _error,
      primaryLabel: _isEdit ? 'Save changes' : 'Save transaction',
      onPrimary: _canSave ? _save : null,
      busy: _saving,
      children: [
        if (!_isEdit) ...[
          PersonPickerField(
            value: _person,
            onChanged: (person) => setState(() {
              _person = person;
              // Picking a dirham account means typing dirhams until the user
              // says otherwise.
              _entryCurrency = null;
            }),
          ),
          const SizedBox(height: 18),
        ],

        _TypeToggle(value: _type, onChanged: (type) => setState(() => _type = type)),
        const SizedBox(height: 18),

        AmountField(
          currency: entry,
          autofocus: _person != null,
          initial: widget.transaction?.enteredAmountMinor ?? widget.transaction?.amountMinor,
          onChanged: (minor) => setState(() => _amount = minor),
        ),
        const SizedBox(height: 12),

        CurrencyField(
          label: 'Entered in',
          value: entry,
          onChanged: (next) => setState(() => _entryCurrency = next),
          helper: entry == account
              ? 'This account is kept in $account'
              : 'Converted into $account when it is saved',
        ),

        if (entry != account) ...[
          const SizedBox(height: 12),
          ConversionNote(amountMinor: _amount, from: entry, to: account),
        ],
        const SizedBox(height: 18),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DateField(
                value: _date,
                onChanged: (value) => setState(() => _date = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Note',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _note,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Invoice #102',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Credit / Debit stated in the user's language (context.md §8).
///
/// Credit is money arriving from the person, which leaves the owner owing it
/// back; debit is money going the other way. Each option says what happened and
/// what it means for the balance, and the colour agrees with both: red for what
/// you owe, green for what you are owed. The mapping to stored values lives in
/// core/direction.dart and nowhere else.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.value, required this.onChanged});

  final TxnType value;
  final ValueChanged<TxnType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Type', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _TypeOption(
                selected: value.flow == MoneyFlow.personToOwner,
                onTap: () => onChanged(TxnType.forFlow(MoneyFlow.personToOwner)),
                icon: AppIcons.payable,
                flow: MoneyFlow.personToOwner,
                color: context.money.payable,
                background: context.money.payableSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypeOption(
                selected: value.flow == MoneyFlow.ownerToPerson,
                onTap: () => onChanged(TxnType.forFlow(MoneyFlow.ownerToPerson)),
                icon: AppIcons.receivable,
                flow: MoneyFlow.ownerToPerson,
                color: context.money.receivable,
                background: context.money.receivableSoft,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.flow,
    required this.color,
    required this.background,
  });

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final MoneyFlow flow;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final resting = context.money.sunken;

    return AnimatedContainer(
      duration: Motion.micro,
      curve: Motion.enter,
      decoration: BoxDecoration(
        color: selected ? background : resting,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        border: Border.all(
          color: selected ? color : context.money.line,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusField),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: selected ? color : context.colors.onSurface),
                    const SizedBox(width: 6),
                    Text(
                      flow.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: selected ? color : context.colors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  flow.meaning,
                  style: TextStyle(fontSize: 12, color: context.money.inkMuted),
                ),
                const SizedBox(height: 2),
                // What it does to the balance — the line that stops credit and
                // debit being mixed up.
                Text(
                  flow.effect,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Date', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: parseDbDate(value),
              firstDate: DateTime(2000),
              // Future-dated entries are rejected by the database, so the
              // picker will not offer one either.
              lastDate: DateTime.now(),
            );
            if (picked != null) onChanged(isoDate(picked));
          },
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Row(
              children: [
                Expanded(child: Text(friendlyDate(value))),
                Icon(AppIcons.date,
                    size: 16, color: context.money.inkFaint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Who?" — search existing people or create one inline (context.md §14).
class PersonPickerField extends ConsumerStatefulWidget {
  const PersonPickerField({super.key, required this.value, required this.onChanged});

  final PersonRef? value;
  final ValueChanged<PersonRef?> onChanged;

  @override
  ConsumerState<PersonPickerField> createState() => _PersonPickerFieldState();
}

class _PersonPickerFieldState extends ConsumerState<PersonPickerField> {
  final _controller = TextEditingController();
  String _query = '';
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createInline() async {
    final name = _query.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);

    try {
      final person = await ref.read(ledgerRepositoryProvider).createPerson(name: name);
      ref.refreshLedger();
      widget.onChanged(PersonRef(person.id, person.name, currency: person.currency));
    } on Failure catch (failure) {
      if (mounted) showMessage(context, failure.message, error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.value;

    if (selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Who?', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.money.sunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.colors.outline),
            ),
            child: Row(
              children: [
                Avatar(selected.name, size: 32, tone: AvatarTone.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selected.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _controller.clear();
                    setState(() => _query = '');
                    widget.onChanged(null);
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final results = ref.watch(searchProvider(_query));
    final recent = ref.watch(peopleProvider(
      (query: '', includeArchived: false, sort: PeopleSort.recent),
    ));

    final options = _query.trim().isEmpty
        ? (recent.valueOrNull ?? const <PersonBalance>[]).take(6).toList()
        : (results.valueOrNull?.people ?? const <PersonBalance>[]);

    final exactMatch = options.any(
      (option) => option.name.toLowerCase() == _query.trim().toLowerCase(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Who?', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          autofocus: true,
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            hintText: 'Search or type a new name',
            prefixIcon: Icon(AppIcons.search, size: AppIconSize.sm),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 216),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.money.line),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final option in options)
                ListTile(
                  dense: true,
                  leading: Avatar(option.name, size: 32),
                  title: Text(option.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: option.phone == null
                      ? null
                      : Text(option.phone!, style: const TextStyle(fontSize: 12)),
                  trailing: NetBadge(netMinor: option.netBalance, currency: option.currency),
                  onTap: () =>
                      widget.onChanged(PersonRef(
                        option.personId,
                        option.name,
                        currency: option.currency,
                      )),
                ),
              if (_query.trim().isNotEmpty && !exactMatch)
                ListTile(
                  dense: true,
                  leading: _creating
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.colors.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(AppIcons.add,
                              size: 17, color: context.colors.primary),
                        ),
                  title: Text('Add “${_query.trim()}” as a new person',
                      style: const TextStyle(fontSize: 14)),
                  onTap: _creating ? null : _createInline,
                ),
              if (options.isEmpty && _query.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Type a name to search or create.',
                      style: TextStyle(fontSize: 13, color: context.money.inkFaint),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
