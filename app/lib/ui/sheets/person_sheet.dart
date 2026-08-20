import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import 'sheet_scaffold.dart';

/// Create or edit a person / business (context.md §5).
///
/// Returns the saved person, or null if cancelled.
Future<Person?> showPersonSheet(
  BuildContext context,
  WidgetRef ref, {
  Person? person,
}) {
  return showAppSheet<Person>(
    context,
    (context) => _PersonSheet(person: person),
  );
}

class _PersonSheet extends ConsumerStatefulWidget {
  const _PersonSheet({this.person});

  final Person? person;

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  late final _name = TextEditingController(text: widget.person?.name ?? '');
  late final _phone = TextEditingController(text: widget.person?.phone ?? '');
  late final _email = TextEditingController(text: widget.person?.email ?? '');
  late final _address = TextEditingController(text: widget.person?.address ?? '');
  late final _notes = TextEditingController(text: widget.person?.notes ?? '');
  late PartyType _type = widget.person?.type ?? PartyType.person;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.person != null;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _email, _address, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(ledgerRepositoryProvider);
      final person = _isEdit
          ? await repository.updatePerson(
              personId: widget.person!.id,
              name: name,
              type: _type,
              phone: _clean(_phone),
              email: _clean(_email),
              address: _clean(_address),
              notes: _clean(_notes),
            )
          : await repository.createPerson(
              name: name,
              type: _type,
              phone: _clean(_phone),
              email: _clean(_email),
              address: _clean(_address),
              notes: _clean(_notes),
            );

      ref.refreshLedger(personId: person.id);
      if (mounted) Navigator.of(context).pop(person);
    } on Failure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: _isEdit ? 'Edit details' : 'Add person or business',
      error: _error,
      busy: _saving,
      primaryLabel: _isEdit ? 'Save changes' : 'Add person',
      onPrimary: _save,
      children: [
        _Labelled(
          label: 'Name',
          child: TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'Rahul Traders',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: 16),

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
                if (option != PartyType.values.last) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Labelled(
                label: 'Phone',
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    hintText: '+91 98200 11223',
                    counterText: '',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Labelled(
                label: 'Email',
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'Optional'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _Labelled(
          label: 'Address',
          child: TextField(
            controller: _address,
            maxLength: 500,
            decoration: const InputDecoration(hintText: 'Optional', counterText: ''),
          ),
        ),
        const SizedBox(height: 16),

        _Labelled(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: 'Payment terms, reference numbers, anything worth remembering.',
              counterText: '',
            ),
          ),
        ),
      ],
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
        Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.colors.primaryContainer : context.colors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? context.colors.primary : context.colors.outline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: selected ? context.colors.primary : context.colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
