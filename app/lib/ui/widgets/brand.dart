import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The Accounic mark, drawn rather than loaded.
///
/// `brand/accounic-icon.svg` is the source of truth for the shape; this is that
/// shape as a CustomPainter. Painting it directly avoids adding an SVG renderer
/// to the app for one glyph, scales to any size without an asset per density,
/// and costs a handful of path operations on a layer that never repaints.
class AccounicMark extends StatelessWidget {
  const AccounicMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: const _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  // The SVG is drawn on a 512 grid; every coordinate below is that grid scaled.
  static const _grid = 512.0;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _grid;
    Offset p(double x, double y) => Offset(x * k, y * k);

    final ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 58 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = AccounicColors.brandGradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    // The "A": a ribbon with no crossbar.
    canvas.drawPath(
      Path()
        ..moveTo(96 * k, 414 * k)
        ..lineTo(256 * k, 104 * k)
        ..lineTo(416 * k, 414 * k),
      ribbon,
    );

    // Three ascending bars, blue through cyan to green.
    const bars = [
      (178.0, 362.0, 52.0, Color(0xFF2563EB)),
      (228.0, 322.0, 92.0, Color(0xFF06B6D4)),
      (278.0, 278.0, 136.0, Color(0xFF22C55E)),
    ];
    for (final (x, y, height, color) in bars) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(p(x, y), p(x + 36, y + height)),
          Radius.circular(9 * k),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}

/// Mark plus wordmark: "Accoun" in ink, "ic" in the gradient — the lock-up from
/// `brand/accounic-horizontal.svg`, rebuilt in live text so it follows the theme
/// and stays crisp at any size.
class AccounicLogo extends StatelessWidget {
  const AccounicLogo({super.key, this.markSize = 26, this.fontSize = 17});

  final double markSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Poppins',
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: context.colors.onSurface,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A zero mark means wordmark only — the login screen shows the mark
        // separately, at full size, above it.
        if (markSize > 0) ...[
          AccounicMark(size: markSize),
          SizedBox(width: markSize * 0.34),
        ],
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Accoun', style: style),
              TextSpan(
                text: 'ic',
                style: style.copyWith(
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFF14B8A6), Color(0xFF22C55E)],
                    ).createShader(Rect.fromLTWH(0, 0, fontSize * 1.6, fontSize)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Text painted with the brand ramp.
///
/// The Flutter half of the web client's `.brand-text`, and it follows the same
/// rule the token was written under: the gradient belongs to the brand — the
/// mark, a hairline, one emphasised line — and never to a large field of UI. It
/// is used on the dashboard greeting and nowhere else, because a second caller
/// is the point at which it stops meaning "this is Accounic" and starts meaning
/// "this app likes gradients".
///
/// Money never takes it. Green and red are the only colours in this product
/// that carry meaning, and a figure wearing the brand ramp would be a figure
/// that has stopped saying which way it runs.
class BrandText extends StatelessWidget {
  const BrandText(this.text, {super.key, required this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      // srcIn keeps the glyph shapes and replaces only their colour, so the
      // gradient runs across the word rather than behind it.
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => AccounicColors.brandGradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        // The mask needs opaque ink underneath it; the colour itself is
        // discarded by srcIn.
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}
