import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/catalogue.dart';
import '../../core/demo.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../widgets/app_page.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

/// Demo versus full Accounic (docs/demo.md).
///
/// The one screen in the demo that is about the demo. It exists to answer a
/// question the visitor will otherwise answer wrongly — "is this all of it?" —
/// and it answers it by being specific: here is the line, here is which side of
/// it each capability sits on.
///
/// It is a comparison, so it is laid out as one: two columns, the same rows in
/// both, aligned. Not three cards of features, and not a wall of ticks against
/// a wall of crosses — a row where only one side has anything in it is a row
/// that says nothing about the product, only about the demo.
///
/// On a phone the two columns become two labelled lines under each capability.
/// The comparison survives; only its geometry changes.
class DemoScreen extends ConsumerWidget {
  const DemoScreen({super.key});

  /// The line, capability by capability.
  ///
  /// Every left-hand entry is something the visitor can go and do right now
  /// through the real engine. Every right-hand entry is the same capability
  /// without the demo's ceiling on it.
  static const _rows = <({String capability, String demo, String full})>[
    (
      capability: 'Dashboard',
      demo: 'Receivable, payable, net and recent activity',
      full: 'The same, plus per-currency breakdowns and trends',
    ),
    (
      capability: 'People and accounts',
      demo: 'View, open, add and edit accounts',
      full: 'Archiving, retraction, opening balances, account currencies',
    ),
    (
      capability: 'Transactions',
      demo: 'Record, edit and retract entries',
      full: 'The same engine, with transfers between accounts',
    ),
    (
      capability: 'Settlement',
      demo: 'Settle a balance, in part or in full',
      full: 'Settle a chosen transaction, and decide what a part payment pays',
    ),
    (
      capability: 'Activity',
      demo: 'The full feed, filtered by kind',
      full: 'The same feed, exportable as a journal',
    ),
    (
      capability: 'Currency',
      demo: 'Figures in one currency',
      full: 'An account per currency, entry in another, recorded rates',
    ),
    (
      capability: 'Reports',
      demo: 'Not in the demo',
      full: 'PDF statements, workspace exports, spreadsheets and backups',
    ),
    (
      capability: 'Your data',
      demo: 'Sample data, reset whenever you like',
      full: 'Your own private books, on Android and Windows as well',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = context.isCompact;

    return AppPage(
      title: 'Demo and full Accounic',
      subtitle: 'What you are using now, and what the complete application adds.',
      children: [
        const _Hero(),
        const SizedBox(height: AppSpacing.xxl),

        const SectionHeader('Side by side'),
        SectionCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: [
              if (!compact) const _ColumnLabels(),
              for (final (index, row) in _rows.indexed) ...[
                if (index > 0 || !compact)
                  Divider(height: 1, color: context.money.line),
                _ComparisonRow(row: row, stacked: compact),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xxl),

        SectionHeader(
          'Everything Accounic does',
          trailing: '$kCapabilityInDemo of $kCapabilityTotal in this demo',
        ),
        // The full inventory, collapsed. A visitor exploring a restricted
        // surface will otherwise decide the restricted surface is the product,
        // and a flat list of a hundred lines is a document nobody reads — so
        // each group opens on its own, and the count on the right says what is
        // inside before it is opened.
        for (final group in kAccounicCapabilities) ...[
          _CapabilityCard(group: group),
          const SizedBox(height: AppSpacing.md),
        ],

        const SizedBox(height: AppSpacing.lg),
        const _DemoOnYourDevice(),
        const SizedBox(height: AppSpacing.lg),
        const _Cta(),
      ],
    );
  }
}

/// One group of the inventory, collapsed until it is asked for.
///
/// The tick is the honest part of this screen. A line the demo can reach is
/// ticked in the receivable green the product uses for money owed TO you, and a
/// line it cannot is left with an open ring — present, named, not yours yet. A
/// list where nothing was ticked would read as a paywall; a list with no marks
/// at all would not answer the question the visitor came with.
class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.group});

  final CapabilityGroup group;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return SectionCard(
      title: group.title,
      collapsible: true,
      hint: '${group.demoCount}/${group.capabilities.length} in demo',
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (group.note != null) ...[
            Text(
              group.note!,
              style: TextStyle(fontSize: 13, height: 1.5, color: palette.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          for (final capability in group.capabilities)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: capability.inDemo
                        ? Icon(
                            AppIcons.check,
                            size: AppIconSize.sm,
                            color: palette.receivable,
                          )
                        : Container(
                            width: AppIconSize.sm,
                            height: AppIconSize.sm,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: palette.lineStrong, width: 1.5),
                            ),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          capability.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: capability.inDemo
                                ? context.colors.onSurface
                                : palette.inkMuted,
                          ),
                        ),
                        if (capability.detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            capability.detail!,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: palette.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The opening statement. One paragraph, and it says the true thing rather than
/// the flattering one: this is the real application on sample data.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return SectionCard(
      raised: true,
      brandRule: true,
      padding: context.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AccounicMark(size: 34),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'This is Accounic, running on sample data',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              const StatusChip('Demo', tone: StatusTone.partial),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Every figure on every screen was computed by the same accounting '
            'engine a paid installation uses. Nothing here is a mock-up: when '
            'you record a transaction, it is recorded; when you settle a '
            'balance, the balance is settled.\n\n'
            'What the demo does is narrow the surface. A handful of capabilities '
            'are held back for the full application, and each of them says so '
            'when you reach it.',
            style: TextStyle(fontSize: 13.5, height: 1.65, color: palette.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// The two column headings, on a window wide enough to have columns.
class _ColumnLabels extends StatelessWidget {
  const _ColumnLabels();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
      color: context.money.inkFaint,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(flex: 4, child: SizedBox()),
          Expanded(flex: 5, child: Text('DEMO', style: style)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: 5, child: Text('FULL ACCOUNIC', style: style)),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.row, required this.stacked});

  final ({String capability, String demo, String full}) row;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    const name = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
    final body = TextStyle(fontSize: 13, height: 1.5, color: palette.inkMuted);

    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.capability, style: name),
            const SizedBox(height: AppSpacing.md),
            _Side(label: 'Demo', text: row.demo, muted: true),
            const SizedBox(height: AppSpacing.sm),
            _Side(label: 'Full', text: row.full, muted: false),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(row.capability, style: name)),
          Expanded(flex: 5, child: Text(row.demo, style: body)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    AppIcons.check,
                    size: AppIconSize.sm,
                    color: palette.receivable,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    row.full,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One side of a stacked comparison, on a phone.
class _Side extends StatelessWidget {
  const _Side({required this.label, required this.text, required this.muted});

  final String label;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: muted ? palette.inkFaint : palette.receivable,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: muted ? palette.inkMuted : context.colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// The demo, for the device the visitor is actually holding.
///
/// The demo is built for all three platforms, so "does this work on my desktop"
/// is a question it can answer rather than promise. The asset is resolved from
/// the current release and offered as a DIRECT download — a releases page asks
/// somebody evaluating a product to read a list of files and guess which one is
/// theirs, which is a small insult at exactly the wrong moment.
///
/// Draws nothing when there is nothing to offer: no release, no demo asset for
/// this platform, no network. An absent card is a better answer than a button
/// that goes somewhere unhelpful.
class _DemoOnYourDevice extends ConsumerWidget {
  const _DemoOnYourDevice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final download = ref.watch(demoDownloadProvider).valueOrNull;
    if (download == null) return const SizedBox.shrink();

    final palette = context.money;

    return SectionCard(
      padding: context.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Try the demo on ${download.platform}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The same demo, built for ${download.platform} from the same code as '
            'this page. It signs in to a demo account exactly as this one does.',
            style: TextStyle(fontSize: 13.5, height: 1.6, color: palette.inkMuted),
          ),
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(download.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(AppIcons.download, size: AppIconSize.sm),
              label: Text('Download the ${download.platform} demo '
                  '(${download.version})'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                side: BorderSide(color: palette.line),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one call to action on the screen, and the last thing on it.
///
/// It asks rather than offers, because that is how access actually works: an
/// administrator enables the account (db/migrations/0030), and until they do
/// there is no download that would help. A button reading "Get full Accounic"
/// would be promising something this screen cannot deliver.
class _Cta extends StatelessWidget {
  const _Cta();

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return SectionCard(
      brandRule: true,
      padding: context.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Getting the full application',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            kAccessGrantedBy,
            style: TextStyle(fontSize: 13.5, height: 1.6, color: palette.inkMuted),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Three steps and no button, because there is no button that would be
          // honest here. Nothing this screen can launch grants access: the only
          // thing that does is an administrator changing one column
          // (db/migrations/0030), and the useful thing to give the visitor is
          // therefore the knowledge of who to ask and what happens next.
          const _Step(1, 'Ask your Accounic administrator for full access.'),
          const _Step(
            2,
            'They enable this account from Administration — the same account, '
            'the same email and password.',
          ),
          const _Step(
            3,
            'Everything on this page opens, on the books you have been working '
            'in. Nothing is copied and nothing is lost.',
          ),
        ],
      ),
    );
  }
}

/// One numbered step of how access is granted.
class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              shape: BoxShape.circle,
              border: Border.all(color: palette.accentLine),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: context.colors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
