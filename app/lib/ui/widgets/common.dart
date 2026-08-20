import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';

/// Shared presentation pieces (context.md §18, §27, §28).
///
/// Money is coloured only by direction, loading states always mirror the shape
/// of the real content, and empty states say what to do next rather than just
/// reporting emptiness.

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
    final palette = context.money;
    final resolved = tone == MoneyTone.auto
        ? switch (balanceTone(minor)) {
            BalanceTone.receivable => MoneyTone.receivable,
            BalanceTone.payable => MoneyTone.payable,
            BalanceTone.settled => MoneyTone.neutral,
          }
        : tone;

    final color = switch (resolved) {
      MoneyTone.receivable => palette.receivable,
      MoneyTone.payable => palette.payable,
      _ => context.colors.onSurface,
    };

    return Text(
      formatMinor(
        tone == MoneyTone.auto ? minor.abs() : minor,
        currency: currency,
        compactDecimals: compact,
      ),
      style: (style ?? const TextStyle()).copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: -0.2,
        decoration: strikethrough ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

enum MoneyTone { receivable, payable, neutral, auto }

/// A headline figure: quiet label, loud number (context.md §13).
class MoneyStat extends StatelessWidget {
  const MoneyStat({
    super.key,
    required this.label,
    required this.minor,
    required this.currency,
    this.tone = MoneyTone.neutral,
    this.sublabel,
  });

  final String label;
  final int minor;
  final String currency;
  final MoneyTone tone;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13.5, color: context.money.inkMuted)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            minor,
            currency: currency,
            tone: tone,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
          ),
        ),
        if (sublabel != null) ...[
          const SizedBox(height: 2),
          Text(sublabel!, style: TextStyle(fontSize: 12.5, color: context.money.inkFaint)),
        ],
      ],
    );
  }
}

/// "₹12,500 receivable" / "Settled up" — the one-line answer for a list row.
class NetBadge extends StatelessWidget {
  const NetBadge({super.key, required this.netMinor, required this.currency});

  final int netMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final color = switch (balanceTone(netMinor)) {
      BalanceTone.receivable => palette.receivable,
      BalanceTone.payable => palette.payable,
      BalanceTone.settled => palette.inkFaint,
    };

    return Text(
      netSummary(netMinor, currency: currency),
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Circular initials, used wherever a person is listed.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, this.accent = false});

  final String name;
  final double size;
  final bool accent;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).take(2);
    final letters = parts.map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent ? context.colors.primaryContainer : context.money.sunken,
        borderRadius: BorderRadius.circular(size / 3.2),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
          color: accent ? context.colors.primary : context.money.inkMuted,
        ),
      ),
    );
  }
}

/// A bordered card with an optional header row.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final String? title;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
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
              ),
              child: Icon(icon, size: 22, color: context.money.inkFaint),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: context.money.inkMuted),
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
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.money.sunken;
    final highlight = Color.alphaBlend(
      context.money.line.withValues(alpha: 0.7),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                const Skeleton(width: 40, height: 40, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Skeleton(width: 140),
                      SizedBox(height: 7),
                      Skeleton(width: 90, height: 11),
                    ],
                  ),
                ),
                const Skeleton(width: 74, height: 14),
              ],
            ),
          ),
      ],
    );
  }
}

/// Inline error with a retry, used by every async screen (context.md §26).
class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.money.payableSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.money.payable.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: context.money.payable, fontSize: 13.5, height: 1.45),
          ),
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
    final (bg, fg) = switch (tone) {
      StatusTone.done => (palette.receivableSoft, palette.receivable),
      StatusTone.partial => (context.colors.primaryContainer, context.colors.primary),
      StatusTone.muted => (palette.sunken, palette.inkFaint),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
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
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.money.payable : null,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}
