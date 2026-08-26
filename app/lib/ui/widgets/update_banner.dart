import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/update_repository.dart';
import '../../providers.dart';

/// "There is a newer version" — one strip above the app, and nothing at all the
/// rest of the time.
///
/// A dialog on launch would be the wrong shape: an update is not urgent, and
/// interrupting someone opening their ledger to tell them so earns the reflex
/// that dismisses every dialog unread. This sits at the top, states the version
/// it found, opens the release, and can be dismissed for the session.
///
/// It appears only when the check actually found something newer. Current
/// installs, a machine with no network, a repository with no releases: all of
/// those render nothing, because [appUpdateProvider] is null for every one of
/// them.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  /// Dismissal lives for the session only. Persisting it would need a store
  /// keyed by version, and the honest behaviour of "you will be told again next
  /// time you open the app" is worth more than the setting it would take.
  bool _dismissed = false;

  Future<void> _open(AppRelease release) async {
    final uri = Uri.tryParse(release.openUrl);
    if (uri == null) return;
    // Failing to launch a browser is not worth an error dialog in a ledger:
    // the version is on screen either way and github.com is not a secret.
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Deliberately silent — see above.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final release = ref.watch(appUpdateProvider).valueOrNull;
    if (release == null) return const SizedBox.shrink();

    final palette = context.money;

    return Material(
      color: palette.accentSoft,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(AppIcons.download, size: AppIconSize.sm, color: context.colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Accounic ${release.version} is available.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _showDetails(release),
                child: const Text('What’s new'),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilledButton(
                onPressed: () => _open(release),
                child: const Text('Update'),
              ),
              IconButton(
                tooltip: 'Not now',
                icon: Icon(AppIcons.close, size: AppIconSize.sm),
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(AppRelease release) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(release.name),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Text(
              release.notes ?? 'No release notes were published for this version.',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _open(release);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
