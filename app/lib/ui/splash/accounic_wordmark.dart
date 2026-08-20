import 'package:flutter/material.dart';

import 'splash_timeline.dart';

/// "Accounic", completing the lock-up (context.md §18).
///
/// The same two-tone treatment as `brand/accounic-horizontal.svg` and as the
/// wordmark in the app's chrome — "Accoun" in ink, "ic" in the teal-to-green
/// end of the ramp — set in Poppins, which the app already bundles. Live text
/// rather than an image: it stays crisp at any density and needs no asset per
/// screen size.
///
/// It arrives late and it arrives quietly. The symbol has already said what the
/// product is; the word only has to name it, so it moves eight pixels and stops.
/// A wordmark that slides in from off-screen turns the last beat of the sequence
/// into the loudest one.
class AccounicWordmark extends StatelessWidget {
  const AccounicWordmark({
    super.key,
    required this.animation,
    required this.fontSize,
    required this.reducedMotion,
  });

  final Animation<double> animation;
  final double fontSize;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'Poppins',
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: -fontSize * 0.032,
      height: 1.1,
      color: const Color(0xFFF2F5F9),
    );

    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Accoun', style: base),
          TextSpan(
            text: 'ic',
            style: base.copyWith(
              foreground:
                  Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFF14B8A6), Color(0xFF22C55E)],
                    ).createShader(Rect.fromLTWH(0, 0, fontSize * 1.7, fontSize)),
            ),
          ),
        ],
      ),
      // Announced once, as the product's name, rather than as two runs of text.
      semanticsLabel: 'Accounic',
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = SplashTimeline.wordmark.transform(animation.value);
          if (reducedMotion) return Opacity(opacity: t, child: child);

          return Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(-8 * (1 - t), 0), child: child),
          );
        },
        child: text,
      ),
    );
  }
}
