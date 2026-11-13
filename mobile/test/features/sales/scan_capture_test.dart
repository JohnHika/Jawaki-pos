import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/scan_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recorded key sequence: the characters and the time each one arrived.
class _Key {
  const _Key(this.char, this.ms);
  final String char; // '\n' is Enter
  final int ms;
}

/// Builds a burst of [text] starting at [start] ms with a fixed [gap], then an
/// Enter after one more gap.
List<_Key> _burst(String text, {int start = 0, int gap = 15, bool enter = true}) {
  final keys = <_Key>[];
  var t = start;
  for (final ch in text.split('')) {
    keys.add(_Key(ch, t));
    t += gap;
  }
  if (enter) keys.add(_Key('\n', t));
  return keys;
}

KeyDownEvent _down(_Key key) {
  if (key.char == '\n') {
    return KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration(milliseconds: key.ms),
    );
  }
  return KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: LogicalKeyboardKey(key.char.codeUnitAt(0)),
    character: key.char,
    timeStamp: Duration(milliseconds: key.ms),
  );
}

/// Feeds [keys] to [capture]; returns, per key, whether it was swallowed.
List<bool> _feed(ScanCapture capture, List<_Key> keys) =>
    [for (final key in keys) capture.handle(_down(key))];

void main() {
  late List<ScanEvent> scans;
  late ScanCapture capture;

  setUp(() {
    scans = [];
    capture = ScanCapture(onScan: scans.add);
  });

  group('timing heuristic', () {
    test('a fast burst of 13 digits ending in Enter is one scan', () {
      final swallowed = _feed(capture, _burst('6001234567893'));
      expect(scans.map((s) => s.code), ['6001234567893']);
      // Characters 1 and 2 have to reach the page (a person typing looks the
      // same at that point); 3 onwards and the Enter are swallowed.
      expect(swallowed.take(2), [false, false]);
      expect(swallowed.skip(2), everyElement(isTrue));
    });

    test('a scanner at the slow end (45 ms between keys) still counts', () {
      _feed(capture, _burst('6001234567', gap: 45));
      expect(scans.map((s) => s.code), ['6001234567']);
    });

    test('typing at 120 ms per key is never a scan and nothing is swallowed',
        () {
      final swallowed = _feed(capture, _burst('sugar2kg', gap: 120));
      expect(scans, isEmpty);
      expect(swallowed, everyElement(isFalse));
    });

    test('a very fast typist at 70 ms per key is still not a scan', () {
      final swallowed = _feed(capture, _burst('maizeflour', gap: 70));
      expect(scans, isEmpty);
      expect(swallowed, everyElement(isFalse));
    });

    test('a burst shorter than 6 characters is not a scan', () {
      final swallowed = _feed(capture, _burst('60012'));
      expect(scans, isEmpty);
      // The Enter is not swallowed either, so a short code typed by hand
      // still submits whatever field it was typed in.
      expect(swallowed.last, isFalse);
    });

    test('exactly 6 characters is the shortest scan', () {
      _feed(capture, _burst('600123'));
      expect(scans.map((s) => s.code), ['600123']);
    });

    test('one slow gap in the middle restarts the burst', () {
      // 4 fast digits, a 80 ms pause, then 3 fast digits + Enter: neither half
      // is long enough, so no scan.
      final keys = [
        ..._burst('6001', enter: false),
        ..._burst('234', start: 45 + 80, enter: true),
      ];
      _feed(capture, keys);
      expect(scans, isEmpty);
    });

    test('a person typing, then a scan, then typing again', () {
      _feed(capture, _burst('su', gap: 130, enter: false));
      _feed(capture, _burst('5449000000996', start: 600));
      _feed(capture, _burst('ga', start: 1500, gap: 140, enter: false));
      expect(scans.map((s) => s.code), ['5449000000996']);
    });

    test('Enter alone, or a long pause before Enter, is not a scan', () {
      _feed(capture, [const _Key('\n', 0)]);
      expect(scans, isEmpty);
      final keys = [
        ..._burst('6001234567', enter: false),
        const _Key('\n', 9 * 15 + 600),
      ];
      final swallowed = _feed(capture, keys);
      expect(scans, isEmpty);
      // The Enter then belongs to whatever field has focus.
      expect(swallowed.last, isFalse);
    });

    test('an Enter 120 ms after the last digit still ends the scan', () {
      final keys = [
        ..._burst('6001234567', enter: false),
        const _Key('\n', 9 * 15 + 120),
      ];
      _feed(capture, keys);
      expect(scans.map((s) => s.code), ['6001234567']);
    });

    test('capital letters from Shift are part of the burst', () {
      final keys = _burst('AB1234');
      final events = <bool>[];
      for (final key in keys) {
        events.add(capture.handle(_down(key)));
      }
      expect(scans.single.code, 'AB1234');
    });

    test('arrow, tab and function keys end a burst without a scan', () {
      _feed(capture, _burst('600123', enter: false));
      final consumed = capture.handle(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration(milliseconds: 100),
      ));
      expect(consumed, isFalse);
      capture.handle(_down(const _Key('\n', 110)));
      expect(scans, isEmpty);
    });

    test('key repeat (a held key) is a person', () {
      _feed(capture, _burst('600123', enter: false));
      capture.handle(const KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.digit3,
        character: '3',
        timeStamp: Duration(milliseconds: 100),
      ));
      capture.handle(_down(const _Key('\n', 110)));
      expect(scans, isEmpty);
    });
  });

  group('duplicate scans', () {
    test('the same code within 300 ms is flagged as a repeat', () {
      // The first Enter lands at 195 ms; the second scan's Enter 210 ms later.
      _feed(capture, _burst('6001234567893'));
      _feed(capture, _burst('6001234567893', start: 210));
      expect(scans, hasLength(2));
      expect(scans[0].repeat, isFalse);
      expect(scans[1].repeat, isTrue);
    });

    test('the same code after 300 ms is a fresh scan', () {
      _feed(capture, _burst('6001234567893'));
      _feed(capture, _burst('6001234567893', start: 500));
      expect(scans[1].repeat, isFalse);
    });

    test('a different code is never a repeat', () {
      _feed(capture, _burst('6001234567893'));
      _feed(capture, _burst('6001234567800', start: 250));
      expect(scans[1].repeat, isFalse);
    });
  });

  group('on and off', () {
    test('a disabled capture ignores everything', () {
      var on = false;
      final gated = ScanCapture(onScan: scans.add, enabled: () => on);
      final swallowed = _feed(gated, _burst('6001234567'));
      expect(scans, isEmpty);
      expect(swallowed, everyElement(isFalse));
      on = true;
      _feed(gated, _burst('6001234567', start: 1000));
      expect(scans, hasLength(1));
    });

    test('onBurst fires once, on the second fast character', () {
      var bursts = 0;
      final watching = ScanCapture(onScan: scans.add, onBurst: () => bursts++);
      watching.handle(_down(const _Key('6', 0)));
      expect(bursts, 0);
      watching.handle(_down(const _Key('0', 12)));
      expect(bursts, 1);
      _feed(watching, _burst('01234', start: 24));
      expect(bursts, 1);
    });
  });

  group('in a real text field', () {
    testWidgets('scan characters never stay in a field and the scan arrives',
        (tester) async {
      final controller = TextEditingController(text: 'ab');
      final focus = FocusNode();
      final submitted = <String>[];
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final live = ScanCapture(onScan: scans.add)..attach();
      addTearDown(live.detach);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            focusNode: focus,
            onSubmitted: submitted.add,
          ),
        ),
      ));
      focus.requestFocus();
      await tester.pump();

      // Real key events: the test binding stamps them all with the same time,
      // so the capture falls back to its own clock and sees a machine-speed
      // burst.
      for (final ch in '6001234567893'.split('')) {
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey(ch.codeUnitAt(0)),
          character: ch,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey(ch.codeUnitAt(0)));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(scans.map((s) => s.code), ['6001234567893']);
      expect(controller.text, 'ab', reason: 'the field is back as it was');
      expect(submitted, isEmpty, reason: 'the scanner Enter is swallowed');
    });

    testWidgets('a field that is not the search field is protected too',
        (tester) async {
      final quantity = TextEditingController();
      final focus = FocusNode();
      addTearDown(quantity.dispose);
      addTearDown(focus.dispose);
      final live = ScanCapture(onScan: scans.add)..attach();
      addTearDown(live.detach);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const TextField(key: ValueKey('search')),
            TextField(key: const ValueKey('qty'), controller: quantity, focusNode: focus),
          ]),
        ),
      ));
      focus.requestFocus();
      await tester.pump();

      for (final ch in '5449000000996'.split('')) {
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey(ch.codeUnitAt(0)),
          character: ch,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(scans.single.code, '5449000000996');
      expect(quantity.text, isEmpty);
    });
  });

  group('status bar readout', () {
    testWidgets('publishes Scanner ready and removes it on dispose',
        (tester) async {
      final status = ScannerStatus();
      DesktopStatusRegistry.entries.value = const [];
      await tester.pumpWidget(const SizedBox());
      status.show();
      await tester.pump();
      var entry = DesktopStatusRegistry.entries.value
          .singleWhere((e) => e.id == 'scanner');
      expect(entry.label, 'Scanner ready');

      status.flash('6001234567893');
      entry = DesktopStatusRegistry.entries.value
          .singleWhere((e) => e.id == 'scanner');
      expect(entry.label, contains('6001234567893'));

      await tester.pump(const Duration(seconds: 2));
      entry = DesktopStatusRegistry.entries.value
          .singleWhere((e) => e.id == 'scanner');
      expect(entry.label, 'Scanner ready');

      status.dispose();
      expect(DesktopStatusRegistry.entries.value.where((e) => e.id == 'scanner'),
          isEmpty);
    });
  });
}
