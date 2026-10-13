import 'package:axon_pos/core/widgets/motion_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CountUpText.parse', () {
    test('splits prefix, grouped number and suffix', () {
      final p = CountUpText.parse('KES 12,345.50 today')!;
      expect(p.prefix, 'KES ');
      expect(p.value, 12345.5);
      expect(p.decimals, 2);
      expect(p.grouped, isTrue);
      expect(p.suffix, ' today');
    });

    test('returns null when there is no number', () {
      expect(CountUpText.parse('No sales'), isNull);
    });
  });

  testWidgets('CountUpText settles on the exact final text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: CountUpText('KES 2,090'))));
    await tester.pumpAndSettle();
    expect(find.text('KES 2,090'), findsOneWidget);
  });

  testWidgets('animations land on their final state with reduced motion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: FadeSlideIn(child: PopIn(child: Text('hello'))),
        ),
      ),
    ));
    // No pumps beyond the first frame: it must already be fully visible.
    final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity.opacity, 1.0);
  });

  testWidgets('finite animations let pumpAndSettle finish', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          FadeSlideIn(child: Text('a')),
          PopIn(child: Text('b')),
          Floating(child: Text('c')),
          RippleRings(child: AnimatedCheckmark()),
          PulseDot(),
          AnimatedProgressBar(value: 0.5),
        ]),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('attention/decoration animations are finite and keep their child',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Wiggle(child: Text('w')),
          BreathingGlow(child: Text('b')),
          ShimmerSweep(child: Text('s')),
          DrawIn(),
        ]),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('w'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('s'), findsOneWidget);
  });
}
