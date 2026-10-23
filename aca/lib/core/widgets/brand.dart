import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The exact current Counterbase Android product icon, shared with the launcher.
class AcaMark extends StatelessWidget {
  const AcaMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Image.asset(
      'assets/images/counterbase_icon.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Counterbase',
    ),
  );
}

/// Mark + wordmark lockup used on splash, sign-in and lock screens.
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
        const SizedBox(height: 16),
        Text(
          'ACA',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: math.max(26, markSize * 0.42),
            fontWeight: FontWeight.w800,
            letterSpacing: 3.2,
            color: p.text,
          ),
        ),
        if (showSubtitle) ...[
          const SizedBox(height: 4),
          Text(
            'Axon Counterbase Admin',
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 13,
              color: p.textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }
}
