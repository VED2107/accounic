import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import 'brand.dart';

/// The demo mode indicator (docs/demo.md).
///
/// One strip across the top of the application, above everything, on every
/// screen. It has to be permanent — a visitor who forgets they are in a demo
/// will read a gate as a bug — and it has to be quiet, because it is present on
/// every screen the product is being judged on.
///
/// So it is the thinnest chrome in the app: the brand's own hairline, the
/// product's name with one word after it, and a text link. No colour field, no
/// icon, no dismissal. It reads as a masthead rather than as a warning, which
/// is the correct register: being in the demo is not a problem the visitor
/// needs to fix.
///
/// Shown whenever the experience is the restricted one — the demo build, or a
/// demo account signing in to the Android or Windows application. A full
/// account never sees it, on any platform.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoRestrictedProvider)) return const SizedBox.shrink();

    final palette = context.money;
    final compact = context.isCompact;

    return Material(
      color: palette.sunken,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The ramp, at one pixel. The same hairline SectionCard's brand
            // rule uses, and the only decoration on the strip.
            Container(
              height: 1.5,
              decoration: const BoxDecoration(gradient: AccounicColors.brandGradient),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm - 2,
                AppSpacing.sm,
                AppSpacing.sm - 2,
              ),
              child: Row(
                children: [
                  BrandText(
                    'Accounic',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.colors.onSurface,
                    ),
                  ),
                  Text(
                    '  ·  Demo',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.inkFaint,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Sample data. Nothing here is a real account.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.inkFaint),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  TextButton(
                    onPressed: () => context.go('/demo'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Points at the demo screen, which explains how access is
                    // granted — not at a download the visitor cannot use yet.
                    child: const Text('About full Accounic'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
