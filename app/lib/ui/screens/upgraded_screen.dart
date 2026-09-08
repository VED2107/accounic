import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/update_repository.dart';
import '../../providers.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

/// The end of the demo (docs/demo.md).
///
/// Shown in the demo build to an account an administrator has converted, in
/// place of the ledger. It is a door out, not a wall: their account is ready
/// and the product is waiting — it is simply not this page.
///
/// ---------------------------------------------------------------------------
/// WHY THE DEMO DOES NOT SIMPLY UNLOCK
///
/// Flutter Web ships as the demo and as nothing else. The real product is the
/// Android and Windows applications, and the web client in `web/`. So a real
/// account reaching the demo build is not somebody to quietly promote in place;
/// it is somebody in the wrong place, holding the right credentials.
///
/// Letting the demo become a full client for them would give the product two
/// web front ends that drift, and would leave a paying customer's books on the
/// deployment whose entire purpose is being a sample. Their account is real, so
/// this screen sends them to the application that is real too, with the same
/// email and password and the same books.
/// ---------------------------------------------------------------------------
class UpgradedScreen extends ConsumerWidget {
  const UpgradedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.money;
    final me = ref.watch(meProvider).valueOrNull;
    final downloads = ref.watch(fullDownloadsProvider).valueOrNull ?? const <DemoDownload>[];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AccounicMark(size: 52)),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    height: 2,
                    width: 96,
                    margin: const EdgeInsets.symmetric(horizontal: 160),
                    decoration: const BoxDecoration(
                      gradient: AccounicColors.brandGradient,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  const Center(
                    child: Text(
                      'Your account is ready',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    me == null
                        ? 'This is now a full Accounic account, and the demo is no '
                            'longer where it belongs.'
                        : '${me.email} is now a full Accounic account. The demo is '
                            'no longer where it belongs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.6, color: palette.inkMuted),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Install Accounic',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Sign in with the same email and password. Everything you '
                            'recorded is already there — nothing is copied and nothing '
                            'is lost.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: palette.inkMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          if (downloads.isEmpty)
                            // No release, no assets, or no network. Saying so
                            // beats a button that goes nowhere.
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: palette.sunken,
                                borderRadius: AppRadius.fieldAll,
                                border: Border.all(color: palette.line),
                              ),
                              child: Text(
                                'The download could not be reached from here. Ask your '
                                'administrator for the Android or Windows application.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: palette.inkFaint,
                                ),
                              ),
                            )
                          else
                            for (final (index, download) in downloads.indexed) ...[
                              if (index > 0) const SizedBox(height: AppSpacing.md),
                              // The first is this machine's platform, so it is
                              // the filled one; the other is offered plainly
                              // beside it rather than hidden.
                              if (index == 0)
                                FilledButton.icon(
                                  onPressed: () => launchUrl(
                                    Uri.parse(download.url),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  icon: const Icon(AppIcons.download, size: AppIconSize.sm),
                                  label: Text(
                                    'Download for ${download.platform} '
                                    '(${download.version})',
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                )
                              else
                                OutlinedButton.icon(
                                  onPressed: () => launchUrl(
                                    Uri.parse(download.url),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  icon: const Icon(AppIcons.download, size: AppIconSize.sm),
                                  label: Text(
                                    'Download for ${download.platform} '
                                    '(${download.version})',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    side: BorderSide(color: palette.line),
                                  ),
                                ),
                            ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(demoRepositoryProvider).leave();
                          ref.invalidate(meProvider);
                        } on Failure catch (failure) {
                          if (context.mounted) {
                            showMessage(context, failure.message, error: true);
                          }
                        }
                      },
                      child: const Text('Sign out'),
                    ),
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
