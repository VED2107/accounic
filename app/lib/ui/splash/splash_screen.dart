import 'package:flutter/material.dart';

import 'accounic_logo_animation.dart';
import 'accounic_wordmark.dart';
import 'splash_background.dart';
import 'splash_timeline.dart';

/// The composition (context.md §18, §29).
///
/// Mark above wordmark at every size — the same choreography on a phone and on
/// a monitor, scaled rather than rearranged. The mark is sized off the shorter
/// edge and clamped at both ends, so an ultrawide window does not produce a
/// four-hundred-pixel logo and a small window does not produce a stamp.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.animation, required this.reducedMotion});

  final Animation<double> animation;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Off the shorter edge, so the composition is centred and intact in
        // portrait, in landscape and in anything between.
        final markSize = (constraints.biggest.shortestSide * 0.30).clamp(104.0, 208.0);
        final fontSize = (markSize * 0.245).clamp(24.0, 46.0);

        // The gate hangs this off `MaterialApp.builder`, which is above the
        // Navigator and therefore above any Material. Without one, Flutter
        // draws its "unstyled text" debug decoration — the double yellow
        // underline — through the wordmark. A transparent Material supplies the
        // ancestor and the text baseline without painting a surface of its own.
        return Material(
          type: MaterialType.transparency,
          child: Semantics(
            label: 'Accounic',
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: animation,
                  builder:
                      (context, _) => SplashBackground(
                        opacity:
                            reducedMotion ? 1 : SplashTimeline.ambient.transform(animation.value),
                      ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AccounicLogoAnimation(
                        animation: animation,
                        size: markSize,
                        reducedMotion: reducedMotion,
                      ),
                      SizedBox(height: markSize * 0.16),
                      AccounicWordmark(
                        animation: animation,
                        fontSize: fontSize,
                        reducedMotion: reducedMotion,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
