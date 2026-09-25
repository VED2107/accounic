import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/theme.dart';
import '../motion.dart';

/// COUNTERFOIL & SEAL — the pieces of the security-print world.
///
/// Every account is drawn as an instrument of value: the one figure a screen
/// certifies sits on a guilloché field, carries a serial, and is separated
/// from its counterfoil by a perforation; a settled entry is cancelled with a
/// stamp. Each piece here exists because it carries a fact:
///
///   [GuillocheField]    marks the ONE certified figure on a surface; never a
///                       background for anything else
///   [Perforation]       separates two figures that must never be added
///                       together — cash in hand and its opening counterfoil
///   [SerialText]        the record's own id, shortened, so an entry can be
///                       named aloud and found again
///   [Microprint]        a line of real account data at the panel's edge
///   [CancellationStamp] a settlement, in the direction's ink
///
/// All of it is painted once and cached behind a RepaintBoundary: none of it
/// animates except the stamp landing, which happens once, after money moved.

/// Fine interference lines, the engraving that sits behind a banknote's value.
///
/// Drawn as bands of phase-shifted sine curves — the classic rosette-free
/// "wave" guilloché — in the primary ink at very low alpha. Static.
class GuillocheField extends StatelessWidget {
  const GuillocheField({super.key, this.color, this.opacity});

  final Color? color;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = (color ?? context.colors.primary)
        .withValues(alpha: opacity ?? (dark ? 0.16 : 0.11));
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(painter: _GuillochePainter(ink), size: Size.infinite),
      ),
    );
  }
}

class _GuillochePainter extends CustomPainter {
  const _GuillochePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..isAntiAlias = true;

    // Two interleaved families of curves whose envelopes breathe against each
    // other; the moiré between them is what reads as "engraved".
    const lines = 26;
    final h = size.height;
    final w = size.width;
    for (var family = 0; family < 2; family++) {
      final freq = family == 0 ? 2.2 : 3.1;
      final amp = h * (family == 0 ? 0.20 : 0.14);
      for (var i = 0; i < lines; i++) {
        final t = i / (lines - 1);
        final phase = t * math.pi * (family == 0 ? 1.0 : -1.3);
        final baseY = h * (0.08 + 0.84 * t);
        final path = Path();
        for (var x = 0.0; x <= w; x += 3) {
          final u = x / w;
          final envelope = math.sin(u * math.pi); // taper at both ends
          final y = baseY +
              amp * envelope * math.sin(u * math.pi * 2 * freq + phase) * (0.35 + 0.65 * t);
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GuillochePainter old) => old.color != color;
}

/// A row of punched holes between two parts of one instrument: the line a
/// counterfoil is torn along. Means "these two are separate", and only that.
class Perforation extends StatelessWidget {
  const Perforation({super.key, this.color, this.height = 10});

  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _PerforationPainter(color ?? context.money.lineStrong),
        ),
      ),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  const _PerforationPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const gap = 9.0;
    const r = 1.6;
    final y = size.height / 2;
    for (var x = gap / 2; x < size.width; x += gap) {
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => old.color != color;
}

/// The record's serial: its id's first six hex digits, grouped like the
/// number printed on a cheque — `No. 4F2A·91`.
String serialOf(String id) {
  final hex = id.replaceAll('-', '').toUpperCase();
  if (hex.length < 6) return hex;
  return '${hex.substring(0, 4)}·${hex.substring(4, 6)}';
}

class SerialText extends StatelessWidget {
  const SerialText(this.id, {super.key, this.prefix = 'No.', this.color, this.size = 11});

  final String id;
  final String prefix;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Serial ${serialOf(id)}',
      excludeSemantics: true,
      child: Text(
        '$prefix ${serialOf(id)}',
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: color ?? context.money.inkFaint,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A single line of microprint at an instrument's edge: real account data,
/// repeated, set too small to be read casually and exactly the kind of detail
/// a copier loses. Decorative to a screen reader.
class Microprint extends StatelessWidget {
  const Microprint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final line = List.filled(12, text.toUpperCase()).join('  ·  ');
    return ExcludeSemantics(
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: TextStyle(
          fontSize: 6.5,
          letterSpacing: 1.4,
          height: 1,
          color: context.money.inkSubtle.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// The two shapes a counter stamp comes in: the round cancellation struck on a
/// paid instrument, and the boxed word struck across one that no longer counts.
enum StampShape { round, box }

/// A rubber stamp, inked in the direction's colour.
///
/// Three details make it read as struck rather than drawn, none of which a
/// user will name and all of which they would miss:
///
/// * **Worn rubber.** The ink is broken by a deterministic speckle, seeded from
///   [seed] (the record's id), so the same entry always carries the same wear
///   and a list of stamps never looks cloned.
/// * **A hand's angle.** Unless [angle] is given, the tilt is derived from the
///   seed too, within ±11° — a clerk never strikes two stamps square.
/// * **The strike.** With [land], it comes down once: out of a 6px blur and
///   1.3× scale, squashes to 0.96 as the ink meets paper, throws a faint ring
///   of pressure, and settles at rest. 460ms, then never again.
class CancellationStamp extends StatefulWidget {
  const CancellationStamp({
    super.key,
    required this.color,
    this.word = 'SETTLED',
    this.detail,
    this.size = 64,
    this.angle,
    this.seed = '',
    this.shape = StampShape.round,
    this.land = false,
  });

  final Color color;
  final String word;
  final String? detail;
  final double size;
  final double? angle;
  final String seed;
  final StampShape shape;
  final bool land;

  @override
  State<CancellationStamp> createState() => _CancellationStampState();
}

class _CancellationStampState extends State<CancellationStamp>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  int get _hash {
    var h = 0x811c9dc5;
    for (final unit in (widget.seed.isEmpty ? widget.word : widget.seed).codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    if (widget.land) {
      _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (Motion.of(context)) {
          _controller!.value = 1;
        } else {
          _controller!.forward();
          Haptics.success();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hash = _hash;
    final angle = widget.angle ?? ((hash % 1000) / 1000 - 0.5) * 0.38;
    final stamp = Semantics(
      label: [widget.word, if (widget.detail != null) widget.detail].join(', '),
      excludeSemantics: true,
      child: Transform.rotate(
        angle: angle,
        child: SizedBox(
          width: widget.shape == StampShape.box ? widget.size * 1.9 : widget.size,
          height: widget.shape == StampShape.box ? widget.size * 0.62 : widget.size,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _StampPainter(
                color: widget.color,
                word: widget.word,
                detail: widget.detail,
                shape: widget.shape,
                seed: hash,
              ),
            ),
          ),
        ),
      ),
    );

    final controller = _controller;
    if (controller == null) return stamp;

    // Down fast (0–50%), squash on contact, then give back to rest.
    final down = CurvedAnimation(parent: controller, curve: const Interval(0, 0.5, curve: Motion.enter));
    final rest = CurvedAnimation(parent: controller, curve: const Interval(0.5, 1, curve: Motion.enter));
    final ring = CurvedAnimation(parent: controller, curve: const Interval(0.42, 1, curve: Motion.enter));

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final scale = 1.3 - 0.34 * down.value + 0.04 * rest.value;
        final sigma = 6 * (1 - down.value);
        Widget struck = Opacity(
          opacity: (down.value * 1.6).clamp(0, 1).toDouble(),
          child: Transform.scale(scale: scale, child: child),
        );
        if (sigma > 0.05) {
          struck = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: struck,
          );
        }
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // The pressure ring: ink squeezed past the rubber's edge, gone in
            // the time it takes to see it.
            if (ring.value > 0 && ring.value < 1)
              Opacity(
                opacity: (1 - ring.value) * 0.35,
                child: Transform.scale(
                  scale: 1 + 0.22 * ring.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: widget.shape == StampShape.round ? BoxShape.circle : BoxShape.rectangle,
                      border: Border.all(color: widget.color, width: 2),
                    ),
                  ),
                ),
              ),
            struck,
          ],
        );
      },
      child: stamp,
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter({
    required this.color,
    required this.word,
    required this.detail,
    required this.shape,
    required this.seed,
  });

  final Color color;
  final String word;
  final String? detail;
  final StampShape shape;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is inked into a layer, then the rubber's wear is punched out
    // of it — so the gaps show the paper, not a second colour.
    canvas.saveLayer(Offset.zero & size, Paint());
    if (shape == StampShape.round) {
      _round(canvas, size);
    } else {
      _box(canvas, size);
    }
    _wear(canvas, size);
    canvas.restore();
  }

  Paint get _stroke => Paint()
    ..color = color.withValues(alpha: 0.88)
    ..style = PaintingStyle.stroke;

  void _round(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ink = color.withValues(alpha: 0.9);
    canvas.drawCircle(c, r - 1.4, _stroke..strokeWidth = size.width * 0.04);
    canvas.drawCircle(c, r * 0.64, _stroke..strokeWidth = size.width * 0.02);

    // The firm's name arched over the top and a second word set upright along
    // the bottom, as on every counter stamp; the bar through the middle sits
    // in the gaps between them, so nothing is printed under it.
    final outer = r - 1.4 - size.width * 0.02;
    final inner = r * 0.64 + size.width * 0.01;
    final band = outer - inner;
    final mid = inner + band / 2;
    final fs = band * 0.62;
    TextPainter glyph(String ch) => TextPainter(
          text: TextSpan(
            text: ch,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: ink,
              fontSize: fs,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

    void arc(String text, {required bool top}) {
      final letters = [for (final ch in text.split('')) glyph(ch)];
      final gap = fs * 0.22;
      final length = letters.fold<double>(0, (t, p) => t + p.width) + gap * (letters.length - 1);
      // Never past the bar: each arc keeps to its own ~130° of the ring.
      final squeeze = math.min(1.0, (mid * math.pi * 0.72) / length);
      final sweep = length * squeeze / mid;
      // Top reads clockwise from the left; bottom reads anticlockwise from
      // the left, so both are upright to the eye.
      var cursor = top ? -math.pi / 2 - sweep / 2 : math.pi / 2 + sweep / 2;
      for (final tp in letters) {
        final step = (tp.width * squeeze) / mid;
        final a = top ? cursor + step / 2 : cursor - step / 2;
        cursor = top ? cursor + step + gap * squeeze / mid : cursor - step - gap * squeeze / mid;
        final pos = c + Offset(math.cos(a), math.sin(a)) * mid;
        canvas
          ..save()
          ..translate(pos.dx, pos.dy)
          ..rotate(top ? a + math.pi / 2 : a - math.pi / 2)
          ..scale(squeeze, 1)
          ..translate(-tp.width / 2, -tp.height / 2);
        tp.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }

    arc('ACCOUNIC', top: true);
    arc('LEDGER', top: false);
    // Two stars' worth of dot either side, where the arcs meet the bar.
    for (final a in [math.pi * 0.84, math.pi * 0.16, -math.pi * 0.16, -math.pi * 0.84]) {
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * mid, size.width * 0.018, Paint()..color = ink);
    }

    // The WORD across a bar through the centre — the thing the stamp says,
    // and legible at any size because it is the largest text on it.
    final hasDetail = detail != null && detail!.isNotEmpty;
    final bar = Rect.fromCenter(
      center: c - Offset(0, hasDetail ? r * 0.1 : 0),
      width: r * 1.78,
      height: r * 0.44,
    );
    canvas.drawRect(bar, Paint()..color = ink);
    _label(canvas, word, bar, r * 0.3, knockout: true);

    if (hasDetail) {
      final below = Rect.fromCenter(
        center: c + Offset(0, r * 0.33),
        width: r * 1.0,
        height: r * 0.22,
      );
      _label(canvas, detail!, below, r * 0.2);
    }
  }

  void _box(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer.deflate(1.5), Radius.circular(size.height * 0.12)),
      _stroke..strokeWidth = size.height * 0.07,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer.deflate(size.height * 0.16), Radius.circular(size.height * 0.06)),
      _stroke..strokeWidth = size.height * 0.03,
    );
    _label(canvas, word, outer.deflate(size.height * 0.2), size.height * 0.4);
  }

  void _label(Canvas canvas, String text, Rect box, double fontSize, {bool knockout = false}) {
    // Shrunk to fit rather than truncated: "OPENIN" on a stamp is a broken
    // stamp.
    TextPainter layout(double fs) => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: knockout ? Colors.white : color.withValues(alpha: 0.92),
              fontSize: fs,
              fontWeight: FontWeight.w800,
              letterSpacing: fs * 0.06,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
    var fs = fontSize;
    var tp = layout(fs);
    final room = box.width - box.height * 0.5;
    while (tp.width > room && fs > 3) {
      fs *= 0.92;
      tp = layout(fs);
    }
    if (knockout) {
      // Punched out of the bar, so the paper shows through the letters.
      canvas.saveLayer(box, Paint()..blendMode = BlendMode.dstOut);
      tp.paint(canvas, box.center - Offset(tp.width / 2, tp.height / 2));
      canvas.restore();
    } else {
      tp.paint(canvas, box.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// Worn rubber: a deterministic scatter of tiny voids, denser toward one
  /// edge where a hand leans. Same seed, same wear.
  void _wear(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final erase = Paint()..blendMode = BlendMode.dstOut;
    final lean = rnd.nextDouble() * math.pi * 2;
    final n = (size.width * size.height / 38).clamp(20, 900).toInt();
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final toward = math.cos(math.atan2(y - size.height / 2, x - size.width / 2) - lean);
      if (rnd.nextDouble() > 0.35 + 0.35 * toward) continue;
      final r = 0.35 + rnd.nextDouble() * size.width * 0.012;
      erase.color = Colors.black.withValues(alpha: 0.55 + rnd.nextDouble() * 0.45);
      canvas.drawCircle(Offset(x, y), r, erase);
    }
  }

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.color != color ||
      old.word != word ||
      old.detail != detail ||
      old.shape != shape ||
      old.seed != seed;
}

/// The instrument itself: paper lifted off the security tint, a hairline
/// engraved border, and — when [certify] is set — a guilloché field behind
/// the top of the panel, where the one figure it certifies sits.
class InstrumentPanel extends StatelessWidget {
  const InstrumentPanel({
    super.key,
    required this.child,
    this.certify = true,
    this.fieldHeight = 150,
    this.padding,
  });

  final Widget child;
  final bool certify;
  final double fieldHeight;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: palette.lineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.06,
            ),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (certify)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: fieldHeight,
              child: const GuillocheField(),
            ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );
  }
}

/// The mark a ledger entry hangs by: a round ink node carrying the entry's
/// direction glyph, tinted in the direction's ink. One widget for every list
/// that shows entries — the account's spine, the dashboard, Activity — so the
/// same entry wears the same mark wherever it appears. Opaque, so a ledger
/// spine drawn behind it passes under it.
class DirectionNode extends StatelessWidget {
  const DirectionNode({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.border,
    this.size = 34,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final Color border;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(background, context.colors.surface),
        shape: BoxShape.circle,
        border: Border.all(color: border),
      ),
      child: Icon(icon, size: size * 0.47, color: foreground),
    );
  }
}

/// The fixed columns every ledger row lays its right-hand side out on, so a list
/// reads as a table: stamps in one column, amounts right-aligned in the next,
/// whatever each row's figure happens to be. Without them each stamp sat
/// against its own amount and the column wandered row by row.
abstract final class LedgerColumns {
  /// The stamp's slot: reserved on every row, stamped or not.
  static const double stamp = 48;

  /// The amount column: wide enough for `₹1,30,721.68` and its ≈ line.
  static double amount(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ? 104 : 148;
}

/// A row's stamp, centred in its fixed slot — or the empty slot, so the
/// amount column never shifts.
class StampSlot extends StatelessWidget {
  const StampSlot({super.key, this.stamp});

  final Widget? stamp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: LedgerColumns.stamp,
      child: stamp == null ? null : Center(child: Opacity(opacity: 0.85, child: stamp)),
    );
  }
}
