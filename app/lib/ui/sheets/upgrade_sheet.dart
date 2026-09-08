import 'package:flutter/material.dart';

import '../../core/demo.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../widgets/brand.dart';
import 'sheet_scaffold.dart';

/// The demo's one gate (docs/demo.md, core/demo.dart).
///
/// Every restricted capability arrives here, and it is the same panel every
/// time — a gate the visitor meets twice should not be a surprise the second
/// time. It is built on [SheetScaffold], so it is the product's own sheet: same
/// chrome, same entrance, same footer, bottom sheet on a phone and a centred
/// panel on a desktop.
///
/// Two decisions about how it reads.
///
/// There is no padlock. A lock says "you are not allowed", which is both untrue
/// — the visitor is welcome to everything the demo offers — and the wrong note
/// to end a demo on. The mark says whose product this is instead, and the panel
/// leads with what the capability DOES rather than with the fact that it is
/// unavailable.
///
/// And it names one capability, not the catalogue. The visitor tapped Export;
/// the first line they read is about exports. The list underneath is what else
/// comes with it, in the order a person would care about it.
Future<void> showUpgradeSheet(BuildContext context, DemoFeature feature) {
  return showAppSheet<void>(context, (context) => _UpgradeSheet(feature: feature));
}

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet({required this.feature});

  final DemoFeature feature;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return SheetScaffold(
      title: feature.title,
      subtitle: feature.blurb,
      // The panel closes and says nothing else. There is no link to follow and
      // no form to fill in: the only thing that opens the full application is
      // an administrator enabling this account, and the body says so. A button
      // that launched a mail client would throw the visitor out of the product
      // mid-evaluation, into an application that may not even be configured.
      primaryLabel: 'Continue demo',
      cancelLabel: 'Close',
      onPrimary: () => Navigator.of(context).maybePop(),
      children: [
        // The mark, at the size the login screen uses, over a hairline of the
        // brand ramp. The only decoration in the panel, and it is doing a job:
        // it says the thing being offered is this product, not an add-on.
        Center(
          child: Column(
            children: [
              const AccounicMark(size: 44),
              const SizedBox(height: AppSpacing.lg),
              Container(
                height: 2,
                width: 96,
                decoration: const BoxDecoration(
                  gradient: AccounicColors.brandGradient,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        Text(
          'You are exploring the Accounic demo, on sample data. The full '
          'application keeps your own books, and adds:',
          style: TextStyle(fontSize: 13.5, height: 1.6, color: palette.inkMuted),
        ),
        const SizedBox(height: AppSpacing.lg),

        for (final promise in kFullAccounicPromises)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Aligned to the cap height of the first line rather than
                // centred on the row: a two-line promise otherwise drags its
                // tick down to the middle and the column of ticks bends.
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    AppIcons.check,
                    size: AppIconSize.sm,
                    color: palette.receivable,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    promise,
                    style: const TextStyle(fontSize: 13.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.sunken,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Getting full access',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                kHowToGetFullAccess,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
