import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/direction.dart';
import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/statement_download.dart';
import '../sheets/export_sheet.dart';
import '../../providers.dart';
import '../motion.dart';
import '../sheets/person_sheet.dart';
import '../sheets/settle_sheet.dart';
import '../sheets/transfer_sheet.dart';
import '../widgets/opening_balance_card.dart';
import '../sheets/sheet_scaffold.dart';
import '../sheets/transaction_sheet.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/currency_field.dart';

/// The metadata line under an account's name.
///
/// [currency] is what this person's figures are denominated in. [entry] is what
/// a new transaction with them defaults to, and is stated only when the two
/// differ — a person who has never switched has one currency and should be told
/// about exactly one (db/migrations/0013).
///
/// Status and last activity join it in v1.11.0: "is this account live, and when
/// did anything last happen on it" are the two questions a name raises that the
/// figure below does not answer, and both clients now answer them here.
String _personSubtitle(
  Person person,
  String currency, {
  String? entry,
  String? lastActivityAt,
}) =>
    [
      person.type.label,
      currency,
      if (entry != null && entry != currency) 'new entries in $entry',
      if (person.phone != null) person.phone!,
      person.isArchived ? 'Archived' : 'Active',
      if (lastActivityAt != null)
        'last activity ${relativeTime(lastActivityAt)}'
      else
        'no activity yet',
    ].join(' · ');

/// Which of the account's four questions is on screen.
enum PersonTab {
  overview('Overview'),
  transactions('Transactions'),
  settlements('Settlements'),
  activity('Activity');

  const PersonTab(this.label);
  final String label;
}

/// Person / business account — the screen the product is really about
/// (context.md §6, §16).
///
/// Credit and debit appear together, never in separate modules, and the net
/// position is the largest thing on the screen so "where do we stand?" needs no
/// arithmetic from the reader.
///
/// v1.11.0 rebuilt it, in step with the web client. It used to be one long
/// statement, and the comment here used to defend that: "the account is a
/// statement, not a set of tabs". That held while the account knew four things.
/// It knows a dozen now — cash in hand, the opening balance, the account
/// position, two per-currency breakdowns, four figures, the notes, the opening
/// book's own activity and the whole timeline — and stacking all of them above
/// the fold meant the answer to "where do we stand?" arrived buried in its own
/// working.
///
/// So: the position and its one action stand alone at the top, and everything
/// else is behind four tabs, because an account is four questions and a reader
/// only ever has one of them at a time.
///
///   Overview      what the position is made of, and the last few entries
///   Transactions  credits, debits and transfers
///   Settlements   money that actually moved
///   Activity      everything in order, including the opening book
///
/// The tab is local state rather than a route. On the web the tabs are links
/// because a URL there is worth having; here a route per tab would put three
/// extra entries in the back stack between the account and the list it came
/// from, which is the wrong trade on a phone.
class PersonScreen extends ConsumerStatefulWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen> {
  PersonTab _tab = PersonTab.overview;

  String get personId => widget.personId;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(personPageProvider(personId));
    final page = async.valueOrNull;

    return AppPage(
      title: page?.person.name ?? 'Account',
      subtitle: page == null
          ? null
          : _personSubtitle(
              page.person,
              page.currency,
              entry: page.defaultCurrency,
              lastActivityAt: page.balance.lastActivityAt,
            ),
      width: ContentWidth.standard,
      bottomPadding: context.isCompact ? 48 : 48,
      leading: _BackButton(),
      actions: [
        if (page != null) PersonMenu(page: page),
      ],
      onRefresh: () async => ref.refresh(personPageProvider(personId).future),
      children: switch (async) {
        AsyncError(:final error) => [
            ErrorNote.forError(
              error,
              what: 'this account',
              onRetry: () => ref.invalidate(personPageProvider(personId)),
            ),
          ],
        // Every figure on this screen is in the *account's* currency. The
        // workspace currency is only used for the equivalent under the
        // position, and as the fallback while the page is still loading.
        AsyncData(:final value) => _body(context, value, value.currency),
        _ => const [_PersonSkeleton()],
      },
    );
  }

  /// The account, in one screen: who, where we stand, what to do — then four
  /// tabs for everything that explains it.
  List<Widget> _body(BuildContext context, PersonPage page, String currency) {
    // `isSettlement` comes from the database's own entry_kind, so neither list
    // is inferred from a shape (db/migrations/0023).
    final transactions =
        page.timeline.where((entry) => !entry.isSettlement).toList();
    final settlements =
        page.timeline.where((entry) => entry.isSettlement).toList();

    return [
      // On a phone the app bar has only room for the name, so the identity row
      // is repeated here where the avatar and the metadata actually fit.
      if (context.isCompact) ...[
        Reveal(
          child: _Identity(
            person: page.person,
            currency: page.currency,
            entryCurrency: page.defaultCurrency,
            lastActivityAt: page.balance.lastActivityAt,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],

      Reveal(
        delay: const Duration(milliseconds: 30),
        child: _PositionCard(page: page, currency: currency),
      ),

      const SizedBox(height: AppSpacing.lg),

      // Four questions, one at a time. The control is the app's own segmented
      // one, so the selected segment slides between tabs rather than blinking
      // from one to the next — on this screen that movement is the only thing
      // telling the eye that what appeared below belongs to what was tapped.
      Segmented<PersonTab>(
        value: _tab,
        segments: [
          for (final tab in PersonTab.values) (value: tab, label: tab.label),
        ],
        onChanged: (tab) => setState(() => _tab = tab),
      ),

      const SizedBox(height: AppSpacing.lg),

      ...switch (_tab) {
        PersonTab.overview => _overview(context, page, currency),
        PersonTab.transactions => _entries(
            context,
            page,
            currency,
            entries: transactions,
            title: 'Transactions',
            note: 'Credits, debits and transfers. Settlements have their own '
                'tab, and the opening balance is not a transaction.',
            emptyTitle: 'No transactions here',
            emptyBody: 'Credits and debits you record with this account will '
                'appear on this tab.',
            actions: [
              ExportButton(person: page.person),
              const SizedBox(width: AppSpacing.sm),
              StatementButton(page: page),
            ],
          ),
        PersonTab.settlements => _entries(
            context,
            page,
            currency,
            entries: settlements,
            title: 'Settlements',
            note: 'Money that actually changed hands, and what it closed.',
            emptyTitle: 'Nothing settled yet',
            emptyBody: page.balance.outstandingReceivable > 0 ||
                    page.balance.outstandingPayable > 0
                ? 'Settle with ${_firstName(page)} and the record will appear '
                    'here.'
                : 'Settlements you record against this account will appear '
                    'here.',
          ),
        PersonTab.activity => [
            ..._entries(
              context,
              page,
              currency,
              entries: page.timeline,
              title: 'Activity',
              note: 'Every entry on this account in the order it happened.',
              emptyTitle: 'Nothing has happened yet',
              emptyBody: 'Everything you record with this account will show up '
                  'here.',
            ),
            if (page.openingActivity.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader('Against the opening balance'),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (row, entry) in page.openingActivity.indexed)
                      TimelineTile(
                        entry: entry,
                        page: page,
                        currency: currency,
                        divider: row < page.openingActivity.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ],
      },
    ];
  }

  static String _firstName(PersonPage page) => page.person.name.split(' ').first;

  /// What the headline is made of, then how it got there, then the last few
  /// entries — and only then the material a reader has to go looking for.
  List<Widget> _overview(BuildContext context, PersonPage page, String currency) {
    final tone = balanceTone(page.regular.positionMinor);
    final recent =
        page.timeline.where((entry) => !entry.isSettlement).take(4).toList();

    return [
      Reveal(
        child: SectionCard(
          child: _Figures(
            balance: page.balance,
            regular: page.regular,
            currency: currency,
            tone: tone,
          ),
        ),
      ),

      // The opening balance, in its own section — never a row in the history
      // (db/migrations/0019), and since 0022 never inside the cash-in-hand
      // figure either.
      if (page.balance.hasOpening) ...[
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: const Duration(milliseconds: 40),
          child: OpeningBalanceCard(page: page),
        ),
      ],

      // Looked up rather than read, so these are closed by default. Worth
      // drawing at all only when this account has traded in more than one
      // currency, or in one that is not its ledger denomination — otherwise the
      // headline already IS the original figure.
      if (_showByCurrency(page.regularByCurrency, page.currency)) ...[
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: const Duration(milliseconds: 55),
          child: CurrencyBreakdownCard(
            title: 'Cash in hand by currency',
            description: 'The original amounts entered for this account, kept '
                'in their own currency.',
            rows: page.regularByCurrency,
            baseCurrency: page.currency,
            opening: false,
            collapsible: true,
          ),
        ),
      ],

      if (_showByCurrency(page.openingByCurrency, page.currency)) ...[
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: const Duration(milliseconds: 60),
          child: CurrencyBreakdownCard(
            title: 'Opening balance by currency',
            description: 'What this account was carried in with, per currency, '
                'less whatever has settled.',
            rows: page.openingByCurrency,
            baseCurrency: page.currency,
            opening: true,
            collapsible: true,
          ),
        ),
      ],

      if (page.person.notes != null) ...[
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: const Duration(milliseconds: 70),
          child: Card(
            child: Padding(
              padding: context.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.note, size: AppIconSize.sm, color: context.money.inkFaint),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      page.person.notes!,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: context.money.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],

      const SizedBox(height: AppSpacing.xl),

      Row(
        children: [
          const Expanded(child: SectionHeader('Recent transactions')),
          if (recent.isNotEmpty)
            _TabLink(
              label: 'All',
              onTap: () => setState(() => _tab = PersonTab.transactions),
            ),
        ],
      ),

      if (recent.isEmpty)
        const Card(
          child: EmptyState(
            icon: AppIcons.quiet,
            title: 'Nothing recorded yet',
            description: 'Credits and debits with this account will appear here.',
          ),
        )
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (row, entry) in recent.indexed)
                TimelineTile(
                  entry: entry,
                  page: page,
                  currency: currency,
                  divider: row < recent.length - 1,
                ),
            ],
          ),
        ),
    ];
  }

  /// One tab's worth of ledger rows, grouped by day.
  List<Widget> _entries(
    BuildContext context,
    PersonPage page,
    String currency, {
    required List<TimelineEntry> entries,
    required String title,
    required String note,
    required String emptyTitle,
    required String emptyBody,
    List<Widget> actions = const [],
  }) {
    final groups = groupByDate(entries, (entry) => entry.entryDate);

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    note,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: context.money.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),

      if (entries.isEmpty)
        Card(
          child: EmptyState(
            icon: AppIcons.quiet,
            title: emptyTitle,
            description: emptyBody,
          ),
        )
      else
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.lg),
          Reveal(
            delay: Motion.stagger(index),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  group.label,
                  trailing: '${group.items.length} '
                      '${group.items.length == 1 ? 'entry' : 'entries'}',
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (row, entry) in group.items.indexed)
                        TimelineTile(
                          entry: entry,
                          page: page,
                          currency: currency,
                          divider: row < group.items.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
    ];
  }
}

/// "All →" beside a section heading, moving to another tab on this screen.
class _TabLink extends StatelessWidget {
  const _TabLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(AppIcons.forward, size: AppIconSize.xs, color: context.colors.primary),
          ],
        ),
      ),
    );
  }
}

/// A back affordance that matches the header's other controls.
class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppIconAction(
      icon: AppIcons.back,
      tooltip: 'Back',
      onPressed: () =>
          Navigator.of(context).canPop() ? context.pop() : context.go('/people'),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.person,
    required this.currency,
    required this.entryCurrency,
    this.lastActivityAt,
  });

  final Person person;

  /// When anything last happened on this account, for the metadata line.
  final String? lastActivityAt;

  /// What a new entry for this person defaults to. Shown only when it differs.
  final String entryCurrency;

  /// The account's currency, stated in the identity line rather than left to be
  /// inferred from a symbol (upgrade §10).
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Opacity(
          opacity: person.isArchived ? 0.6 : 1,
          child: Avatar(person.name, size: 48),
        ),
        const SizedBox(width: AppSpacing.md + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.display(20),
              ),
              const SizedBox(height: 2),
              Text(
                _personSubtitle(
                  person,
                  currency,
                  entry: entryCurrency,
                  lastActivityAt: lastActivityAt,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.money.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where we stand, what to do about it, and the four figures it is made of.
/// Whether a per-currency breakdown is worth drawing: more than one currency
/// with data, or a single one that is not the account's ledger currency.
bool _showByCurrency(List<CurrencyHalfBreakdown> rows, String ledgerCurrency) {
  final withData = rows.where((r) => r.hasData).toList();
  if (withData.length > 1) return true;
  return withData.length == 1 && withData.first.currency != ledgerCurrency;
}

/// Where we stand, and the one action that changes it.
///
/// v1.11.0 emptied this card out. It used to carry the headline, two secondary
/// figures, a workspace-currency equivalent, the action row AND the four
/// figures the position is made of — which meant the answer to "where do we
/// stand?" shared its card with three other answers and the reader had to pick.
/// The four figures moved to the Overview tab, the opening balance to one line
/// of prose, and what is left is the figure, what it means in words, and what
/// to do about it.
class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.page, required this.currency});

  final PersonPage page;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final balance = page.balance;
    // The headline is CASH IN HAND: the regular trading position, with the
    // opening balance taken out (db/migrations/0022). The opening balance is a
    // figure of its own, stated below and owned by its own section, and the two
    // are never added together into one number here.
    final regular = page.regular;
    final opening = page.openingPosition;
    final tone = balanceTone(regular.positionMinor);
    final first = page.person.name.split(' ').first;

    final color = switch (tone) {
      BalanceTone.receivable => palette.receivable,
      BalanceTone.payable => palette.payable,
      BalanceTone.settled => context.colors.onSurface,
    };

    return SectionCard(
      raised: true,
      brandRule: true,
      child: Padding(
        padding: EdgeInsets.all(context.isCompact ? AppSpacing.lg : AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The state as a word, not only as a colour (§29). Right-aligned,
            // where a statement puts it.
            Row(
              children: [
                Icon(AppIcons.net, size: AppIconSize.xs, color: palette.inkFaint),
                const SizedBox(width: AppSpacing.xs + 2),
                Text(
                  'CASH IN HAND',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: palette.inkFaint,
                  ),
                ),
                const Spacer(),
                _ToneBadge(tone: tone),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // The one figure this screen is about, centred and alone. Everything
            // that explains it is one tab away rather than one line below.
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // Animates when it changes — which is exactly when a settlement
                // has just been recorded on this screen.
                child: AnimatedMoney(
                  regular.positionMinor.abs(),
                  currency: currency,
                  color: color,
                  style: context.display(context.isCompact ? 36 : 44),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Text(
                switch (tone) {
                  BalanceTone.receivable => '$first owes you',
                  BalanceTone.payable => 'You owe $first',
                  BalanceTone.settled => 'Everything is settled',
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tone == BalanceTone.settled ? palette.inkFaint : color,
                ),
              ),
            ),

            // The same position in the workspace's currency. Context rather
            // than a figure anything settles against (upgrade §10).
            if (page.currency != page.baseCurrency && regular.positionMinor != 0) ...[
              const SizedBox(height: AppSpacing.xs + 2),
              Center(
                child: Text(
                  regular.positionBaseMinor == null
                      ? 'No ${page.currency} → ${page.baseCurrency} rate yet'
                      : '${formatApprox(regular.positionBaseMinor!.abs(), currency: page.baseCurrency)} at today\u2019s rate',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                ),
              ),
            ],

            // The opening balance in one line, not as a second figure beside
            // the first. Two large numbers on one card is how this header
            // started becoming a dashboard; the figures themselves are in the
            // Overview tab and in the opening book's own section.
            if (balance.hasOpening) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  'Opening balance of '
                  '${formatMoney(opening.positionMinor.abs(), currency: currency, base: currency)} '
                  'is accounted separately',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.4, color: palette.inkFaint),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.lg + 2),
            _ActionRow(page: page),
          ],
        ),
      ),
    );
  }
}

/// Which side of the ledger this account is on, as a word.
///
/// Deliberately not [StatusChip], whose tones mean a settlement's progress —
/// done, partial, none. This one means a direction, and the two must not be
/// confused by sharing a widget.
class _ToneBadge extends StatelessWidget {
  const _ToneBadge({required this.tone});

  final BalanceTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final (bg, fg, border, label) = switch (tone) {
      BalanceTone.receivable => (
          palette.receivableSoft,
          palette.receivable,
          palette.receivableLine,
          'RECEIVABLE',
        ),
      BalanceTone.payable => (
          palette.payableSoft,
          palette.payable,
          palette.payableLine,
          'PAYABLE',
        ),
      BalanceTone.settled => (palette.sunken, palette.inkFaint, palette.line, 'SETTLED'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: fg,
        ),
      ),
    );
  }
}

/// Settle, credit, debit.
///
/// Settle is the filled one whenever anything is outstanding — that is the
/// spec's headline interaction. Credit and debit are separate buttons rather
/// than one "add" that then asks which: the type is the decision, so it is the
/// click.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.page});

  final PersonPage page;

  Future<void> _add(BuildContext context, WidgetRef ref, MoneyFlow flow) async {
    final saved = await showTransactionSheet(
      context,
      ref,
      person: PersonRef(
        page.person.id,
        page.person.name,
        currency: page.currency,
        defaultCurrency: page.defaultCurrency,
      ),
      defaultType: TxnType.forFlow(flow),
    );
    if (saved && context.mounted) showMessage(context, 'Transaction recorded.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = page.balance;
    final palette = context.money;

    return Row(
      children: [
        if (balance.hasOutstanding) ...[
          Expanded(
            child: _Action(
              label: 'Settle',
              icon: AppIcons.settlement,
              filled: true,
              onTap: () async {
                final saved = await showSettleSheet(
                  context,
                  ref,
                  balance: balance,
                  openTransactions: page.openTransactions,
                );
                if (saved && context.mounted) {
                  showMessage(context, 'Settlement recorded.');
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
        ],
        Expanded(
          child: _Action(
            label: 'Credit',
            icon: AppIcons.payable,
            tint: palette.payable,
            onTap: () => _add(context, ref, MoneyFlow.personToOwner),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(
          child: _Action(
            label: 'Debit',
            icon: AppIcons.receivable,
            tint: palette.receivable,
            onTap: () => _add(context, ref, MoneyFlow.ownerToPerson),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        // Moving money between two of your own accounts is neither of the
        // above — nothing is owed differently overall, it just sits somewhere
        // else. Hence its own control rather than a mode of "add".
        Expanded(
          child: _Action(
            label: 'Transfer',
            icon: AppIcons.forward,
            onTap: () async {
              final saved = await showTransferSheet(context, ref, from: page.balance);
              if (saved && context.mounted) {
                showMessage(context, 'Transfer recorded. Both accounts updated.');
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Download this account as a PDF.
///
/// The statement is built on the device from `person_page()` — the same data
/// the screen above is drawn from, through the same row rules in
/// `core/statement.dart` — so the export cannot disagree with the screen it was
/// exported from. On Windows this opens the native save dialog; on Android the
/// file goes to the app's files directory, where a file manager can reach it.
///
/// Every outcome is reported. Cancelling the dialog says nothing went wrong,
/// because nothing did; a failure says what failed and that nothing was saved.
class StatementButton extends ConsumerStatefulWidget {
  const StatementButton({super.key, required this.page});

  final PersonPage page;

  @override
  ConsumerState<StatementButton> createState() => _StatementButtonState();
}

class _StatementButtonState extends ConsumerState<StatementButton> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      // Every row, not the screenful above: a statement that stopped at 30
      // entries would be a different document from the one the web exports.
      final full = await ref
          .read(ledgerRepositoryProvider)
          .personStatementPage(widget.page.person.id);

      final me = ref.read(meProvider).valueOrNull;
      final result = await const StatementDownloader().save(
        page: full,
        ownerName: me?.name ?? '',
      );

      if (!mounted) return;
      switch (result) {
        case StatementSaved(:final path, :final chosen):
          Haptics.success();
          showMessage(
            context,
            chosen ? 'Statement saved to $path' : 'Statement saved to $path',
          );
        case StatementSaveCancelled():
          // The user closed the dialog. Nothing to report and nothing wrong.
          break;
        case StatementSaveFailed(:final message):
          showMessage(context, message, error: true);
      }
    } on Failure catch (failure) {
      // The account could not be read — an expired session, no network, a
      // person that has since been deleted. The message says which.
      if (mounted) showMessage(context, failure.message, error: true);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'The statement could not be created. Nothing has been saved.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Hoverable(
      builder: (context, hovered) => Pressable(
        onTap: _busy ? null : _download,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? palette.raised : Colors.transparent,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: hovered ? palette.lineStrong : palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                SizedBox(
                  width: AppIconSize.xs,
                  height: AppIconSize.xs,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.inkMuted,
                  ),
                )
              else
                Icon(AppIcons.download, size: AppIconSize.xs, color: palette.inkMuted),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _busy ? 'Preparing…' : 'Download PDF',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: palette.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tint,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Hoverable(
      builder: (context, hovered) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: filled ? AccounicColors.actionGradient : null,
            color: filled
                ? null
                : hovered
                    ? palette.raised
                    : palette.sunken,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(
              color: filled
                  ? Colors.transparent
                  : hovered
                      ? (tint ?? palette.lineStrong).withValues(alpha: 0.5)
                      : palette.line,
            ),
            boxShadow: [
              if (hovered && filled)
                BoxShadow(
                  color: AccounicColors.actionGlow.withValues(alpha: 0.34),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: AppIconSize.sm,
                color: filled ? Colors.white : tint,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: filled ? Colors.white : context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edit, archive, delete.
///
/// Delete is always listed. Hiding it while the account has history meant the
/// menu simply had no Delete in it, which reads as the action being broken
/// rather than as being unavailable — and it left the person no route to the
/// thing they should do instead. It is shown greyed with the count that blocks
/// it and the alternative named, so the menu answers the question it raises.
class PersonMenu extends ConsumerWidget {
  const PersonMenu({super.key, required this.page});

  final PersonPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = page.person;
    final palette = context.money;

    Widget item(IconData icon, String label, {Color? tone, String? note}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: note == null ? 0 : 1),
              child: Icon(icon, size: AppIconSize.sm, color: tone ?? palette.inkMuted),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: tone ?? context.colors.onSurface,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: palette.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

    // The same test the server applies. `transactionCount` and `totalSettled`
    // both exclude voided rows, and `delete_person()` now counts live rows only,
    // so the two agree — which they did not before: a person whose transactions
    // had all been voided reported zero here, was offered Delete, and was then
    // refused by a server that was still counting the voided rows.
    final transactions = page.balance.transactionCount;
    final settled = page.balance.totalSettled;
    final deletable = transactions == 0 && settled == 0;

    return PopupMenuButton<String>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      color: palette.raised,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.fieldAll,
        side: BorderSide(color: palette.lineStrong),
      ),
      icon: Icon(AppIcons.more, size: AppIconSize.md, color: palette.inkMuted),
      onSelected: (value) async {
        final repository = ref.read(ledgerRepositoryProvider);

        switch (value) {
          case 'edit':
            await showPersonSheet(
              context,
              ref,
              person: person,
              openingMinor: page.balance.openingMinor,
            );

          case 'archive':
          case 'restore':
            final archiving = value == 'archive';
            final ok = await confirm(
              context,
              destructive: false,
              icon: AppIcons.archive,
              title: archiving ? 'Archive ${person.name}?' : 'Restore ${person.name}?',
              confirmLabel: archiving ? 'Archive' : 'Restore',
              body: archiving
                  ? 'They are hidden from the people list and from your totals. '
                      'Every transaction and settlement is kept, and you can restore '
                      'them at any time.'
                  : 'They will appear in your people list and totals again.',
            );
            if (!ok) return;
            try {
              await repository.setPersonArchived(person.id, archiving);
              ref.refreshLedger(personId: person.id);
            } on Failure catch (failure) {
              if (context.mounted) showMessage(context, failure.message, error: true);
            }

          // The way back from an account entered wrong. A void, never a
          // delete: the rows stay, marked voided, which is exactly what makes
          // it safe enough to offer from a menu.
          case 'void-history':
            final ok = await confirm(
              context,
              icon: AppIcons.warning,
              title: 'Retract everything for ${person.name}?',
              confirmLabel: 'Retract all history',
              body: 'Every transaction and settlement on this account is marked '
                  'voided. The balance goes to zero and the entries disappear '
                  'from your dashboard and activity feed.\n\n'
                  'Nothing is deleted — they stay on this person’s own timeline, '
                  'marked voided, with their amounts and dates exactly as they '
                  'were. Undoing it means restoring entries one at a time.',
            );
            if (!ok) return;
            try {
              final counts = await repository.voidPersonHistory(
                person.id,
                reason: 'Retracted from the person screen',
              );
              ref.refreshLedger(personId: person.id);
              if (context.mounted) {
                final entries = counts.transactions + counts.settlements;
                showMessage(
                  context,
                  entries == 0
                      ? 'There was nothing left to retract.'
                      : '$entries ${entries == 1 ? 'entry' : 'entries'} retracted.',
                );
              }
            } on Failure catch (failure) {
              if (context.mounted) showMessage(context, failure.message, error: true);
            }

          case 'delete':
            final ok = await confirm(
              context,
              icon: AppIcons.delete,
              title: 'Delete ${person.name}?',
              confirmLabel: 'Delete',
              body: 'This cannot be undone. It is only possible because there are no '
                  'transactions on this account.',
            );
            if (!ok) return;
            try {
              await repository.deletePerson(person.id);
              ref.refreshLedger();
              if (context.mounted) context.pop();
            } on Failure catch (failure) {
              if (context.mounted) showMessage(context, failure.message, error: true);
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'edit', child: item(AppIcons.edit, 'Edit details')),
        PopupMenuItem(
          value: person.isArchived ? 'restore' : 'archive',
          child: item(AppIcons.archive, person.isArchived ? 'Restore' : 'Archive'),
        ),
        if (!deletable)
          PopupMenuItem(
            value: 'void-history',
            child: item(
              AppIcons.warning,
              'Retract all history',
              tone: palette.payable,
              note: 'Voids every entry — nothing is deleted',
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          enabled: deletable,
          child: item(
            AppIcons.delete,
            'Delete',
            tone: deletable ? palette.payable : palette.inkFaint,
            note: switch (deletable) {
              true => null,
              false when transactions > 0 =>
                '$transactions ${transactions == 1 ? 'transaction' : 'transactions'} '
                    'on this account — archive instead',
              false => 'A settlement is still recorded here — archive instead',
            },
          ),
        ),
      ],
    );
  }
}

/// One timeline row.
///
/// Tapping expands the actions for that row only — a toolbar on every line makes
/// a dense ledger unreadable (context.md §16). The expansion is animated so the
/// rows below it move rather than jump, which is what tells the eye the panel
/// belongs to the row it came out of.
class TimelineTile extends ConsumerStatefulWidget {
  const TimelineTile({
    super.key,
    required this.entry,
    required this.page,
    required this.currency,
    this.divider = true,
  });

  final TimelineEntry entry;
  final PersonPage page;
  final String currency;
  final bool divider;

  @override
  ConsumerState<TimelineTile> createState() => _TimelineTileState();
}

class _TimelineTileState extends ConsumerState<TimelineTile> {
  bool _open = false;
  bool _busy = false;

  Future<void> _void() async {
    final entry = widget.entry;
    final isTransaction = !entry.isSettlement;
    final isTransfer = entry.isTransfer;
    final other = entry.transferCounterpartyName ?? 'the other account';

    final ok = await confirm(
      context,
      icon: isTransaction ? AppIcons.delete : AppIcons.settlement,
      title: isTransfer
          ? 'Retract this transfer?'
          : isTransaction
              ? 'Void this transaction?'
              : 'Reverse this settlement?',
      confirmLabel: isTransfer
          ? 'Retract transfer'
          : isTransaction
              ? 'Void'
              : 'Reverse',
      body: isTransfer
          ? 'Both sides are retracted together. '
              '${formatMoney(entry.amountMinor, currency: widget.currency, base: widget.currency)} returns to '
              'this account, and the matching entry on $other is retracted with it. '
              'Nothing is deleted — both entries stay on both timelines, marked '
              'retracted.'
          : isTransaction
              ? 'The transaction stays in the timeline as history but stops counting '
                  'towards any balance. If it has already been settled, void those '
                  'settlements first.'
              : '${formatMoney(entry.amountMinor, currency: widget.currency, base: widget.currency)} goes back to '
                  'outstanding. The record stays in the timeline marked as reversed.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(ledgerRepositoryProvider);
      // A transfer leg is never retracted on its own: the whole transfer is,
      // and the other person's entry goes with it. The database refuses any
      // other arrangement, so this is the only call that can succeed.
      if (isTransfer) {
        await repository.voidTransfer(
          entry.transferId!,
          reason: 'Retracted from the person screen',
        );
      } else if (isTransaction) {
        await repository.voidTransaction(entry.id);
      } else {
        await repository.voidSettlement(entry.id);
      }
      Haptics.success();
      ref.refreshLedger(personId: widget.page.person.id);
    } on Failure catch (failure) {
      if (mounted) showMessage(context, failure.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final palette = context.money;

    final (background, foreground, border) = entry.isSettlement
        ? (palette.sunken, palette.inkMuted, palette.line)
        : entry.isReceivable
            ? (palette.receivableSoft, palette.receivable, palette.receivableLine)
            : (palette.payableSoft, palette.payable, palette.payableLine);

    final icon = entry.isSettlement
        ? AppIcons.settlement
        : entry.isReceivable
            ? AppIcons.receivable
            : AppIcons.payable;

    return Opacity(
      opacity: entry.isVoid ? 0.55 : 1,
      child: Column(
        children: [
          Hoverable(
            builder: (context, hovered) => AnimatedContainer(
              duration: Motion.fast,
              color: _open
                  ? palette.sunken
                  : hovered
                      ? palette.sunken
                      : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: border),
                        ),
                        child: Icon(icon, size: AppIconSize.sm, color: foreground),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    entry.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                if (entry.isVoid)
                                  const StatusChip('Voided', tone: StatusTone.muted)
                                // Settlement chips are meaningless on a
                                // transfer leg: it is not something the other
                                // party pays off.
                                else if (entry.isTransfer)
                                  const StatusChip('Transfer', tone: StatusTone.muted)
                                else if (entry.status == SettlementStatus.settled)
                                  const StatusChip('Settled', tone: StatusTone.done)
                                else if (entry.status == SettlementStatus.partial)
                                  StatusChip(
                                    '${formatMoney(entry.remainingMinor ?? 0, currency: widget.currency, base: widget.currency)} left',
                                    tone: StatusTone.partial,
                                  ),
                              ],
                            ),
                            if (entry.note != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                entry.note!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                              ),
                            ],
                            // The rate that links the two figures on the right,
                            // and whether a human chose either of them. Third
                            // and quietest: it must not compete with the amount
                            // (upgrade §11, §44, §45).
                            if (entry.enteredCurrency != null) ...[
                              const SizedBox(height: 2),
                              RateNote(
                                enteredMinor: entry.enteredAmountMinor,
                                enteredCurrency: entry.enteredCurrency,
                                rateE9: entry.exchangeRateE9,
                                rateSource: entry.exchangeRateSource,
                                accountCurrency: widget.currency,
                                conversionMode: entry.conversionMode,
                                autoConvertedMinor: entry.autoConvertedAmountMinor,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // The amount that was ENTERED leads, in the currency it
                      // was entered in — a dirham entry is 400 AED and says so.
                      // Under it, the one equivalent that adds something: the
                      // ledger figure when the entry was converted into this
                      // account, otherwise the workspace-currency figure for an
                      // account kept in a foreign currency. Never both, and
                      // never the equivalent alone (upgrade §44).
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(
                            entry.entryAmountMinorOr(widget.currency),
                            currency: entry.entryCurrencyOr(widget.currency),
                            base: widget.currency,
                            strikethrough: entry.isVoid,
                            tone: entry.isSettlement
                                ? MoneyTone.neutral
                                : entry.isReceivable
                                    ? MoneyTone.receivable
                                    : MoneyTone.payable,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          if (_equivalentOf(entry, widget.currency) case final it?)
                            Text(
                              formatApprox(it.minor, currency: it.currency),
                              style: TextStyle(fontSize: 12, color: palette.inkFaint),
                            ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedRotation(
                        duration: Motion.fast,
                        curve: Motion.enter,
                        turns: _open ? 0.5 : 0,
                        child: Icon(
                          AppIcons.expand,
                          size: AppIconSize.sm,
                          color: palette.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          AnimatedSize(
            duration: Motion.normal,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : _RowActions(
                    entry: entry,
                    page: widget.page,
                    currency: widget.currency,
                    busy: _busy,
                    onVoid: _void,
                  ),
          ),

          if (widget.divider)
            Divider(height: 1, color: palette.line, indent: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// What can be done to one entry, revealed under it.
class _RowActions extends ConsumerWidget {
  const _RowActions({
    required this.entry,
    required this.page,
    required this.currency,
    required this.busy,
    required this.onVoid,
  });

  final TimelineEntry entry;
  final PersonPage page;
  final String currency;
  final bool busy;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.money;

    return Container(
      width: double.infinity,
      color: palette.sunken,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              fullDate(entry.entryDate),
              if (!entry.isTransfer &&
                  !entry.isSettlement &&
                  (entry.remainingMinor ?? 0) > 0)
                '${formatMoney(entry.remainingMinor!, currency: currency, base: currency)} still outstanding',
            ].join('  ·  '),
            style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
          ),
          const SizedBox(height: AppSpacing.md),
          if (entry.isVoid)
            Text(
              'This entry was voided. It stays here as history and does not '
              'affect any balance.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.inkFaint),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                // A transfer offers neither: it is not settled by anybody,
                // and it is never edited one side at a time. Both restrictions
                // are enforced in the database as well — this is the affordance
                // agreeing with it.
                if (!entry.isTransfer &&
                    !entry.isSettlement &&
                    (entry.remainingMinor ?? 0) > 0)
                  _RowAction(
                    label: 'Settle this',
                    icon: AppIcons.settlement,
                    onTap: busy
                        ? null
                        : () async {
                            final saved = await showSettleSheet(
                              context,
                              ref,
                              balance: page.balance,
                              openTransactions: page.openTransactions,
                              presetTransactionId: entry.id,
                            );
                            if (saved && context.mounted) {
                              showMessage(context, 'Settlement recorded.');
                            }
                          },
                  ),
                if (!entry.isTransfer && !entry.isSettlement)
                  _RowAction(
                    label: 'Edit',
                    icon: AppIcons.edit,
                    onTap: busy
                        ? null
                        : () async {
                            final saved = await showTransactionSheet(
                              context,
                              ref,
                              person: PersonRef(
                                page.person.id,
                                page.person.name,
                                currency: page.currency,
                                defaultCurrency: page.defaultCurrency,
                              ),
                              transaction: EditableTransaction(
                                id: entry.id,
                                type: entry.txnType ?? TxnType.credit,
                                amountMinor: entry.amountMinor,
                                date: entry.entryDate,
                                description: entry.note,
                                // An edit reopens on what was actually typed,
                                // in the currency it was typed in — and on the
                                // override when there is one, so re-saving
                                // cannot silently restate the row.
                                enteredAmountMinor: entry.enteredAmountMinor,
                                enteredCurrency: entry.enteredCurrency,
                                conversionMode: entry.conversionMode,
                                autoConvertedAmountMinor: entry.autoConvertedAmountMinor,
                                exchangeRateE9: entry.exchangeRateE9,
                                exchangeRateSource: entry.exchangeRateSource,
                              ),
                            );
                            if (saved && context.mounted) {
                              showMessage(context, 'Transaction updated.');
                            }
                          },
                  ),
                _RowAction(
                  label: entry.isTransfer
                      ? 'Retract transfer'
                      : entry.isSettlement
                          ? 'Reverse'
                          : 'Void',
                  icon: AppIcons.delete,
                  tone: palette.payable,
                  onTap: busy ? null : onVoid,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tone,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final color = tone ?? context.colors.onSurface;

    return Hoverable(
      builder: (context, hovered) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
          decoration: BoxDecoration(
            color: hovered ? palette.raised : Colors.transparent,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: hovered ? palette.lineStrong : palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppIconSize.xs, color: color),
              const SizedBox(width: AppSpacing.sm - 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Credited, debited, settled, remaining — the four figures the position is made
/// of, laid out two by two so they fit a phone without shrinking.
/// The four figures under the headline.
///
/// Every one of them is the REGULAR half (db/migrations/0022): these sit
/// beneath a card headed "Cash in hand", so a total that quietly included the
/// opening balance would contradict the number it is printed under. The opening
/// book's own credit, debit and settled figures are in its own section.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.balance,
    required this.regular,
    required this.currency,
    required this.tone,
  });

  final PersonBalance balance;
  final PositionSplit regular;
  final String currency;
  final BalanceTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    Widget cell(String label, IconData? icon, int minor, MoneyTone moneyTone, Color? color) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md + 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: AppIconSize.xs, color: color ?? palette.inkFaint),
                      const SizedBox(width: AppSpacing.xs + 2),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    minor,
                    currency: currency,
                    base: currency,
                    tone: moneyTone,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );

    // The engine's total_credit is the owner-to-person direction, which the
    // product calls a debit — see docs/accounting-direction.md.
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cell(
                'Credited to you',
                AppIcons.payable,
                regular.debitMinor,
                regular.debitMinor > 0 ? MoneyTone.payable : MoneyTone.neutral,
                regular.debitMinor > 0 ? palette.payable : null,
              ),
              VerticalDivider(width: 1, color: palette.line),
              cell(
                'Debited to them',
                AppIcons.receivable,
                regular.creditMinor,
                regular.creditMinor > 0 ? MoneyTone.receivable : MoneyTone.neutral,
                regular.creditMinor > 0 ? palette.receivable : null,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.line),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cell(
                'Settled',
                AppIcons.settlement,
                regular.settledMinor,
                MoneyTone.neutral,
                null,
              ),
              VerticalDivider(width: 1, color: palette.line),
              cell(
                tone == BalanceTone.payable ? 'You will pay' : 'You will receive',
                AppIcons.net,
                tone == BalanceTone.payable
                    ? regular.payableMinor
                    : regular.receivableMinor,
                switch (tone) {
                  BalanceTone.payable => MoneyTone.payable,
                  BalanceTone.receivable => MoneyTone.receivable,
                  BalanceTone.settled => MoneyTone.neutral,
                },
                null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonSkeleton extends StatelessWidget {
  const _PersonSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: context.cardPadding,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 130, height: 11),
                    SizedBox(height: AppSpacing.md),
                    Skeleton(width: 190, height: 38),
                    SizedBox(height: AppSpacing.md),
                    Skeleton(width: 120, height: 13),
                    SizedBox(height: AppSpacing.xl),
                    Skeleton(height: 46, radius: AppRadius.field),
                  ],
                ),
              ),
              Divider(height: 1, color: context.money.line),
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(child: Skeleton(width: 100, height: 34)),
                    SizedBox(width: AppSpacing.xxl),
                    Expanded(child: Skeleton(width: 100, height: 34)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Card(child: SkeletonList(rows: 5)),
      ],
    );
  }
}

/// The one equivalent a timeline row shows under its headline figure.
///
/// The ledger figure when the entry was converted into this account — that is
/// what the balance is summed from — otherwise the workspace-currency figure,
/// for an account kept in a currency that is not the workspace's. Never both:
/// two approximations under one amount is not more honest, only noisier.
({int minor, String currency})? _equivalentOf(TimelineEntry entry, String ledgerCurrency) {
  final entryCurrency = entry.entryCurrencyOr(ledgerCurrency);
  if (entryCurrency != ledgerCurrency) {
    return (minor: entry.amountMinor, currency: ledgerCurrency);
  }
  final base = entry.baseCurrency;
  final baseMinor = entry.amountBaseMinor;
  if (base != null && base != ledgerCurrency && baseMinor != null) {
    return (minor: baseMinor, currency: base);
  }
  return null;
}

/// Export this account as data — a PDF report, a spreadsheet or a backup.
///
/// Sits beside the statement rather than replacing it: a statement is the
/// document you send someone, an export is the data you keep. Opening it from
/// here pre-selects this account, which is what someone standing on a person's
/// screen almost always wants.
class ExportButton extends ConsumerWidget {
  const ExportButton({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.money;

    return Hoverable(
      builder: (context, hovered) => Pressable(
        onTap: () => showExportSheet(context, ref, person: person),
        child: Semantics(
          button: true,
          label: 'Export ${person.name}',
          child: AnimatedContainer(
            duration: Motion.fast,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered ? palette.raised : Colors.transparent,
              borderRadius: AppRadius.fieldAll,
              border: Border.all(color: hovered ? palette.lineStrong : palette.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.note, size: AppIconSize.xs, color: palette.inkMuted),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Export',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
