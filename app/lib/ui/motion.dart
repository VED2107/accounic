import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// A press acknowledging itself. Faster than thought — any slower and the
  /// control reads as deciding rather than responding. Matches the web
  /// client's `--dur-tap`.
  static const tap = Duration(milliseconds: 110);

  static const micro = Duration(milliseconds: 140);
  static const component = Duration(milliseconds: 240);
  static const major = Duration(milliseconds: 380);

  /// The same three bands under the names the rest of the industry uses, plus
  /// the emphasised one for a transition that has to be *noticed* — a
  /// settlement landing, a sheet becoming a success screen. Aliases rather than
  /// new values, because a fourth duration nobody can distinguish from the
  /// third is how a motion system stops being a system.
  static const fast = micro;
  static const normal = component;
  static const slow = major;
  static const emphasized = Duration(milliseconds: 460);

  /// A strong ease-out: most of the distance in the first third, then a long
  /// settle. The built-in `easeOutCubic` it replaced (v1.16) spent too long
  /// getting going — the first frames are the ones the eye is on, and a curve
  /// still accelerating there reads as the app hesitating.
  static const enter = Cubic(0.23, 1, 0.32, 1);

  /// For an animation running in REVERSE (`CurvedAnimation.reverseCurve`, a
  /// route or dialog closing). Walked backwards from 1 to 0, an ease-in curve
  /// is steepest at the start of the walk, so the element leaves at once. Never
  /// used forwards: an ease-in entrance starts slow, exactly when the user is
  /// watching.
  static const exit = Curves.easeInCubic;

  /// Something already on screen travelling somewhere else — a segment thumb,
  /// a morph. Leaves decisively, arrives gently.
  static const move = Cubic(0.77, 0, 0.175, 1);
  static const standard = Cubic(0.65, 0, 0.35, 1);

  /// iOS's sheet curve (via Ionic): a surface arriving from off-screen with
  /// weight.
  static const drawer = Cubic(0.32, 0.72, 0, 1);

  /// A surface opening is watched; a surface closing is not — the user already
  /// decided. Every modal leaves faster than it arrived.
  static const sheetIn = Duration(milliseconds: 360);
  static const sheetOut = Duration(milliseconds: 200);

  /// One restrained overshoot, and the vocabulary's rarest member. Reserved for
  /// confirming that money moved: it appears on the settlement tick and nowhere
  /// else, which is what keeps it reading as emphasis rather than as house
  /// style. The web client's `--ease-emph` is the same idea with the same
  /// single caller.
  static const emphasis = Curves.easeOutBack;

  /// The per-item step of a list stagger, and the point past which it stops
  /// reading as sequence and starts reading as lag.
  static const staggerStep = Duration(milliseconds: 40);
  static const staggerCap = 8;

  /// True where a pointer can actually hover.
  ///
  /// The hover affordances cost two implicit animations per row — a fill and a
  /// chevron nudge — and each of those is an `AnimationController` and a
  /// `Ticker`. On a touch screen not one of them can ever fire, so on a 500-row
  /// ledger that is a thousand controllers built to serve an event the device
  /// cannot produce. Widgets that decorate hover check this and build the plain
  /// thing instead.
  static bool get pointerHovers => switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          false,
        _ => true,
      };

  /// True when the platform asks for reduced motion, or when the app is being
  /// driven by a test.
  static bool of(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ||
      MediaQuery.maybeOf(context)?.disableAnimations == true;

  /// Set just before a keyboard-initiated navigation, read (and cleared) by the
  /// next page transition. A shortcut is pressed dozens of times a day; the
  /// page it reaches must simply be there (improve-animations plan 1).
  static bool instantNext = false;

  /// A crossfade for a control whose label changes in place — Save → spinner →
  /// Saved. Scale from 0.98 and a 2px blur that clears as it lands, so the two
  /// states read as one control changing, never two labels overlapping.
  static Widget blurSwap(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        final sigma = (1 - t) * 2;
        Widget out = Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
        );
        if (sigma > 0.05) {
          out = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: out,
          );
        }
        return out;
      },
    );
  }

  static Duration stagger(int index) =>
      staggerStep * (index > staggerCap ? staggerCap : index);
}

/// Fades and lifts its child in once, on first build.
///
/// Used for the blocks a screen is made of: a header, a card, a section. Not for
/// individual rows inside a list — [Stagger] handles those, and applying this to
/// two hundred ledger rows would build two hundred animation controllers.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.offset = 6});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (Motion.of(context)) return child;
    return child
        .animate()
        // 200ms, 6px: a screen here is opened tens of times a day, so its
        // blocks settle rather than perform.
        .fadeIn(delay: delay, duration: const Duration(milliseconds: 200), curve: Motion.enter)
        .moveY(
          begin: offset,
          end: 0,
          delay: delay,
          duration: const Duration(milliseconds: 200),
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
          // Past the cap every row already shared one delay, so the stagger was
          // over — but each was still paying for an Animate, a controller and a
          // ticker. On the people list, which fetches up to 500 rows, that was
          // 500 controllers to choreograph the eight the user can see. Rows past
          // the cap are below the fold when the screen settles; they render
          // plain.
          if (index > Motion.staggerCap)
            child
          else
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
    this.scale = 0.97,
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
        // Asymmetric: the press lands in 100ms so the control answers before
        // the finger lifts; the release takes longer so it settles back rather
        // than snapping.
        duration: _down ? const Duration(milliseconds: 100) : const Duration(milliseconds: 180),
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
      return Text(formatMoney(minor, currency: currency, base: currency), style: resolved);
    }

    return _DirectionalMoney(minor: minor, currency: currency, style: resolved);
  }
}

/// The counting figure, plus one small physical cue: when the amount changes it
/// nudges in the direction the money went — up as it grows, down as it shrinks
/// — and settles. The count carries the value; the nudge carries the direction,
/// which a count alone makes the eye work out.
class _DirectionalMoney extends StatefulWidget {
  const _DirectionalMoney({required this.minor, required this.currency, required this.style});

  final int minor;
  final String currency;
  final TextStyle style;

  @override
  State<_DirectionalMoney> createState() => _DirectionalMoneyState();
}

class _DirectionalMoneyState extends State<_DirectionalMoney> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Motion.major, value: 1);
  late double _from = widget.minor.toDouble();
  late double _to = widget.minor.toDouble();

  @override
  void didUpdateWidget(_DirectionalMoney old) {
    super.didUpdateWidget(old);
    if (old.minor != widget.minor) {
      _from = _current;
      _to = widget.minor.toDouble();
      _controller.forward(from: 0);
    }
  }

  double get _current {
    final t = Motion.standard.transform(_controller.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        final sign = (_to - _from).sign;
        // A 4px rise or drop that decays to rest over the count.
        final dy = -sign * 4 * math.sin(v * math.pi) * (1 - v);
        return Transform.translate(
          offset: Offset(0, dy),
          child: Text(
            formatMoney(_current.round(), currency: widget.currency, base: widget.currency),
            style: widget.style,
          ),
        );
      },
    );
  }
}

/// The tick that draws itself when a settlement lands — the one deliberate
/// flourish in the product, beside the stamp.
///
/// It used to scale a check glyph into place while this comment claimed it drew
/// itself. Now it does: the disc arrives (from 0.85, never from nothing), then
/// the stroke is laid down along its path, short leg then long, the way a hand
/// makes the mark. 560ms, once, after money moved.
class SettledMark extends StatefulWidget {
  const SettledMark({super.key, this.size = 64});

  final double size;

  @override
  State<SettledMark> createState() => _SettledMarkState();
}

class _SettledMarkState extends State<SettledMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 560));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Motion.of(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final disc = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.45, curve: Motion.enter));
    final stroke = CurvedAnimation(parent: _controller, curve: const Interval(0.28, 1, curve: Motion.enter));

    return Semantics(
      label: 'Settled',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Opacity(
          opacity: disc.value,
          child: Transform.scale(
            scale: 0.85 + 0.15 * disc.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: palette.receivableSoft,
                shape: BoxShape.circle,
                border: Border.all(color: palette.receivableLine),
              ),
              child: CustomPaint(
                painter: _TickPainter(progress: stroke.value, color: palette.receivable),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.29, w * 0.52)
      ..lineTo(w * 0.44, w * 0.66)
      ..lineTo(w * 0.72, w * 0.37);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.progress != progress || old.color != color;
}

/// Content that changes in place — a tab's body — crossing over in the
/// direction it came from, so the body travels the same way the segmented
/// thumb above it just did. On a desktop the crossover passes through a 3px
/// blur, which stops two layers of text reading as two things overlapping; on
/// a phone the blur's offscreen layer costs more than it gives.
class DirectionalSwitcher extends StatefulWidget {
  const DirectionalSwitcher({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<DirectionalSwitcher> createState() => _DirectionalSwitcherState();
}

class _DirectionalSwitcherState extends State<DirectionalSwitcher> {
  int _direction = 1;

  @override
  void didUpdateWidget(DirectionalSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _direction = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.of(context)) return widget.child;
    final blur = Motion.pointerHovers;
    return AnimatedSwitcher(
      duration: Motion.normal,
      reverseDuration: Motion.fast,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.enter,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(widget.index);
        final from = (incoming ? 1 : -1) * _direction * 0.035;
        Widget out = SlideTransition(
          position: Tween(begin: Offset(from, 0), end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
        if (blur) {
          final inner = out;
          out = AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final sigma = (1 - animation.value) * 3;
              return sigma < 0.05
                  ? inner
                  : ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: inner,
                    );
            },
          );
        }
        return out;
      },
      child: KeyedSubtree(key: ValueKey(widget.index), child: widget.child),
    );
  }
}

/// Page transitions for go_router. A shared, quiet fade-through: the outgoing
/// screen releases before the incoming one arrives, which reads as one surface
/// changing rather than two screens sliding past each other.
Widget fadeThrough(BuildContext context, Animation<double> animation,
    Animation<double> secondary, Widget child) {
  if (Motion.of(context)) return child;
  // Reached by a keyboard shortcut: no transition at all.
  if (Motion.instantNext) {
    if (animation.status == AnimationStatus.completed) Motion.instantNext = false;
    return child;
  }
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.012), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Motion.enter)),
      child: child,
    ),
  );
}

/// Rebuilds its child when the pointer enters or leaves it.
///
/// Desktop needs to answer "is this thing clickable?" before it is clicked, and
/// Flutter's ink effects answer it only after. Everything hoverable in the app
/// goes through this, so the answer is the same everywhere: a step of surface,
/// a step of ink, nothing that moves layout.
///
/// On a touch device `MouseRegion` simply never fires, so the same widget tree
/// serves both without a platform check.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.builder, this.cursor = SystemMouseCursors.click});

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  void _set(bool value) {
    if (_hovered != value && mounted) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.pointerHovers) return widget.builder(context, false);

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// A background tint that eases in under a hovering pointer, and is a plain
/// [ColoredBox] on a device with no pointer.
///
/// [AnimatedContainer] builds its controller whether or not its value will ever
/// change, so on a touch screen it is a per-row ticker animating nothing.
class HoverFill extends StatelessWidget {
  const HoverFill({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Motion.pointerHovers) return ColoredBox(color: color, child: child);
    return AnimatedContainer(curve: Curves.ease, duration: Motion.fast, color: color, child: child);
  }
}

/// A child nudged aside by a hovering pointer, and left where it is otherwise.
class HoverSlide extends StatelessWidget {
  const HoverSlide({super.key, required this.offset, required this.child});

  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Motion.pointerHovers) return child;
    return AnimatedSlide(
      duration: Motion.fast,
      curve: Motion.enter,
      offset: offset,
      child: child,
    );
  }
}

/// Haptics, on the two platforms that have them and for the three events that
/// earn them (context.md §30).
///
/// A phone that buzzes on every tap is a phone the user turns the haptics off
/// on, and then it cannot tell them anything. So: a transaction recorded, a
/// settlement landed, a destructive confirmation taken. Nothing else.
abstract final class Haptics {
  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// A record was written and the ledger moved.
  static void success() {
    if (_supported) HapticFeedback.mediumImpact();
  }

  /// A choice was committed — a direction picked, a confirmation accepted.
  static void selection() {
    if (_supported) HapticFeedback.selectionClick();
  }

  /// Something was refused.
  static void warning() {
    if (_supported) HapticFeedback.heavyImpact();
  }
}

/// The drill-down transition: a hierarchy, not a sibling swap.
///
/// [fadeThrough] is for the tab destinations, which have no order — sliding
/// between them would imply one. A person detail *is* below the list it came
/// from, so it arrives from the trailing edge and leaves the same way, and the
/// gesture to go back has something to correspond to.
Widget drillIn(BuildContext context, Animation<double> animation,
    Animation<double> secondary, Widget child) {
  if (Motion.of(context)) return child;

  final incoming = CurvedAnimation(parent: animation, curve: Motion.drawer, reverseCurve: Motion.exit);

  return FadeTransition(
    opacity: incoming,
    child: SlideTransition(
      position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(incoming),
      // The outgoing page recedes a fraction rather than staying put, which is
      // what makes the new one read as arriving on top of it.
      child: SlideTransition(
        position: Tween(begin: Offset.zero, end: const Offset(-0.015, 0)).animate(
          CurvedAnimation(parent: secondary, curve: Motion.exit),
        ),
        child: child,
      ),
    ),
  );
}
