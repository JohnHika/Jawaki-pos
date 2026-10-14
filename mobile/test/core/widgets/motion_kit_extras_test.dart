import 'package:axon_pos/core/widgets/motion_kit_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  final entrances = <String, Widget Function()>{
    'FlipIn': () => const FlipIn(child: Text('hi')),
    'BlurIn': () => const BlurIn(child: Text('hi')),
    'WipeIn': () => const WipeIn(child: Text('hi')),
    'UnfoldIn': () => const UnfoldIn(child: Text('hi')),
    'DropIn': () => const DropIn(child: Text('hi')),
    'SwingIn': () => const SwingIn(child: Text('hi')),
    'ZoomSettle': () => const ZoomSettle(child: Text('hi')),
    'CircleReveal': () => const CircleReveal(child: Text('hi')),
    'BorderDraw': () => const BorderDraw(child: Text('hi')),
    'SwipeNudge': () => const SwipeNudge(child: Text('hi')),
    'SoftEntrance': () => const SoftEntrance(child: Text('hi')),
    'CascadeScale': () => const CascadeScale(index: 2, child: Text('hi')),
    'TiltOnDrag': () => const TiltOnDrag(child: Text('hi')),
  };

  for (final e in entrances.entries) {
    testWidgets('${e.key} settles and leaves its child on screen',
        (tester) async {
      await tester.pumpWidget(_host(e.value()));
      await tester.pumpAndSettle();
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('${e.key} is already final with reduced motion',
        (tester) async {
      await tester.pumpWidget(_host(e.value(), reduced: true));
      expect(find.text('hi'), findsOneWidget);
    });
  }

  testWidgets('LetterRise ends with every letter present and readable',
      (tester) async {
    await tester.pumpWidget(_host(const LetterRise('Karibu')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Karibu'), findsOneWidget);
    for (final ch in 'Karibu'.split('')) {
      expect(find.text(ch), findsOneWidget);
    }
  });

  testWidgets('ArcGauge animates to its value and settles', (tester) async {
    await tester.pumpWidget(_host(const ArcGauge(value: 0.6)));
    await tester.pumpAndSettle();
    expect(find.byType(ArcGauge), findsOneWidget);
  });

  testWidgets('RollingNumber shows the new value after a change',
      (tester) async {
    Widget app(String v) => _host(RollingNumber(v));
    await tester.pumpWidget(app('1,200'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1,200'), findsOneWidget);
    await tester.pumpWidget(app('1,250'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1,250'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('BumpOnChange and FlashOnChange survive repeated changes',
      (tester) async {
    Widget app(int n) => _host(Column(children: <Widget>[
          BumpOnChange(trigger: n, child: Text('n$n')),
          FlashOnChange(trigger: n, child: Text('f$n')),
        ]));
    await tester.pumpWidget(app(1));
    await tester.pumpWidget(app(2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(app(3));
    await tester.pumpAndSettle();
    expect(find.text('n3'), findsOneWidget);
    expect(find.text('f3'), findsOneWidget);
  });

  testWidgets('SkeletonSwap shows the skeleton, then the content',
      (tester) async {
    Widget app(bool loading) => _host(SkeletonSwap(
          loading: loading,
          skeleton: const Text('loading'),
          child: const Text('ready'),
        ));
    await tester.pumpWidget(app(true));
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
  });

  testWidgets('PressDepth still fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
        PressDepth(onTap: () => taps++, child: const Text('press'))));
    await tester.tap(find.text('press'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('cascaded() wraps only the first maxAnimated children',
      (tester) async {
    final kids = <Widget>[for (var i = 0; i < 5; i++) Text('c$i')];
    await tester.pumpWidget(
        _host(Column(children: kids.cascaded(maxAnimated: 2))));
    await tester.pumpAndSettle();
    expect(find.byType(CascadeScale), findsNWidgets(2));
    expect(find.text('c4'), findsOneWidget);
  });
}
