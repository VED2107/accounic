import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/money.dart';
import '../core/theme.dart';

/// The motion language (context.md §18), the Flutter half of the one the web
/// client speaks.
///
/// Both clients use the same three bands and the same easing family, so the two
/// feel like one product even though nothing is shared but the numbers:
///
///   micro       100–180ms   press feedback, hover, colour changes
///   component   180–300ms   cards, sheets, tab content, list rows
///   major       300–450ms   route transitions, settlement success
///
/// Two rules hold everywhere. Animate transform and opacity only — never a
/// layout property, which would re-run layout on every frame on a mid-range
/// Android device. And check [Motion.of] before starting anything decorative,
/// because a user who has asked the system for reduced motion has asked this app
/// too.
class Motion {
  const Motion._();

  static const micro = Duration(milliseconds: 140);
  static const component = Duration(milliseconds: 240);
  static const major = Duration(milliseconds: 380);

  /// A tightened ease-out. Fast to start, settles rather than stops — the curve
  /// physical objects follow, without the overshoot of an elastic curve.
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const move = Curves.fastOutSlowIn;
  static const standard = Curves.easeInOutCubic;

  /// The per-item step of a list stagger, and the point past which it stops
  /// reading as sequence and starts reading as lag.
  static const staggerStep = Duration(milliseconds: 40);
  static const staggerCap = 8;

  /// True when the platform asks for reduced motion, or when the app is being
  /// driven by a test.
  static bool of(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ||
      MediaQuery.maybeOf(context)?.disableAnimations == true;

  static Duration stagger(int index) =>
      staggerStep * (index > staggerCap ? staggerCap : index);
}

/// Fades and lifts its child in once, on first build.
///
/// Used for the blocks a screen is made of: a header, a card, a section. Not for
/// individual rows inside a list — [Stagger] handles those, and applying this to
/// two hundred ledger rows would build two hundred animation controllers.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.offset = 10});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (Motion.of(context)) return child;
    return child
        .animate()
        .fadeIn(delay: delay, duration: Motion.component, curve: Motion.enter)
        .moveY(
          begin: offset,
          end: 0,
          delay: delay,
          duration: Motion.component,
          curve: Motion.enter,
        );
  }
}

/// A list whose rows arrive in sequence.
///
/// The stagger is capped, and rows past the cap simply appear with the last
/// delayed one — a fiftieth row still fading in a second after the screen
/// settled reads as a stall, not as choreography.
class Stagger extends StatelessWidget {
  const Stagger({super.key, required this.children, this.delay = Duration.zero});

  final List<Widget> children;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (Motion.of(context)) {
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, child) in children.indexed)
          child
              .animate()
              .fadeIn(
                delay: delay + Motion.stagger(index),
                duration: Motion.micro,
                curve: Motion.enter,
              )
              .moveY(
                begin: 6,
                end: 0,
                delay: delay + Motion.stagger(index),
                duration: Motion.component,
                curve: Motion.enter,
              ),
      ],
    );
  }
}

/// Scales its child down a hair while pressed.
///
/// The one piece of feedback every tappable surface in the app shares. Scale is
/// a transform, so it costs nothing but a matrix — and unlike a ripple it reads
/// on a card the size of half a screen.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.98,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.of(context);
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: Motion.micro,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}

/// A money figure that travels to its new value instead of jumping to it.
///
/// It does **not** animate on first build. A balance counting up from zero every
/// time a screen opens is decoration; a balance visibly moving from ₹17,000 to
/// ₹13,000 the moment a settlement is recorded is information — it shows the
/// user the consequence of what they just did, on the number they were looking
/// at. Same rule as the web client's CountUp.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(
    this.minor, {
    super.key,
    required this.currency,
    this.style,
    this.color,
  });

  final int minor;
  final String currency;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = (style ?? const TextStyle()).copyWith(
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (Motion.of(context)) {
      return Text(formatMinor(minor, currency: currency), style: resolved);
    }

    return TweenAnimationBuilder<double>(
      // The tween's `begin` is replaced by the current value on rebuild, so the
      // first build animates from the target to the target — a no-op — and every
      // later change animates from wherever the figure already was.
      tween: Tween(begin: minor.toDouble(), end: minor.toDouble()),
      duration: Motion.major,
      curve: Motion.standard,
      builder: (context, value, _) => Text(
        formatMinor(value.round(), currency: currency),
        style: resolved,
      ),
    );
  }
}

/// The tick that draws itself when a settlement lands — the one deliberate
/// flourish in the product, and the only place anything is celebrated.
class SettledMark extends StatelessWidget {
  const SettledMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final mark = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.receivableSoft,
        shape: BoxShape.circle,
        border: Border.all(color: palette.receivableLine),
      ),
      child: Icon(Icons.check_rounded, size: size * 0.5, color: palette.receivable),
    );

    if (Motion.of(context)) return mark;

    return mark
        .animate()
        .scaleXY(begin: 0.7, end: 1, duration: Motion.major, curve: Curves.easeOutBack)
        .fadeIn(duration: Motion.component);
  }
}

/// Page transitions for go_router. A shared, quiet fade-through: the outgoing
/// screen releases before the incoming one arrives, which reads as one surface
/// changing rather than two screens sliding past each other.
Widget fadeThrough(BuildContext context, Animation<double> animation,
    Animation<double> secondary, Widget child) {
  if (Motion.of(context)) return child;
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.012), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Motion.enter)),
      child: child,
    ),
  );
}
