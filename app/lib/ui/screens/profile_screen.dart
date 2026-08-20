import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../motion.dart';
import '../sheets/sheet_scaffold.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';

/// Profile (context.md §4). Deliberately small: identity, currency, password.
///
/// The email address is not editable here — it is administrative state, changed
/// by an admin (context.md §25).
///
/// It is laid out as a settings page rather than a form. The difference matters:
/// a form asks to be filled in and submitted, and presents a permanently armed
/// Save button whether or not anything has changed. This asks to be *read*, and
/// only offers to save once something is different — which is why the save bar
/// is collapsed until then, and why it says what will happen if it is dismissed.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const _currencies = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'AUD', 'CAD', 'SGD'];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _business = TextEditingController();

  String _currency = 'INR';

  /// What was loaded, so "has anything changed?" is answered against the server
  /// state rather than against the last keystroke.
  ({String name, String phone, String business, String currency})? _original;

  SaveState _save = SaveState.idle;
  String? _formError;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _phone, _business]) {
      controller.addListener(_onEdited);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _business.dispose();
    super.dispose();
  }

  void _onEdited() {
    // Clearing the field error as soon as the field is touched: an error that
    // outlives the thing it described is noise.
    if (_nameError != null && _name.text.trim().isNotEmpty) {
      setState(() => _nameError = null);
    } else if (mounted) {
      setState(() {});
    }
  }

  bool get _dirty {
    final original = _original;
    if (original == null) return false;
    return _name.text.trim() != original.name ||
        _phone.text.trim() != original.phone ||
        _business.text.trim() != original.business ||
        _currency != original.currency;
  }

  void _discard() {
    final original = _original;
    if (original == null) return;
    setState(() {
      _name.text = original.name;
      _phone.text = original.phone;
      _business.text = original.business;
      _currency = original.currency;
      _nameError = null;
      _formError = null;
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      Haptics.warning();
      setState(() => _nameError = 'Your name cannot be empty.');
      return;
    }

    setState(() {
      _save = SaveState.saving;
      _formError = null;
    });

    try {
      await ref.read(ledgerRepositoryProvider).updateProfile(
            name: name,
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            businessName: _business.text.trim().isEmpty ? null : _business.text.trim(),
            currency: _currency,
          );

      // The currency is a display setting for every figure in the app, so a
      // change to it has to reach every screen, not just this one.
      ref.invalidate(meProvider);
      ref.refreshLedger();

      if (!mounted) return;
      Haptics.success();
      setState(() {
        _original = (
          name: name,
          phone: _phone.text.trim(),
          business: _business.text.trim(),
          currency: _currency,
        );
        _save = SaveState.saved;
      });

      // Hold the confirmation long enough to be read, then go quiet again.
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) setState(() => _save = SaveState.idle);
    } on Failure catch (failure) {
      if (!mounted) return;
      Haptics.warning();
      setState(() {
        _formError = failure.message;
        _save = SaveState.idle;
      });
    }
  }

  Future<void> _changePassword() async {
    final changed = await showAppSheet<bool>(context, (context) => const _PasswordSheet());
    if ((changed ?? false) && mounted) {
      showMessage(context, 'Your password has been changed.');
    }
  }

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      destructive: false,
      icon: AppIcons.signOut,
      title: 'Sign out?',
      confirmLabel: 'Sign out',
      body: 'You will need your email and password to sign back in. '
          'Nothing in your ledger is affected.',
    );
    if (!ok) return;

    try {
      await ref.read(authRepositoryProvider).signOut();
      ref.invalidate(meProvider);
    } on Failure catch (failure) {
      if (mounted) showMessage(context, failure.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(meProvider);

    return async.when(
      loading: () => const AppPage(
        title: 'Profile',
        width: ContentWidth.standard,
        children: [_ProfileSkeleton()],
      ),
      error: (error, _) => AppPage(
        title: 'Profile',
        width: ContentWidth.standard,
        children: [
          ErrorNote.forError(error, onRetry: () => ref.invalidate(meProvider)),
        ],
      ),
      data: (me) {
        if (me == null) return const AppPage(title: 'Profile', children: []);

        // Seed the controllers once; later rebuilds must not stomp on what the
        // user is currently typing.
        if (_original == null) {
          _name.text = me.name;
          _phone.text = me.phone ?? '';
          _business.text = me.businessName ?? '';
          _currency = _currencies.contains(me.currency) ? me.currency : 'INR';
          _original = (
            name: me.name,
            phone: me.phone ?? '',
            business: me.businessName ?? '',
            currency: _currency,
          );
        }

        return AppPage(
          title: 'Profile',
          subtitle: 'Your identity, the currency your ledger is kept in, and your password.',
          width: ContentWidth.standard,
          bottomPadding: 120,
          children: [
            Reveal(child: _IdentityCard(me: me)),
            const SizedBox(height: AppSpacing.xxl),

            if (_formError != null) ...[
              ErrorNote(_formError!),
              const SizedBox(height: AppSpacing.lg),
            ],

            Reveal(
              delay: const Duration(milliseconds: 40),
              child: SettingsGroup(
                title: 'Identity',
                description: 'How you appear in this workspace.',
                children: [
                  SettingsForm(
                    children: [
                      AppTextField(
                        label: 'Name',
                        controller: _name,
                        icon: AppIcons.person,
                        maxLength: 120,
                        error: _nameError,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        label: 'Phone',
                        controller: _phone,
                        icon: AppIcons.phone,
                        hint: 'Optional',
                        keyboardType: TextInputType.phone,
                        maxLength: 32,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            Reveal(
              delay: const Duration(milliseconds: 80),
              child: SettingsGroup(
                title: 'Business',
                description: 'Shown alongside your name where there is room for it.',
                children: [
                  SettingsForm(
                    children: [
                      AppTextField(
                        label: 'Business name',
                        controller: _business,
                        icon: AppIcons.business,
                        hint: 'Optional',
                        maxLength: 120,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            Reveal(
              delay: const Duration(milliseconds: 120),
              child: SettingsGroup(
                title: 'Currency',
                description: 'Every figure in the app is shown in this currency.',
                children: [
                  SettingsForm(
                    children: [
                      AppDropdown<String>(
                        label: 'Currency',
                        value: _currency,
                        icon: AppIcons.currency,
                        items: [
                          for (final code in _currencies)
                            (code, '$code  ·  ${currencySymbol(code).trim()}'),
                        ],
                        onChanged: (value) => setState(() => _currency = value ?? _currency),
                        helper: 'Amounts already recorded are not converted — this changes '
                            'how they are displayed.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            Reveal(
              delay: const Duration(milliseconds: 160),
              child: SettingsGroup(
                title: 'Security',
                children: [
                  SettingsRow(
                    icon: AppIcons.locked,
                    title: 'Change password',
                    subtitle: 'At least 10 characters, with a number and both cases',
                    onTap: _changePassword,
                    divider: true,
                  ),
                  SettingsRow(
                    icon: AppIcons.signOut,
                    title: 'Sign out',
                    subtitle: 'On this device only',
                    tone: context.money.payable,
                    onTap: _signOut,
                  ),
                ],
              ),
            ),

            // The rail carries administration on a desktop width; on a phone
            // the bottom bar is full, so this is the way in.
            if (me.isAdmin) ...[
              const SizedBox(height: AppSpacing.xxl),
              Reveal(
                delay: const Duration(milliseconds: 200),
                child: SettingsGroup(
                  title: 'Administration',
                  children: [
                    SettingsRow(
                      icon: AppIcons.admin,
                      title: 'Accounts & access',
                      subtitle: 'Manage who can sign in — not what they can see',
                      onTap: () => context.go('/admin'),
                    ),
                  ],
                ),
              ),
            ],

            _SaveBar(
              visible: _dirty || _save != SaveState.idle,
              state: _save,
              onSave: _submit,
              onDiscard: _discard,
            ),
          ],
        );
      },
    );
  }
}

/// Who you are, above the settings that describe it.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Card(
      child: Padding(
        padding: context.cardPadding,
        child: Row(
          children: [
            Avatar(me.name, size: 54, tone: AvatarTone.accent),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          me.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.display(19),
                        ),
                      ),
                      if (me.isAdmin) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const StatusChip('Admin', tone: StatusTone.partial),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    me.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.inkMuted),
                  ),
                  if (me.createdAt.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Joined ${fullDate(me.createdAt)}',
                      style: TextStyle(fontSize: 12, color: palette.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The save affordance, which exists only while there is something to save.
///
/// It is the one control on the page that can change server state, so it is
/// also the one that gets the accent — and it arrives with an explanation
/// rather than sitting there permanently armed under an unchanged form.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.visible,
    required this.state,
    required this.onSave,
    required this.onDiscard,
  });

  final bool visible;
  final SaveState state;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.normal,
      curve: Motion.enter,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: Reveal(
                offset: 6,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: context.money.raised,
                    borderRadius: AppRadius.cardAll,
                    border: Border.all(color: context.money.lineStrong),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          state == SaveState.saved
                              ? 'Your details are saved.'
                              : 'You have unsaved changes.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: state == SaveState.saved
                                ? context.money.receivable
                                : context.money.inkMuted,
                          ),
                        ),
                      ),
                      if (state == SaveState.idle) ...[
                        TextButton(
                          onPressed: onDiscard,
                          style: TextButton.styleFrom(foregroundColor: context.money.inkMuted),
                          child: const Text('Discard'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      SaveButton(
                        state: state,
                        onPressed: onSave,
                        label: 'Save changes',
                        savedLabel: 'Saved',
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: context.cardPadding,
            child: const Row(
              children: [
                Skeleton(width: 54, height: 54, radius: 17),
                SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 150, height: 19),
                      SizedBox(height: AppSpacing.sm),
                      Skeleton(width: 200, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        for (var group = 0; group < 2; group++) ...[
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.md),
            child: Skeleton(width: 88, height: 11),
          ),
          Card(
            child: Padding(
              padding: context.cardPadding,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 60, height: 12),
                  SizedBox(height: AppSpacing.sm),
                  Skeleton(height: 46, radius: AppRadius.field),
                  SizedBox(height: AppSpacing.lg),
                  Skeleton(width: 60, height: 12),
                  SizedBox(height: AppSpacing.sm),
                  Skeleton(height: 46, radius: AppRadius.field),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ],
    );
  }
}

class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet();

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _reveal = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // Same rules as the web client and the admin form, stated in one place each
  // so a user never meets two different definitions of a valid password.
  static const _rules = [
    ('At least 10 characters', _lengthOk),
    ('An uppercase and a lowercase letter', _caseOk),
    ('A number', _digitOk),
  ];

  static bool _lengthOk(String value) => value.length >= 10;
  static bool _caseOk(String value) =>
      RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value);
  static bool _digitOk(String value) => RegExp(r'\d').hasMatch(value);

  Future<void> _submit() async {
    final password = _password.text;

    if (!_rules.every((rule) => rule.$2(password))) {
      Haptics.warning();
      setState(() => _error = 'That password does not meet the requirements below.');
      return;
    }
    if (password != _confirm.text) {
      Haptics.warning();
      setState(() => _error = 'Those passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).changePassword(password);
      Haptics.success();
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Change password',
      subtitle: 'You will stay signed in on this device.',
      icon: AppIcons.locked,
      error: _error,
      busy: _busy,
      primaryLabel: 'Change password',
      onPrimary: _submit,
      children: [
        AppTextField(
          label: 'New password',
          controller: _password,
          icon: AppIcons.locked,
          autofocus: true,
          obscureText: !_reveal,
          hint: 'At least 10 characters',
          textInputAction: TextInputAction.next,
          trailing: TextButton(
            onPressed: () => setState(() => _reveal = !_reveal),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_reveal ? 'Hide' : 'Show'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Requirements(password: _password.text),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Confirm password',
          controller: _confirm,
          icon: AppIcons.locked,
          obscureText: !_reveal,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

/// The password rules, ticking themselves off as they are met.
///
/// Rules a user only learns about by failing are rules that get failed twice.
class _Requirements extends StatelessWidget {
  const _Requirements({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, test) in _PasswordSheetState._rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.enter,
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: test(password) ? palette.receivableSoft : palette.sunken,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: test(password) ? palette.receivableLine : palette.line,
                    ),
                  ),
                  child: Icon(
                    AppIcons.check,
                    size: 10,
                    color: test(password) ? palette.receivable : Colors.transparent,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedDefaultTextStyle(
                  duration: Motion.fast,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: test(password) ? palette.inkMuted : palette.inkFaint,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
