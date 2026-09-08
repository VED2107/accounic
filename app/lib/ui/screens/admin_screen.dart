import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/demo.dart';
import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../sheets/sheet_scaffold.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';

/// Administration (context.md §25), the Flutter half of the web app's `/admin`.
///
/// Deliberately small and deliberately plain, like the web one: a few system
/// counters, a searchable directory of accounts, and the one switch this client
/// can actually operate — enabling and disabling an account. There is no way to
/// open another user's books; admins manage accounts, not ledgers, and RLS would
/// refuse anyway.
///
/// **Everything else on the web /admin page is missing on purpose, and cannot
/// be added here.** Creating a user, resetting a password, deleting an account
/// and changing administrator rights all require the service-role key:
/// `grant_admin` and `revoke_admin` are granted to `service_role` alone, with
/// `authenticated` explicitly revoked in `0007_admin.sql`. A distributable
/// binary cannot hold that key — anyone could extract it and bypass RLS
/// entirely — and this client has no server to put the call behind. So those
/// operations live on the server-rendered web app, where the key never leaves
/// the machine. See docs/decisions.md §21 and §31.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

/// Which accounts the directory is showing.
///
/// A filter on one list rather than a second screen: administration already has
/// an account list, and "the demo ones" is a question about that list. The
/// database applies it (`admin_list_users(p_demo_only)`), so paging and the
/// count stay honest.
enum _Audience {
  all('All accounts', null),
  demo('Demo', true),
  real('Real', false);

  const _Audience(this.label, this.demoOnly);

  final String label;
  final bool? demoOnly;
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _search = TextEditingController();
  String _query = '';
  _Audience _audience = _Audience.all;

  AdminUsersQuery get _args => (query: _query, demoOnly: _audience.demoOnly);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _setActive(AdminUser user, bool active) async {
    final confirmed = await confirm(
      context,
      title: active ? 'Enable ${user.name}?' : 'Disable ${user.name}?',
      body: active
          ? 'They will be able to sign in again. Their ledger is untouched either way.'
          : 'They will be signed out and cannot sign in until you enable them again. '
              'Nothing in their ledger is deleted.',
      confirmLabel: active ? 'Enable' : 'Disable',
      destructive: !active,
      icon: active ? AppIcons.success : AppIcons.locked,
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(ledgerRepositoryProvider).setUserActive(user.id, active);
      ref.invalidate(adminUsersProvider);
      ref.invalidate(systemInfoProvider);
      if (mounted) {
        showMessage(context, active ? '${user.name} can sign in again.' : '${user.name} is disabled.');
      }
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    }
  }

  /// Demo account to real account (db/migrations/0030).
  ///
  /// Two steps, deliberately. The first states what will happen and what will
  /// be kept — including the books, in the counts this account actually holds,
  /// because "their demo data becomes their real data" is the part an
  /// administrator must not learn afterwards. The second is the result, with
  /// the address of the full application to hand on.
  ///
  /// Every guard that matters is in the RPC. This dialog is courtesy; the
  /// database is the rule.
  Future<void> _convert(AdminUser user) async {
    final name = user.name.isEmpty ? user.email : user.name;

    final ok = await confirm(
      context,
      destructive: false,
      icon: AppIcons.tiers,
      title: 'Convert $name to a real account?',
      confirmLabel: 'Convert to real user',
      body: 'They keep this account, this email and this password — only their '
          'demo status changes.\n\n'
          'This account holds ${user.peopleCount} '
          '${user.peopleCount == 1 ? 'person' : 'people'} and '
          '${user.transactionCount} '
          '${user.transactionCount == 1 ? 'transaction' : 'transactions'}. '
          'Nothing is deleted: the sample books they built while trying Accounic '
          'become the opening state of their real books.\n\n'
          'Demo restrictions are lifted and they can use the full application.',
    );
    if (!ok || !mounted) return;

    try {
      final converted = await ref.read(ledgerRepositoryProvider).convertDemoUser(user.id);
      ref.invalidate(adminUsersProvider);
      ref.invalidate(systemInfoProvider);
      if (!mounted) return;
      await _converted(converted);
    } on Failure catch (failure) {
      if (mounted) showMessage(context, failure.message, error: true);
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    }
  }

  /// The result, and the one thing the administrator needs next: the link to
  /// hand over. Copy rather than open, because an administrator sending this to
  /// a customer wants it on the clipboard, not in a browser tab of their own.
  Future<void> _converted(ConvertedUser user) async {
    final open = await confirm(
      context,
      destructive: false,
      icon: AppIcons.success,
      title: '${user.name.isEmpty ? user.email : user.name} is a real user',
      confirmLabel: 'Copy full app link',
      cancelLabel: 'Done',
      body: 'They now have the complete application, with the same email and '
          'password.\n\n'
          'Their books came through intact: ${user.peopleKept} '
          '${user.peopleKept == 1 ? 'person' : 'people'} and '
          '${user.transactionsKept} '
          '${user.transactionsKept == 1 ? 'transaction' : 'transactions'}.\n\n'
          '$kFullAccounicUrl',
    );
    if (!open || !mounted) return;

    await Clipboard.setData(const ClipboardData(text: ''));
    await Clipboard.setData(ClipboardData(text: kFullAccounicUrl));
    if (mounted) showMessage(context, 'The full Accounic link is on your clipboard.');
  }

  /// Marks a real account as a demo one (db/migrations/0031).
  ///
  /// The other direction has its own flow, because turning a visitor into a
  /// customer deserves the confirmation that names their books. This direction
  /// is the administrator correcting a record, and it says plainly what the
  /// person on the other end will notice: a narrower application, and not one
  /// figure moved.
  Future<void> _markDemo(AdminUser user) async {
    final name = user.name.isEmpty ? user.email : user.name;

    final ok = await confirm(
      context,
      icon: AppIcons.tiers,
      title: 'Make $name a demo account?',
      confirmLabel: 'Make it a demo account',
      body: 'They keep this account, this email, this password and every one of '
          'their records — the application simply offers them less until an '
          'administrator changes it back.\n\n'
          'Reports, transfers, opening balances and multi-currency close for '
          'them. Nothing in their ledger is deleted, moved or converted.',
    );
    if (!ok || !mounted) return;

    try {
      await ref.read(ledgerRepositoryProvider).setUserDemo(user.id, true);
      ref.invalidate(adminUsersProvider);
      ref.invalidate(systemInfoProvider);
      if (mounted) showMessage(context, '$name is now a demo account.');
    } on Failure catch (failure) {
      if (mounted) showMessage(context, failure.message, error: true);
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull;
    final users = ref.watch(adminUsersProvider(_args));
    final info = ref.watch(systemInfoProvider);

    // The screen is guarded by the router and by every RPC it calls; this is the
    // third layer, and the only one the user ever sees.
    if (me != null && !me.isAdmin) {
      return const AppPage(
        title: 'Administration',
        children: [
          Card(
            child: EmptyState(
              icon: AppIcons.locked,
              title: 'Administrator access is required',
              description: 'This area manages accounts. Your own ledger is unaffected.',
            ),
          ),
        ],
      );
    }

    return AppPage(
      title: 'Administration',
      subtitle: 'Accounting data stays private to each user. '
          'Administrators manage accounts, not ledgers.',
      // Reached from the rail on a desktop, where there is nothing to go back
      // to, and pushed from the profile on a phone, where there is.
      // `Navigator.of(context).canPop()`, not go_router's `context.canPop()`:
      // the latter asserts when there is no GoRouter above it, which makes the
      // screen impossible to pump in a widget test. The Navigator answers the
      // same question — is there something under this route — without the
      // dependency, and the pop itself still goes through go_router, which only
      // runs when this branch decided there was something to pop.
      leading: Navigator.of(context).canPop()
          ? AppIconAction(
              icon: AppIcons.back,
              tooltip: 'Back',
              onPressed: () => context.pop(),
            )
          : null,
      width: ContentWidth.standard,
      onRefresh: () async {
        ref.invalidate(adminUsersProvider);
        ref.invalidate(systemInfoProvider);
      },
      children: [
        Reveal(
          child: info.when(
            loading: () => const _StatsSkeleton(),
            error: (error, _) => ErrorNote.forError(
              error,
              what: 'the system summary',
              onRetry: () => ref.invalidate(systemInfoProvider),
            ),
            data: (data) => _SystemStats(info: data),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Reveal(
          delay: const Duration(milliseconds: 60),
          child: SectionCard(
            title: 'Accounts',
            action: users.maybeWhen(
              data: (page) => Text(
                '${page.total} ${page.total == 1 ? 'account' : 'accounts'}',
                style: TextStyle(fontSize: 12, color: context.money.inkFaint),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.sm),
                        child: Icon(
                          AppIcons.search,
                          size: AppIconSize.sm,
                          color: context.money.inkFaint,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      hintText: 'Search name or email',
                    ),
                  ),
                ),
                // Demo accounts are ordinary accounts with a flag, so they live
                // in the ordinary list behind a filter rather than on a screen
                // of their own (db/migrations/0030).
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Segmented<_Audience>(
                    value: _audience,
                    segments: [
                      for (final audience in _Audience.values)
                        (value: audience, label: audience.label),
                    ],
                    onChanged: (audience) => setState(() => _audience = audience),
                  ),
                ),
                users.when(
                  loading: () => const SkeletonList(rows: 4),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: ErrorNote.forError(
                      error,
                      what: 'the user list',
                      onRetry: () => ref.invalidate(adminUsersProvider),
                    ),
                  ),
                  data: (page) => page.users.isEmpty
                      ? EmptyState(
                          icon: AppIcons.noResults,
                          title: switch (_audience) {
                            _Audience.demo => 'No demo accounts',
                            _Audience.real => 'No real accounts match',
                            _Audience.all => 'No accounts match',
                          },
                          description: _audience == _Audience.demo && _query.isEmpty
                              ? 'Demo accounts are created in the web app, and every '
                                  'anonymous visitor to the online demo becomes one.'
                              : 'Try a different name or email address.',
                        )
                      : Stagger(
                          children: [
                            for (final (index, user) in page.users.indexed)
                              _UserRow(
                                user: user,
                                isSelf: user.id == me?.id,
                                divider: index < page.users.length - 1,
                                onSetActive: (active) => _setActive(user, active),
                                onConvert: () => _convert(user),
                                onMarkDemo: () => _markDemo(user),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Reveal(
          delay: const Duration(milliseconds: 100),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  AppIcons.locked,
                  size: AppIconSize.xs,
                  color: context.money.inkFaint,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Creating an account and resetting a password need a server key that '
                  'no installed app may carry, so both live in the web app.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.money.inkFaint,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SystemStats extends StatelessWidget {
  const _SystemStats({required this.info});

  final SystemInfo info;

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, String?)>[
      // The demo count rides on the users tile rather than taking a seventh.
      // Six divides evenly into two, three and six; seven leaves an orphan cell
      // at every width the strip is laid out at.
      (
        'Users',
        '${info.usersActive}/${info.usersTotal}',
        info.usersDemo == 0 ? 'active' : 'active · ${info.usersDemo} demo',
      ),
      ('Administrators', '${info.admins}', null),
      ('People', '${info.peopleTotal}', null),
      ('Transactions', '${info.transactionsTotal}', null),
      ('Settlements', '${info.settlementsTotal}', null),
      ('Database', info.databaseSize, null),
    ];

    // Two columns on a phone, three on a tablet, all six in a row on a desktop.
    // Laid out by count rather than by a fixed cell width, so the row always
    // divides evenly and never leaves one orphan on a second line.
    final columns = switch (context.breakpoint) {
      Breakpoint.compact => 2,
      Breakpoint.medium => 3,
      _ => 6,
    };

    return SectionCard(
      child: Column(
        children: [
          for (var row = 0; row * columns < stats.length; row++) ...[
            if (row > 0) Divider(height: 1, color: context.money.line),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) VerticalDivider(width: 1, color: context.money.line),
                    Expanded(
                      child: row * columns + column < stats.length
                          ? _Stat(stat: stats[row * columns + column])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.stat});

  final (String, String, String?) stat;

  @override
  Widget build(BuildContext context) {
    final (label, value, note) = stat;
    final palette = context.money;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w700,
              color: palette.inkFaint,
            ),
          ),
          const SizedBox(height: AppSpacing.sm - 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.display(18),
                ),
              ),
              if (note != null) ...[
                const SizedBox(width: AppSpacing.xs + 1),
                // Flexible, like the value beside it. The note was a bare Text,
                // which is fine while every note is one short word and overflows
                // the tile the moment one is not — as "active · 2 demo" did, by
                // 56px, in a two-column phone layout.
                Flexible(
                  child: Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    final columns = switch (context.breakpoint) {
      Breakpoint.compact => 2,
      Breakpoint.medium => 3,
      _ => 6,
    };

    return SectionCard(
      child: Row(
        children: [
          for (var i = 0; i < columns; i++)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md + 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 68, height: 10),
                    SizedBox(height: AppSpacing.sm),
                    Skeleton(width: 44, height: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One account. The contextual menu is the only way to change anything about
/// it, and every item in that menu goes through a confirmation that names the
/// consequence — administration is where a mis-tap costs someone their access.
class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.divider,
    required this.onSetActive,
    required this.onConvert,
    required this.onMarkDemo,
  });

  final AdminUser user;
  final bool isSelf;
  final bool divider;
  final ValueChanged<bool> onSetActive;
  final VoidCallback onConvert;
  final VoidCallback onMarkDemo;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final name = user.name.isEmpty ? user.email : user.name;

    return Column(
      children: [
        Hoverable(
          cursor: SystemMouseCursors.basic,
          builder: (context, hovered) => HoverFill(
            color: hovered ? palette.sunken : Colors.transparent,
            child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                // A disabled account is drawn as state rather than identity —
                // it is the one thing about the row that matters more than who
                // it is.
                Opacity(
                  opacity: user.isActive ? 1 : 0.55,
                  child: Avatar(name, size: 38),
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
                              user.name.isEmpty ? '—' : user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: user.isActive
                                    ? context.colors.onSurface
                                    : palette.inkMuted,
                              ),
                            ),
                          ),
                          if (user.isAdmin) ...[
                            const SizedBox(width: AppSpacing.sm),
                            const StatusChip('Admin', tone: StatusTone.partial),
                          ],
                          if (user.isDemo) ...[
                            const SizedBox(width: AppSpacing.sm - 2),
                            StatusChip(
                              user.isAnonymous ? 'Demo - anonymous' : 'Demo',
                              tone: StatusTone.muted,
                            ),
                          ],
                          if (!user.isActive) ...[
                            const SizedBox(width: AppSpacing.sm - 2),
                            const StatusChip('Disabled', tone: StatusTone.muted),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
                      ),
                      if (!context.isCompact) ...[
                        const SizedBox(height: 3),
                        Text(
                          [
                            '${user.peopleCount} '
                                '${user.peopleCount == 1 ? 'person' : 'people'}',
                            '${user.transactionCount} '
                                '${user.transactionCount == 1 ? 'transaction' : 'transactions'}',
                            if (user.lastSignInAt != null)
                              'seen ${relativeTime(user.lastSignInAt!)}',
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                        ),
                      ],
                    ],
                  ),
                ),
                // Self-management is blocked here and again in the RPC: an admin
                // who disables themselves locks everyone out of administration.
                if (isSelf)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Text(
                      'You',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.inkFaint,
                      ),
                    ),
                  )
                else
                  _AccountMenu(
                    user: user,
                    hovered: hovered,
                    onSetActive: onSetActive,
                    onConvert: onConvert,
                    onMarkDemo: onMarkDemo,
                  ),
              ],
            ),
            ),
          ),
        ),
        if (divider) Divider(height: 1, color: palette.line, indent: AppSpacing.lg),
      ],
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.user,
    required this.hovered,
    required this.onSetActive,
    required this.onConvert,
    required this.onMarkDemo,
  });

  final AdminUser user;
  final bool hovered;
  final ValueChanged<bool> onSetActive;
  final VoidCallback onConvert;
  final VoidCallback onMarkDemo;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    Widget item(IconData icon, String label, {Color? tone, String? note}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppIconSize.sm, color: tone ?? palette.inkMuted),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 13.5, color: tone ?? context.colors.onSurface),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: TextStyle(fontSize: 12, height: 1.35, color: palette.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

    return PopupMenuButton<String>(
      tooltip: 'Manage account',
      position: PopupMenuPosition.under,
      color: palette.raised,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.fieldAll,
        side: BorderSide(color: palette.lineStrong),
      ),
      icon: AnimatedContainer(
        duration: Motion.fast,
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? palette.raised : Colors.transparent,
          borderRadius: AppRadius.fieldAll,
          border: Border.all(color: hovered ? palette.line : Colors.transparent),
        ),
        child: Icon(
          AppIcons.more,
          size: AppIconSize.sm,
          color: hovered ? context.colors.onSurface : palette.inkFaint,
        ),
      ),
      onSelected: (value) => switch (value) {
        'disable' => onSetActive(false),
        'enable' => onSetActive(true),
        'convert' => onConvert(),
        'mark-demo' => onMarkDemo(),
        _ => null,
      },
      itemBuilder: (context) => [
        // Offered only on a demo account, and shown-but-disabled on an
        // anonymous one with the reason - the same rule the administrator role
        // follows below. An anonymous visitor has no email and no password, so
        // converting them would produce a real account nobody can sign in to,
        // and admin_convert_demo_user() refuses it outright.
        if (user.isDemo) ...[
          PopupMenuItem(
            value: 'convert',
            enabled: !user.isAnonymous,
            child: item(
              AppIcons.tiers,
              'Convert to real user',
              tone: user.isAnonymous ? palette.inkFaint : palette.receivable,
              note: user.isAnonymous
                  ? 'Anonymous visitors have no sign-in to keep'
                  : 'Keeps their account, their password and their books',
            ),
          ),
          const PopupMenuDivider(),
        ] else ...[
          // The other direction. An administrator creates both kinds of account
          // and is allowed to have changed their mind; the ledger is untouched
          // either way (db/migrations/0031).
          PopupMenuItem(
            value: 'mark-demo',
            child: item(
              AppIcons.tiers,
              'Make it a demo account',
              note: 'Narrows what they can reach. Keeps every record',
            ),
          ),
          const PopupMenuDivider(),
        ],
        if (user.isActive)
          PopupMenuItem(
            value: 'disable',
            child: item(AppIcons.locked, 'Disable account', tone: palette.payable),
          )
        else
          PopupMenuItem(
            value: 'enable',
            child: item(AppIcons.success, 'Enable account', tone: palette.receivable),
          ),
        // Shown, disabled, with the reason — the same rule the person menu
        // follows (docs/decisions.md §29). `grant_admin` and `revoke_admin` are
        // granted to `service_role` alone; `authenticated` is explicitly revoked
        // in 0007_admin.sql. This client holds the anon key and has no server to
        // put a service-role call behind, so the operation is not merely
        // unavailable here — it is impossible here, and the web app is where it
        // lives.
        PopupMenuItem(
          value: 'admin-role',
          enabled: false,
          child: item(
            AppIcons.admin,
            user.isAdmin ? 'Revoke administrator' : 'Make administrator',
            tone: palette.inkFaint,
            note: 'Administrator roles are changed in the web app',
          ),
        ),
      ],
    );
  }
}
