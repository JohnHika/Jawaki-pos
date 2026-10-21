import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The ACA brand mark: an "A" whose crossbar is the counter. Drawn in code so it
/// stays crisp at any size and matches the launcher icon exactly.
class AcaMark extends StatelessWidget {
  const AcaMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter()),
      );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final tile = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(24 * s));
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFA166), Color(0xFFE0611E)],
        ).createShader(Offset.zero & size),
    );

    final stroke = Paint()
      ..color = const Color(0xFF0B0A0F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final a = Path()
      ..moveTo(27 * s, 76 * s)
      ..lineTo(50 * s, 24 * s)
      ..lineTo(73 * s, 76 * s);
    canvas.drawPath(a, stroke);
    // The counter: crossbar of the A.
    canvas.drawLine(Offset(37 * s, 60 * s), Offset(63 * s, 60 * s), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mark + wordmark lockup used on the splash, sign-in and lock screens.
class AcaLockup extends StatelessWidget {
  const AcaLockup({super.key, this.markSize = 72, this.showSubtitle = true});
  final double markSize;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AcaMark(size: markSize),
        const SizedBox(height: 18),
        Text('ACA',
            style: TextStyle(
                fontSize: math.max(26, markSize * 0.45), fontWeight: FontWeight.w800, letterSpacing: 4, color: p.text)),
        if (showSubtitle) ...[
          const SizedBox(height: 4),
          Text('Axon Counterbase Admin', style: TextStyle(fontSize: 14, color: p.textMuted, letterSpacing: 0.4)),
        ],
      ],
    );
  }
}
