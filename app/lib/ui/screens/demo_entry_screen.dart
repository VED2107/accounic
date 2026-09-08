import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import 'login_screen.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

/// The demo's door (docs/demo.md).
///
/// It stands where [LoginScreen] stands in a real build, and is deliberately
/// the same door: the mark at full size, the wordmark, the product's one
/// sentence, and a single control. A visitor who later installs Accounic should
/// recognise the screen they arrive at.
///
/// The one thing it adds is an answer to "what am I about to be signed in to?",
/// because a button that signs you in to something unnamed is a button most
/// people do not press. Three lines, then the door.
class DemoEntryScreen extends ConsumerStatefulWidget {
  const DemoEntryScreen({super.key});

  @override
  ConsumerState<DemoEntryScreen> createState() => _DemoEntryScreenState();
}

class _DemoEntryScreenState extends ConsumerState<DemoEntryScreen> {
  bool _busy = false;
  String? _error;

  /// Whether the visitor asked for the email-and-password form instead.
  ///
  /// There are two ways in and they are for two different people. A visitor who
  /// followed a link wants the anonymous door: no typing, a workspace of their
  /// own, gone when they close the tab. Someone who was GIVEN an account — from
  /// a deck, a mail, a landing page — wants to sign in to the same books they
  /// were shown last time, and needs the ordinary form to do it.
  ///
  /// So the second door is the product's real [LoginScreen], not a copy of it.
  bool _signIn = false;

  Future<void> _enter() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(demoRepositoryProvider).enter();
      // The router's redirect reacts to the auth stream, exactly as it does
      // after a real sign-in. No manual navigation here either.
      ref.invalidate(meProvider);
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    if (_signIn) {
      return Stack(
        children: [
          const LoginScreen(
            footnote: 'Signing in with a shared demo account shows the same '
                'sample books each time.\n'
                'It cannot reach anyone else’s data.',
          ),
          // Back to the anonymous door. Positioned over the login screen rather
          // than built into it, so the screen a real installation ships stays
          // exactly the screen a real installation ships.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: TextButton.icon(
                onPressed: () => setState(() => _signIn = false),
                icon: const Icon(AppIcons.back, size: AppIconSize.sm),
                label: const Text('Back'),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AccounicMark(size: 56)),
                  const SizedBox(height: 18),
                  const Center(child: AccounicLogo(markSize: 0, fontSize: 24)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Know who owes you, who you owe, and what is settled.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5, color: palette.inkMuted),
                  ),
                  const SizedBox(height: AppSpacing.xxl + AppSpacing.xs),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            ErrorNote(_error!),
                            const SizedBox(height: AppSpacing.lg),
                          ],

                          const Text(
                            'Try the demo',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'A sample workspace with five accounts already in it. '
                            'Record a transaction, settle a balance, and watch the '
                            'books move.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: palette.inkMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          const _Point('No account, no email, nothing to install'),
                          const _Point('Your own private copy of the sample books'),
                          const _Point('Sample data only — no real money anywhere'),

                          const SizedBox(height: AppSpacing.xl),
                          FilledButton(
                            onPressed: _busy ? null : _enter,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Enter demo'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => setState(() => _signIn = true),
                      child: const Text('I have a demo account'),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'This is a limited demonstration of Accounic.\n'
                    'The full application keeps your own books.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.6, color: palette.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of what the visitor is getting. Ticked rather than bulleted: each
/// of these is a reassurance, and a tick reads as one where a dot does not.
class _Point extends StatelessWidget {
  const _Point(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              AppIcons.check,
              size: AppIconSize.sm,
              color: context.money.receivable,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
