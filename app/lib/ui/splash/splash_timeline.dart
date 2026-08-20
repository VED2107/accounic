library;

import 'package:flutter/animation.dart';

/// The choreography, stated once as numbers (context.md §18).
///
/// The whole sequence is driven by a **single** [AnimationController] running
/// for [SplashTimeline.total]; every stage below is an [Interval] into it. That
/// is deliberate — six controllers would mean six tickers, six chances for the
/// stages to drift apart on a loaded frame, and no single place to read the
/// timing off. With one clock the sequence is a description rather than a set
/// of instructions that happen to line up.
///
/// The stages overlap on purpose. Nothing here waits for the thing before it to
/// finish: the bars start climbing while the "A" is still resolving, and the
/// arrow leaves before the bars land. Sequences whose stages abut read as a
/// list of animations; sequences that overlap read as one movement.
///
///   0 – 180ms    the room lights, barely
///   160 – 620    the A is drawn, and settles into place
///   420 – 760    three bars rise, 70ms apart
///   580 – 1000   the arrow travels its path; the head arrives last
///   1000 – 1150  everything settles a hair
///   1080 – 1400  the wordmark completes the brand
///   1400 – 1560  a beat
///   1560 – 1900  the splash gives way to the application
abstract final class SplashTimeline {
  /// Total wall-clock length of the cinematic sequence.
  static const total = Duration(milliseconds: 1900);

  /// The reduced-motion sequence: two fades, no drawing, no transforms.
  static const reduced = Duration(milliseconds: 900);

  /// How long the app waits before giving up on the sequence and showing the
  /// application anyway (context.md §26). The splash depends on nothing but a
  /// ticker, so this should never fire — it exists so that a stalled controller
  /// cannot strand a user on a logo.
  static const failsafe = Duration(seconds: 5);

  static const _ms = 1900.0;

  static Interval _at(double startMs, double endMs, {Curve curve = Curves.linear}) =>
      Interval(startMs / _ms, endMs / _ms, curve: curve);

  /// The ambient light behind the mark.
  static final ambient = _at(0, 180, curve: Curves.easeOut);

  /// The A: how much of the ribbon has been drawn.
  static final markDraw = _at(160, 620, curve: Curves.easeInOutCubic);

  /// The A's entrance transform — scale and lift, on a softer curve than the
  /// draw so the shape arrives before it stops moving.
  static final markEnter = _at(160, 660, curve: Curves.easeOutCubic);

  /// The three bars, 70ms apart. Each climbs for 260ms.
  static final bars = [
    _at(420, 680, curve: Curves.easeOutCubic),
    _at(490, 750, curve: Curves.easeOutCubic),
    _at(560, 820, curve: Curves.easeOutCubic),
  ];

  /// The arrow's stroke, drawn from its tail.
  static final arrowDraw = _at(580, 960, curve: Curves.easeInOutCubic);

  /// The arrowhead, which arrives only once the stroke has got there.
  static final arrowHead = _at(920, 1010, curve: Curves.easeOutCubic);

  /// The settle: 0.985 → 1. The one moment of the sequence a viewer feels
  /// rather than sees.
  static final settle = _at(1000, 1150, curve: Curves.easeOutCubic);

  /// The wordmark completing the lock-up.
  static final wordmark = _at(1080, 1400, curve: Curves.easeOutCubic);

  /// The whole composition releasing, and the application taking over.
  static final exit = _at(1560, 1900, curve: Curves.easeInOutCubic);

  /// The point past which the application below is already fully painted, so
  /// the splash can stop being built at all.
  static const done = 1.0;
}
