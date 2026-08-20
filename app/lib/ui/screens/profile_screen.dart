import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../sheets/sheet_scaffold.dart';
import '../widgets/common.dart';

/// Profile (context.md §4). Deliberately small: identity, currency, password.
///
/// The email address is not editable here — it is administrative state, changed
/// by an admin (context.md §25).
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

  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _business.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(ledgerRepositoryProvider).updateProfile(
            name: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            businessName: _business.text.trim().isEmpty ? null : _business.text.trim(),
            currency: _currency,
          );
      ref.invalidate(meProvider);
      ref.refreshLedger();
      if (mounted) showMessage(context, 'Your details are saved.');
    } on Failure catch (failure) {
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _PasswordSheet(),
    );
    if ((changed ?? false) && mounted) {
      showMessage(context, 'Your password has been changed.');
    }
  }

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      destructive: false,
      title: 'Sign out?',
      confirmLabel: 'Sign out',
      body: 'You will need your email and password to sign back in.',
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Profile')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorNote.forError(error, onRetry: () => ref.invalidate(meProvider)),
        ),
        data: (me) {
          if (me == null) return const SizedBox.shrink();

          // Seed the controllers once; later rebuilds must not stomp on what the
          // user is currently typing.
          if (!_loaded) {
            _name.text = me.name;
            _phone.text = me.phone ?? '';
            _business.text = me.businessName ?? '';
            _currency = _currencies.contains(me.currency) ? me.currency : 'INR';
            _loaded = true;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              PageBody(
                maxWidth: 620,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Avatar(me.name, size: 52, tone: AvatarTone.accent),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(me.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w600)),
                              Text(
                                '${me.email}${me.isAdmin ? ' · administrator' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(fontSize: 12.5, color: context.money.inkMuted),
                              ),
                              if (me.createdAt.isNotEmpty)
                                Text(
                                  'Joined ${fullDate(me.createdAt)}',
                                  style: TextStyle(
                                      fontSize: 12, color: context.money.inkFaint),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Your details',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              'Your email address is managed by your administrator.',
                              style:
                                  TextStyle(fontSize: 12.5, color: context.money.inkMuted),
                            ),
                            const SizedBox(height: 18),

                            if (_error != null) ...[
                              ErrorNote(_error!),
                              const SizedBox(height: 14),
                            ],

                            _Labelled(
                              label: 'Name',
                              child: TextField(controller: _name, maxLength: 120,
                                  decoration: const InputDecoration(counterText: '')),
                            ),
                            const SizedBox(height: 14),
                            _Labelled(
                              label: 'Phone',
                              child: TextField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                maxLength: 32,
                                decoration: const InputDecoration(
                                    hintText: 'Optional', counterText: ''),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _Labelled(
                              label: 'Business name',
                              child: TextField(
                                controller: _business,
                                maxLength: 120,
                                decoration: const InputDecoration(
                                    hintText: 'Optional', counterText: ''),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _Labelled(
                              label: 'Currency',
                              child: DropdownButtonFormField<String>(
                                value: _currency,
                                items: [
                                  for (final code in _currencies)
                                    DropdownMenuItem(value: code, child: Text(code)),
                                ],
                                onChanged: (value) =>
                                    setState(() => _currency = value ?? _currency),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Save details'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            onTap: _changePassword,
                            leading: const Icon(Icons.lock_outline),
                            title: const Text('Change password',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Choose something long',
                                style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                          Divider(height: 1, color: context.money.line),
                          ListTile(
                            onTap: _signOut,
                            leading: Icon(Icons.logout, color: context.money.payable),
                            title: Text('Sign out',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.money.payable,
                                )),
                          ),
                        ],
                      ),
                    ),

                    if (me.isAdmin) ...[
                      const SizedBox(height: 14),
                      Text(
                        'User administration lives in the web app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: context.money.inkFaint),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;

    // Same rules as the web client and the admin form, stated in one place each
    // so a user never meets two different definitions of a valid password.
    if (password.length < 10) {
      setState(() => _error = 'Use at least 10 characters.');
      return;
    }
    if (!RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      setState(() =>
          _error = 'Include an uppercase letter, a lowercase letter and a number.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'Those passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).changePassword(password);
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
      error: _error,
      busy: _busy,
      primaryLabel: 'Change password',
      onPrimary: _submit,
      children: [
        _Labelled(
          label: 'New password',
          child: TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'At least 10 characters'),
          ),
        ),
        const SizedBox(height: 14),
        _Labelled(
          label: 'Confirm password',
          child: TextField(
            controller: _confirm,
            obscureText: true,
            onSubmitted: (_) => _submit(),
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
