import 'dart:async';

import 'package:flutter/material.dart';

import 'splash_background.dart';
import 'splash_screen.dart';
import 'splash_timeline.dart';

/// Holds the splash over the application until the sequence is done
/// (context.md §20, §26).
///
/// It is an overlay, not a route. The router, the auth redirect and every
/// provider come up *behind* it on the very first frame, which is what makes
/// the handover seamless: by the time the splash lifts, the screen underneath
/// is already painted and settled, so there is nothing to wait for and nothing
/// flashes into place.
///
/// Two rules it must never break:
///
/// * **It never waits on anything.** Not the network, not Supabase, not a
///   session refresh. Accounic must open offline, so the splash is a fixed
///   length of time and the application is behind it either way — the moment a
///   splash starts awaiting a future it has stopped being a brand moment and
///   become a loading screen that lies about being one.
/// * **It always lifts.** [SplashTimeline.failsafe] removes it even if the
///   ticker never completes, because there is no failure worth stranding
///   someone on a logo for.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _failsafe;

  /// Set once the splash has finished and been removed from the tree. From then
  /// on this widget builds nothing but its child.
  bool _finished = false;

  /// Resolved on the first build, because [MediaQuery] is not available in
  /// [initState] and the answer decides how long the controller runs for.
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: SplashTimeline.total)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });

    _failsafe = Timer(SplashTimeline.failsafe, _finish);
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _failsafe?.cancel();
    setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;

    // A user who has asked the system for less motion gets the brand without
    // the choreography: the mark and the word simply resolve, over a shorter
    // clock (context.md §28).
    if (_reducedMotion == null) {
      final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      _reducedMotion = reduced;
      _controller.duration = reduced ? SplashTimeline.reduced : SplashTimeline.total;
      _controller.forward();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, splash) {
            final exit = SplashTimeline.exit.transform(_controller.value);
            if (exit >= 1) return const SizedBox.shrink();

            // The splash releases by fading and easing back a fraction, so the
            // application appears to come forward to meet it rather than being
            // uncovered. A hard cut here would undo the whole sequence.
            return IgnorePointer(
              child: Opacity(
                opacity: 1 - exit,
                child: Transform.scale(scale: 1 + 0.02 * exit, child: splash),
              ),
            );
          },
          child: SplashScreen(animation: _controller, reducedMotion: _reducedMotion ?? false),
        ),
      ],
    );
  }
}

/// The colour the native launch surface, the splash ground and the application
/// scaffold all share, so no handover between them is ever visible
/// (context.md §27).
///
/// Kept next to the gate because the three places that must agree on it are the
/// Android launch drawable, the Windows window brush and this file; if it
/// changes here it has to change in `android/app/src/main/res/drawable/
/// launch_background.xml` and `windows/runner/win32_window.cpp` in the same
/// commit.
const Color kLaunchGround = SplashBackground.ground;
