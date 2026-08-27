import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../widgets/common.dart';

/// Global search (context.md §15).
///
/// People rank above transactions because that is nearly always what is being
/// looked for. The debounce lives in `searchProvider`, so a keystroke cancels
/// the pending request before it is sent.
Future<void> showSearchSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    // Above the shell, so the bottom bar and the docked `+` are not drawn over
    // the results. See showAppSheet.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _SearchSheet(),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(String personId) {
    Navigator.of(context).pop();
    context.push('/people/$personId');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(searchProvider(_query));
    final trimmed = _query.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search people, phone numbers or notes…',
                  prefixIcon: const Icon(AppIcons.search, size: AppIconSize.md),
                  suffixIcon: trimmed.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(AppIcons.close, size: AppIconSize.sm),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),

            Flexible(
              child: trimmed.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'Start typing to find a person or a transaction note.',
                        style: TextStyle(fontSize: 13.5, color: context.money.inkFaint),
                      ),
                    )
                  : async.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: SkeletonList(rows: 3),
                      ),
                      error: (error, _) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: ErrorNote.forError(error, what: 'those results'),
                      ),
                      data: (results) {
                        if (results.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Text(
                              'Nothing matches “$trimmed”.',
                              style:
                                  TextStyle(fontSize: 13.5, color: context.money.inkFaint),
                            ),
                          );
                        }

                        return ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            if (results.people.isNotEmpty) ...[
                              const _SectionLabel('People'),
                              for (final person in results.people)
                                ListTile(
                                  onTap: () => _open(person.personId),
                                  leading: Avatar(person.name, size: 36, tone: AvatarTone.accent),
                                  title: Text(
                                    person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: person.phone == null
                                      ? null
                                      : Text(person.phone!,
                                          style: const TextStyle(fontSize: 12)),
                                  trailing: NetBadge(
                                      netMinor: person.netBalance,
                                      currency: person.currency),
                                ),
                            ],
                            if (results.transactions.isNotEmpty) ...[
                              const _SectionLabel('Transactions'),
                              for (final txn in results.transactions)
                                ListTile(
                                  onTap: () => _open(txn.personId),
                                  title: Text(
                                    txn.note ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    '${txn.personName} · ${friendlyDate(txn.entryDate)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Text(
                                    formatMoney(txn.amountMinor, currency: txn.currency),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: txn.isReceivable
                                          ? context.money.receivable
                                          : context.money.payable,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: context.money.inkFaint,
        ),
      ),
    );
  }
}
