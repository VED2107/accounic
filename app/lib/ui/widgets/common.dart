import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/avatar_color.dart';
import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
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
    this.tone = MoneyTone.neutral,
    this.style,
    this.compact = true,
    this.strikethrough = false,
  });

  final int minor;
  final String currency;
  final MoneyTone tone;
  final TextStyle? style;
  final bool compact;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatMinor(
        tone == MoneyTone.auto ? minor.abs() : minor,
        currency: currency,
        compactDecimals: compact,
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
    this.tone = MoneyTone.neutral,
    this.sublabel,
    this.size = 27,
  });

  final String label;
  final int minor;
  final String currency;
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
  const NetBadge({super.key, required this.netMinor, required this.currency});

  final int netMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final tone = balanceTone(netMinor);
    final color = switch (tone) {
      BalanceTone.receivable => palette.receivable,
      BalanceTone.payable => palette.payable,
      BalanceTone.settled => palette.inkFaint,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          tone == BalanceTone.settled
              ? 'Settled'
              : formatMinor(netMinor.abs(), currency: currency),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          switch (tone) {
            BalanceTone.receivable => 'receivable',
            BalanceTone.payable => 'payable',
            BalanceTone.settled => 'up',
          },
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: tone == BalanceTone.settled ? palette.inkFaint : color.withValues(alpha: 0.75),
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

    return Semantics(
      label: '${(receivable / total * 100).round()} percent receivable',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 4,
          child: Row(
            children: [
              Expanded(flex: receivable, child: ColoredBox(color: context.money.receivable)),
              Expanded(flex: payable, child: ColoredBox(color: context.money.payable)),
            ],
          ),
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
              child: Icon(icon, size: 22, color: context.money.inkFaint),
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
class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key, this.onRetry, this.detail});

  /// Builds the note straight from a thrown error, so the user gets the safe
  /// sentence and — in a debug build only — the developer gets the cause.
  /// Screens use this rather than rendering nothing on failure.
  factory ErrorNote.forError(Object error, {Key? key, VoidCallback? onRetry}) {
    final failure = error is Failure ? error : null;
    return ErrorNote(
      failure?.message ?? '$error',
      key: key,
      onRetry: onRetry,
      detail: failure?.detail ?? (failure == null ? '${error.runtimeType}: $error' : null),
    );
  }

  final String message;
  final VoidCallback? onRetry;

  /// The technical cause. Rendered only in a debug build.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.money.payableSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        border: Border.all(color: context.money.payableLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: context.money.payable, fontSize: 13, height: 1.45),
          ),
          if (kDebugMode && detail != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              detail!,
              style: TextStyle(
                color: context.money.inkFaint,
                fontSize: 11,
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: context.money.payable,
              ),
              child: const Text('Try again'),
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
              error ? Icons.error_outline : Icons.check_circle_outline,
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
