import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/avatar_color.dart';
import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../motion.dart';

/// The Accounic design system, Flutter side (context.md §18, §27, §28).
///
/// The same pieces as `web/src/components/ui/primitives.tsx`, with the same
/// names and the same rules: money is coloured only by direction, loading states
/// mirror the shape of the real content, and empty states say what to do next
/// rather than reporting emptiness. No screen styles a card, a row or an avatar
/// by hand.

/// A money amount. [tone] of `auto` picks receivable/payable from the sign and
/// renders the magnitude, which is how balances are read aloud.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.minor, {
    super.key,
    this.currency = 'INR',
    this.base,
    this.tone = MoneyTone.neutral,
    this.style,
    this.compact = true,
    this.strikethrough = false,
    this.withCode,
  });

  final int minor;
  final String currency;
  final MoneyTone tone;
  final TextStyle? style;
  final bool compact;
  final bool strikethrough;

  /// The workspace's own currency (upgrade §45).
  ///
  /// Given it, an amount in that same currency drops its ISO suffix —
  /// `₹2,537.50` rather than `₹2,537.50 INR` — while every foreign amount keeps
  /// one. The contrast is the point: in a list where most rows are `₹…` and one
  /// is `500 AED`, the foreign row identifies itself and the rest stop
  /// repeating what the workspace already says.
  final String? base;

  /// Force the ISO code on or off, overriding [base].
  ///
  /// A symbol alone is ambiguous: `$` is eight of the currencies in this list
  /// and `₹` is two. So the code stays on wherever the workspace currency is
  /// not known, and anything that leaves the app — a statement, an export —
  /// sets it explicitly rather than relying on context it will not have.
  final bool? withCode;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatMoney(
        tone == MoneyTone.auto ? minor.abs() : minor,
        currency: currency,
        compactDecimals: compact,
        withCode: withCode,
        base: base,
      ),
      style: (style ?? const TextStyle()).copyWith(
        color: tone.color(context, minor),
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: -0.2,
        decoration: strikethrough ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

enum MoneyTone {
  receivable,
  payable,
  neutral,
  auto;

  Color color(BuildContext context, int minor) {
    final palette = context.money;
    final resolved = this == MoneyTone.auto
        ? switch (balanceTone(minor)) {
            BalanceTone.receivable => MoneyTone.receivable,
            BalanceTone.payable => MoneyTone.payable,
            BalanceTone.settled => MoneyTone.neutral,
          }
        : this;

    return switch (resolved) {
      MoneyTone.receivable => palette.receivable,
      MoneyTone.payable => palette.payable,
      _ => context.colors.onSurface,
    };
  }
}

/// A headline figure: quiet label, loud number (context.md §13).
class MoneyStat extends StatelessWidget {
  const MoneyStat({
    super.key,
    required this.label,
    required this.minor,
    required this.currency,
    this.base,
    this.tone = MoneyTone.neutral,
    this.sublabel,
    this.size = 27,
  });

  final String label;
  final int minor;
  final String currency;

  /// The workspace currency, so a figure already in it drops the repeated code.
  final String? base;
  final MoneyTone tone;
  final String? sublabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: context.money.inkMuted)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            minor,
            currency: currency,
            base: base,
            tone: tone,
            style: context.display(size),
          ),
        ),
        if (sublabel != null) ...[
          const SizedBox(height: 5),
          Text(sublabel!, style: TextStyle(fontSize: 12.5, color: context.money.inkFaint)),
        ],
      ],
    );
  }
}

/// The balance at the end of a list row — the visual anchor of that row
/// (context.md §5). Amount first, then the one word that says which way it runs.
class NetBadge extends StatelessWidget {
  const NetBadge({
    super.key,
    required this.netMinor,
    required this.currency,
    this.base,
    this.approxMinor,
    this.approxCurrency,
  });

  final int netMinor;
  final String currency;

  /// The workspace currency, so a row kept in it drops the repeated code and a
  /// row kept in any other one keeps it.
  final String? base;

  /// The same position in the workspace's own currency, when this row is kept
  /// in a different one. A dirham balance in a rupee workspace is two facts,
  /// and a row showing only one of them makes the reader convert in their head
  /// (upgrade 42).
  final int? approxMinor;
  final String? approxCurrency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final tone = balanceTone(netMinor);
    final color = switch (tone) {
      BalanceTone.receivable => palette.receivable,
      BalanceTone.payable => palette.payable,
      BalanceTone.settled => palette.inkMuted,
    };

    final approx = approxMinor;
    final approxCode = approxCurrency;
    final showApprox = approx != null &&
        approxCode != null &&
        approxCode != currency &&
        tone != BalanceTone.settled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // A settled row has no figure, and the word standing in for one used to
        // be set in the row money style — so a directory of people showed a
        // bold word in the same slot, at the same weight, as the real amounts
        // beside it, and the eye kept stopping on it. The word is metadata: it
        // drops to metadata weight and lets the pill below carry the state.
        if (tone == BalanceTone.settled)
          Text(
            'No balance',
            style: TextStyle(fontSize: 13, color: palette.inkFaint),
          )
        else
          Text(
            // formatMinor never wrote a code at all, so an AED row in a rupee
            // workspace read as a bare "251.34" with nothing saying which
            // currency it was — the opposite of the web's old habit of writing
            // the code on every row. Both now follow the one rule.
            formatMoney(netMinor.abs(), currency: currency, base: base),
            style: context.moneyStyle(MoneySize.row, color: color),
          ),
        if (showApprox)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              formatApprox(approx.abs(), currency: approxCode),
              style: context.moneyStyle(MoneySize.small, color: palette.inkFaint),
            ),
          ),
        const SizedBox(height: 3),
        // The state in a word AND in a shape. Colour alone never carries it:
        // the pill's tint, its border and the word all say the same thing, so
        // it survives a colour-blind reader and a bad monitor alike.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: switch (tone) {
              BalanceTone.receivable => palette.receivableSoft,
              BalanceTone.payable => palette.payableSoft,
              BalanceTone.settled => palette.sunken,
            },
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: switch (tone) {
                BalanceTone.receivable => palette.receivableLine,
                BalanceTone.payable => palette.payableLine,
                BalanceTone.settled => palette.line,
              },
            ),
          ),
          child: Text(
            switch (tone) {
              BalanceTone.receivable => 'receivable',
              BalanceTone.payable => 'payable',
              BalanceTone.settled => 'up to date',
            },
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
          ),
        ),
      ],
    );
  }
}

/// Initials, tinted by identity.
///
/// Each person gets a stable colour of their own, so a directory reads as a set
/// of distinct faces rather than a wall of red and green — and red and green go
/// back to meaning money and only money, which is the point of reserving them.
///
/// The `tone` override stays for the handful of places where the avatar really
/// is about state rather than identity, such as a disabled account.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, this.tone});

  final String name;
  final double size;
  final AvatarTone? tone;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).take(2);
    final letters = parts.map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  /// Picks the tint from a net balance.
  static AvatarTone toneFor(int netMinor) => switch (balanceTone(netMinor)) {
        BalanceTone.receivable => AvatarTone.receivable,
        BalanceTone.payable => AvatarTone.payable,
        BalanceTone.settled => AvatarTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final (background, foreground, border) = switch (tone) {
      null => () {
          final identity = AvatarColor.of(name, Theme.of(context).brightness);
          return (identity.background, identity.foreground, identity.border);
        }(),
      AvatarTone.receivable => (
          palette.receivableSoft,
          palette.receivable,
          palette.receivableLine
        ),
      AvatarTone.payable => (palette.payableSoft, palette.payable, palette.payableLine),
      AvatarTone.accent => (palette.accentSoft, context.colors.primary, palette.accentLine),
      AvatarTone.neutral => (palette.sunken, palette.inkMuted, palette.line),
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size / 3.2),
        border: Border.all(color: border),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.33,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: foreground,
        ),
      ),
    );
  }
}

enum AvatarTone { neutral, receivable, payable, accent }

/// A bordered card with an optional header row.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.padding = EdgeInsets.zero,
    this.raised = false,
    this.brandRule = false,
  });

  final Widget child;
  final String? title;
  final Widget? action;
  final EdgeInsets padding;

  /// Lifts the card a step above the page — used for the one hero panel on a
  /// screen, never for a list.
  final bool raised;

  /// A single gradient hairline along the top edge: the only place the brand
  /// ramp appears in the chrome.
  final bool brandRule;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      clipBehavior: Clip.antiAlias,
      color: raised ? context.money.raised : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (brandRule)
            const SizedBox(
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(gradient: AccounicColors.brandGradient)),
            ),
          if (title != null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(16, brandRule ? 13 : 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: context.display(15),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
            Divider(height: 1, color: context.money.line),
          ],
          Padding(padding: padding, child: child),
        ],
      ),
    );
    return card;
  }
}

/// A hairline showing how a total splits between the two directions. Not a
/// chart — a proportion, read in the same glance as the numbers above it. Drawn
/// only when both sides are non-zero, because a full-width bar of one colour
/// says nothing the figure has not already said.
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.receivable, required this.payable});

  final int receivable;
  final int payable;

  @override
  Widget build(BuildContext context) {
    final total = receivable + payable;
    if (total <= 0 || receivable == 0 || payable == 0) return const SizedBox.shrink();

    // Two dark tones meeting edge to edge at 4px read as one smudge. Six
    // pixels, each half rounded, with a gap between them: the proportion is
    // legible at a glance and the two sides are unmistakably two things.
    return Semantics(
      label: '${(receivable / total * 100).round()} percent receivable',
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            Expanded(
              flex: receivable,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.money.receivable,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              flex: payable,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.money.payable,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty states that tell the user what to do next (context.md §28).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.action,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.money.sunken,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.money.line),
              ),
              child: Icon(icon, size: AppIconSize.lg, color: context.money.inkFaint),
            ),
            const SizedBox(height: 16),
          ],
          Text(title, textAlign: TextAlign.center, style: context.display(15)),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: context.money.inkMuted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// Shimmering placeholder block (context.md §27).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    // A shimmer that never stops is a repeating animation on a screen the user
    // may be staring at; reduced motion turns it into a plain block.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !Motion.of(context)) _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.money.sunken;
    final highlight = Color.alphaBlend(
      context.money.lineStrong.withValues(alpha: 0.55),
      base,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

/// A list of skeleton rows shaped like the real list underneath it.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Skeleton(width: 40, height: 40, radius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 140),
                      SizedBox(height: 7),
                      Skeleton(width: 90, height: 11),
                    ],
                  ),
                ),
                Skeleton(width: 74, height: 14),
              ],
            ),
          ),
      ],
    );
  }
}

/// Inline error with a retry, used by every async screen (context.md §26).
/// What failed, what to do about it, and whether anything was lost
/// (context.md §26; upgrade §10).
///
/// "Something went wrong" answers none of those three, and in a product that
/// holds someone's money the third is the one they actually want. So a failure
/// here is a heading that names what failed, a line saying what to do, and —
/// where it applies — the sentence that says the stored ledger is untouched and
/// only this screen failed to load. The database's own words never reach a
/// normal user; the technical cause is kept for a debug build.
class ErrorNote extends StatelessWidget {
  const ErrorNote(
    this.message, {
    super.key,
    this.onRetry,
    this.detail,
    this.title,
    this.reassurance,
  });

  /// Builds the note straight from a thrown error, so the user gets the safe
  /// sentence and — in a debug build only — the developer gets the cause.
  /// Screens use this rather than rendering nothing on failure.
  ///
  /// [what] names the thing that did not load, e.g. `'transactions'`, and
  /// becomes "Couldn't load transactions". A read that failed changed nothing,
  /// so the reassurance is stated by default; a *write* that failed should pass
  /// its own, because "your data is safe" is the wrong thing to say about a save
  /// that may or may not have landed.
  factory ErrorNote.forError(
    Object error, {
    Key? key,
    VoidCallback? onRetry,
    String? what,
    String? reassurance,
  }) {
    final failure = error is Failure ? error : null;
    return ErrorNote(
      failure?.message ?? '$error',
      key: key,
      onRetry: onRetry,
      title: what == null ? null : 'Couldn’t load $what',
      reassurance: reassurance ??
          (what == null
              ? null
              : 'Nothing was changed — your people, transactions and balances '
                  'are as you left them.'),
      detail: failure?.detail ?? (failure == null ? '${error.runtimeType}: $error' : null),
    );
  }

  /// What failed, in the user's terms. Optional, because a refused *write*
  /// already says what it refused in [message].
  final String? title;
  final String message;

  /// The sentence about the user's data. Rendered one step quieter.
  final String? reassurance;
  final VoidCallback? onRetry;

  /// The technical cause. Rendered only in a debug build.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.payableSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        border: Border.all(color: palette.payableLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                color: palette.payable,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            message,
            style: TextStyle(
              color: title == null ? palette.payable : palette.inkMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          if (reassurance != null) ...[
            const SizedBox(height: 4),
            Text(
              reassurance!,
              style: TextStyle(color: palette.inkFaint, fontSize: 12.5, height: 1.45),
            ),
          ],
          if (kDebugMode && detail != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              detail!,
              style: TextStyle(
                color: palette.inkFaint,
                fontSize: 11,
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              // 44dp: this is the action the note is offering, and it is
              // frequently the only tappable thing on a failed screen.
              height: 44,
              child: OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.payable,
                  side: BorderSide(color: palette.payableLine),
                ),
                child: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small status pill: settled / partly settled / voided.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final (bg, fg, border) = switch (tone) {
      StatusTone.done => (palette.receivableSoft, palette.receivable, palette.receivableLine),
      StatusTone.partial => (palette.accentSoft, context.colors.primary, palette.accentLine),
      StatusTone.muted => (palette.sunken, palette.inkFaint, palette.line),
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
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

enum StatusTone { done, partial, muted }

/// Centres content and caps its width so a maximised desktop window does not
/// stretch a list to 3000 px (context.md §29).
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final palette = context.money;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? AppIcons.warning : AppIcons.success,
              size: 18,
              color: error ? palette.payable : palette.receivable,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

/// A segmented control whose selection *moves* between segments.
///
/// Material's own `SegmentedButton` re-tints two boxes, which reads as two
/// separate state changes happening at once. A single pill that slides carries
/// the same information as one continuous thing, and it tells the eye which
/// direction the selection travelled — which matters when the segments are
/// filters over the same list.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<({T value, String label})> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final index = segments.indexWhere((segment) => segment.value == value);
    final selected = index < 0 ? 0 : index;

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / segments.length;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.normal,
                curve: Motion.move,
                left: width * selected,
                top: 0,
                bottom: 0,
                width: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    border: Border.all(color: palette.lineStrong),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (position, segment) in segments.indexed)
                    Expanded(
                      child: Semantics(
                        selected: position == selected,
                        button: true,
                        child: Hoverable(
                          builder: (context, hovered) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChanged(segment.value),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: Motion.fast,
                                curve: Motion.enter,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: position == selected
                                      ? context.colors.onSurface
                                      : hovered
                                          ? palette.inkMuted
                                          : palette.inkFaint,
                                ),
                                child: Text(
                                  segment.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One currency's half of a position — cash in hand OR the opening balance —
/// shown in the currency the money was actually entered in (db/migrations/0024).
///
/// The rule this widget holds: the large figure is ALWAYS the original entered
/// amount in its own currency. The workspace-currency equivalent is a small
/// "≈" line beneath it and nothing settles against it. Nothing here reconverts
/// a base-currency total back into a foreign currency.
class CurrencyHalfBlock extends StatelessWidget {
  const CurrencyHalfBlock({
    super.key,
    required this.row,
    required this.baseCurrency,
    required this.opening,
  });

  final CurrencyHalfBreakdown row;
  final String baseCurrency;

  /// Labels the net figure "Remaining" for the opening half, "Net" for cash.
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final net = row.net;
    final tone = net > 0
        ? palette.receivable
        : net < 0
            ? palette.payable
            : palette.inkMuted;

    Widget figure(String name, int minor, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: palette.inkFaint),
              ),
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  minor,
                  currency: row.currency,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );

    final count = StringBuffer('${row.entryCount} ')
      ..write(row.entryCount == 1 ? 'entry' : 'entries');
    if ((row.peopleCount ?? 0) > 0) {
      count
        ..write(' · ${row.peopleCount} ')
        ..write(row.peopleCount == 1 ? 'account' : 'accounts');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  row.currency,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: palette.inkFaint,
                  ),
                ),
              ),
              Text(
                count.toString(),
                style: TextStyle(fontSize: 11, color: palette.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              net.abs(),
              currency: row.currency,
              // The block is already headed by its ISO code, so the figure
              // under that heading does not repeat it — "AED / 251.34", not
              // "AED / 251.34 AED".
              withCode: false,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
          ),
          if (row.showsBaseEquivalent) ...[
            const SizedBox(height: 2),
            Text(
              formatApprox(row.netBaseMinor!.abs(), currency: baseCurrency),
              style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
            ),
          ] else if (row.currency != baseCurrency && row.netBaseMinor == null) ...[
            const SizedBox(height: 2),
            Text(
              'no ${row.currency} → $baseCurrency rate yet',
              style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              figure('Receivable', row.receivable, palette.receivable),
              figure('Payable', row.payable, palette.payable),
              figure('Settled', row.settled, palette.inkMuted),
              if (row.today != 0)
                figure('Today', row.today, palette.inkMuted)
              else
                figure(opening ? 'Remaining' : 'Net', net.abs(), palette.inkMuted),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card of [CurrencyHalfBlock]s — the per-currency view of one half of an
/// account's position, for the person screen (db/migrations/0024). Rendered
/// only when [rows] has something to show.
class CurrencyBreakdownCard extends StatelessWidget {
  const CurrencyBreakdownCard({
    super.key,
    required this.title,
    required this.description,
    required this.rows,
    required this.baseCurrency,
    required this.opening,
  });

  final String title;
  final String description;
  final List<CurrencyHalfBreakdown> rows;
  final String baseCurrency;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final ordered = CurrencyHalfBreakdown.order(rows, baseCurrency);
    if (ordered.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              description,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.inkFaint),
            ),
          ),
          for (final row in ordered) ...[
            Divider(height: 1, color: palette.line),
            CurrencyHalfBlock(row: row, baseCurrency: baseCurrency, opening: opening),
          ],
        ],
      ),
    );
  }
}
