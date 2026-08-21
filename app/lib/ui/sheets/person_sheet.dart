import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../widgets/forms.dart';
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
    // Phone and email share a line only where a line is wide enough to hold two
    // fields. On a phone that split leaves roughly 150px each, which is narrower
    // than the values they hold — a number wraps and an address truncates.
    final compact = context.isCompact;

    final phone = AppTextField(
      label: 'Phone',
      controller: _phone,
      icon: AppIcons.phone,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      maxLength: 32,
      hint: '+91 98200 11223',
    );

    final email = AppTextField(
      label: 'Email',
      controller: _email,
      icon: AppIcons.email,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      hint: 'Optional',
    );

    return SheetScaffold(
      title: _isEdit ? 'Edit details' : 'Add person or business',
      icon: _isEdit ? AppIcons.edit : AppIcons.addPerson,
      error: _error,
      busy: _saving,
      primaryLabel: _isEdit ? 'Save changes' : 'Add person',
      onPrimary: _save,
      children: [
        AppTextField(
          label: 'Name',
          controller: _name,
          autofocus: true,
          icon: AppIcons.person,
          textInputAction: TextInputAction.next,
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
        const SizedBox(height: AppSpacing.lg),

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
        const SizedBox(height: AppSpacing.lg),

        AppTextField(
          label: 'Address',
          controller: _address,
          icon: AppIcons.address,
          textInputAction: TextInputAction.next,
          maxLength: 500,
          hint: 'Optional',
        ),
        const SizedBox(height: AppSpacing.lg),

        AppTextField(
          label: 'Notes',
          controller: _notes,
          icon: AppIcons.note,
          maxLines: 3,
          maxLength: 2000,
          hint: 'Payment terms, reference numbers, anything worth remembering.',
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
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Material(
      color: selected ? palette.accentSoft : palette.sunken,
      borderRadius: AppRadius.fieldAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.fieldAll,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.fieldAll,
            border: Border.all(
              color: selected ? palette.accentLine : palette.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: selected ? context.colors.primary : palette.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
