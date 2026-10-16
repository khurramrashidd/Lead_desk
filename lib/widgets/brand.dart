import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// ---------------------------------------------------------------------------
/// AI Lead Desk mark — a speech bubble (every enquiry is a conversation) holding
/// a rising trend line (conversations that convert), with an AI sparkle.
/// The same normalised geometry generates the launcher icon and the favicon, so
/// the app, the browser tab and the phone home screen all show one mark.
/// ---------------------------------------------------------------------------
class _MarkGeometry {
  static const bubble = Rect.fromLTRB(0.170, 0.232, 0.688, 0.612);
  static const bubbleRadius = 0.098;
  static const tail = [Offset(0.300, 0.598), Offset(0.252, 0.790), Offset(0.440, 0.598)];
  static const arrow = [Offset(0.272, 0.508), Offset(0.392, 0.406), Offset(0.482, 0.470), Offset(0.628, 0.322)];
  static const head = [Offset(0.528, 0.322), Offset(0.628, 0.322), Offset(0.628, 0.422)];
  static const arrowWidth = 0.055;
  static const sparkCentre = Offset(0.806, 0.218);
  static const sparkOuter = 0.104;
  static const sparkInner = 0.030;
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.bubbleColor, required this.arrowColor, this.scale = 1.08});
  final Color bubbleColor;
  final Color arrowColor;
  final double scale;

  Offset _p(Offset o, double s) => Offset((0.5 + (o.dx - 0.5) * scale) * s, (0.5 + (o.dy - 0.5) * scale) * s);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final bubble = Paint()..color = bubbleColor..isAntiAlias = true;

    canvas.drawPath(
      Path()..addPolygon(_MarkGeometry.tail.map((p) => _p(p, s)).toList(), true),
      bubble,
    );
    final b = _MarkGeometry.bubble;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(_p(b.topLeft, s), _p(b.bottomRight, s)),
        Radius.circular(_MarkGeometry.bubbleRadius * scale * s),
      ),
      bubble,
    );

    final stroke = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _MarkGeometry.arrowWidth * scale * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final path in [_MarkGeometry.arrow, _MarkGeometry.head]) {
      final p = Path()..moveTo(_p(path.first, s).dx, _p(path.first, s).dy);
      for (final pt in path.skip(1)) {
        p.lineTo(_p(pt, s).dx, _p(pt, s).dy);
      }
      canvas.drawPath(p, stroke);
    }

    // four-point sparkle
    final c = _p(_MarkGeometry.sparkCentre, s);
    final outer = _MarkGeometry.sparkOuter * scale * s;
    final inner = _MarkGeometry.sparkInner * scale * s;
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? outer : inner;
      final a = i * math.pi / 4;
      final pt = Offset(c.dx + r * math.sin(a), c.dy - r * math.cos(a));
      i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(star..close(), bubble);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.bubbleColor != bubbleColor || old.arrowColor != arrowColor || old.scale != scale;
}

/// The product mark. [tile] draws the gradient app-icon tile behind it.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32, this.tile = true, this.color, this.inkColor});

  final double size;
  final bool tile;

  /// Mark colour when [tile] is false.
  final Color? color;

  /// Arrow colour inside the bubble.
  final Color? inkColor;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(
        bubbleColor: tile ? Colors.white : (color ?? context.scheme.primary),
        arrowColor: tile
            ? AppTheme.indigoDeep
            : (inkColor ?? (context.isDark ? const Color(0xFF14151F) : Colors.white)),
        scale: tile ? 1.08 : 1.18,
      ),
    );
    if (!tile) return mark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.2232),
        boxShadow: [
          BoxShadow(color: AppTheme.indigo.withValues(alpha: 0.35), blurRadius: size * 0.4, offset: Offset(0, size * 0.12)),
        ],
      ),
      child: mark,
    );
  }
}

/// Mark + "AI Lead Desk" wordmark.
class LeadDeskLogo extends StatelessWidget {
  const LeadDeskLogo({super.key, this.size = 30, this.showWordmark = true, this.onDark = false});
  final double size;
  final bool showWordmark;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final base = onDark ? Colors.white : context.scheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size),
        if (showWordmark) ...[
          SizedBox(width: size * 0.36),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: size * 0.56,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: base,
              ),
              children: [
                const TextSpan(text: 'AI Lead '),
                TextSpan(
                  text: 'Desk',
                  style: TextStyle(color: onDark ? const Color(0xFFA5B4FC) : AppTheme.indigo),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// SechTummit Trainers — the institute brand on the public website.
/// Three rising chevrons: the climb to the summit.
/// ---------------------------------------------------------------------------
class _SummitPainter extends CustomPainter {
  _SummitPainter(this.peak, this.body);
  final Color peak;
  final Color body;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    void chevron(double y, double halfWidth, double drop, Color color, double opacity) {
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.115 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(
        Path()
          ..moveTo((0.5 - halfWidth) * s, (y + drop) * s)
          ..lineTo(0.5 * s, y * s)
          ..lineTo((0.5 + halfWidth) * s, (y + drop) * s),
        paint,
      );
    }

    chevron(0.70, 0.355, 0.165, body, 0.35);
    chevron(0.47, 0.265, 0.155, body, 1.0);
    chevron(0.20, 0.175, 0.145, peak, 1.0);
  }

  @override
  bool shouldRepaint(_SummitPainter old) => old.peak != peak || old.body != body;
}

class SummitMark extends StatelessWidget {
  const SummitMark({super.key, this.size = 34, this.onDark = false});
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SummitPainter(AppTheme.amber, onDark ? Colors.white : AppTheme.navy),
      );
}

/// Mark + "SechTummit Trainers" wordmark for the institute website.
class InstituteLogo extends StatelessWidget {
  const InstituteLogo({super.key, this.size = 34, this.onDark = false, this.compact = false});
  final double size;
  final bool onDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strong = onDark ? Colors.white : AppTheme.navy;
    final soft = onDark ? Colors.white70 : AppTheme.navy.withValues(alpha: 0.62);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SummitMark(size: size, onDark: onDark),
        SizedBox(width: size * 0.3),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SechTummit',
              style: TextStyle(
                fontSize: size * 0.56,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: strong,
              ),
            ),
            if (!compact)
              Text(
                'TRAINERS',
                style: TextStyle(
                  fontSize: size * 0.27,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: size * 0.095,
                  color: soft,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Paints text with the brand gradient. Used sparingly, for one phrase per page.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style, this.gradient});
  final String text;
  final TextStyle style;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (bounds) => (gradient ??
                const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFFC4B5FD), Color(0xFFFBBF24)]))
            .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        blendMode: BlendMode.srcIn,
        child: Text(text, style: style.copyWith(color: Colors.white)),
      );
}
