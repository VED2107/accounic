import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
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

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _search = TextEditingController();
  String _query = '';

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

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull;
    final users = ref.watch(adminUsersProvider(_query));
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
                      ? const EmptyState(
                          icon: AppIcons.noResults,
                          title: 'No accounts match',
                          description: 'Try a different name or email address.',
                        )
                      : Stagger(
                          children: [
                            for (final (index, user) in page.users.indexed)
                              _UserRow(
                                user: user,
                                isSelf: user.id == me?.id,
                                divider: index < page.users.length - 1,
                                onSetActive: (active) => _setActive(user, active),
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
      ('Users', '${info.usersActive}/${info.usersTotal}', 'active'),
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
                Text(note, style: TextStyle(fontSize: 12.5, color: palette.inkFaint)),
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
  });

  final AdminUser user;
  final bool isSelf;
  final bool divider;
  final ValueChanged<bool> onSetActive;

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
  });

  final AdminUser user;
  final bool hovered;
  final ValueChanged<bool> onSetActive;

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
        _ => null,
      },
      itemBuilder: (context) => [
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
