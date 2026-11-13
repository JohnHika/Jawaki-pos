import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/design_system.dart';
import 'desktop_layout.dart';

/// One finished barcode scan.
@immutable
class ScanEvent {
  const ScanEvent({required this.code, required this.at, this.repeat = false});

  /// The characters the scanner typed, without the Enter that ended them.
  final String code;

  /// When the terminating Enter arrived (platform time stamp, or the app's own
  /// clock when the platform gives none).
  final Duration at;

  /// The same code scanned again within [ScanCapture.duplicateWindow]. The
  /// caller treats it as "one more" of the same item, never a new line.
  final bool repeat;

  @override
  String toString() => 'ScanEvent($code${repeat ? ', repeat' : ''})';
}

/// Recognises a USB / Bluetooth "keyboard wedge" barcode scanner.
///
/// A wedge scanner is a keyboard: it types the barcode very fast and ends with
/// Enter. The only way to tell it from a person is timing, so this listens to
/// every key press ([HardwareKeyboard.addHandler]) and decides:
///
///  * a **burst** is characters arriving with gaps of at most [maxGap]
///    (default 50 ms; a person does not type that fast, a scanner types a
///    character every 5 to 30 ms);
///  * a burst that reaches [minLength] characters and ends with Enter is a
///    **scan** and is delivered to [onScan];
///  * everything else is left alone, so normal typing, shortcuts and arrow keys
///    reach the page untouched.
///
/// Scan characters never stay in a text field. The first two characters of a
/// burst have already reached the focused field before the burst can be told
/// from typing; the field's text is put back as it was when the scan ends. From
/// the third character on, the keys are swallowed so they cannot trigger
/// shortcuts or land in a field. The scanner's Enter is swallowed too, so it
/// cannot submit a form.
///
/// A scanner must be set to send Enter after the code (the usual factory
/// setting); without it nothing is recognised and the digits would be lost.
class ScanCapture {
  ScanCapture({
    required this.onScan,
    this.enabled,
    this.onBurst,
    this.minLength = 6,
    this.maxLength = 64,
    this.maxGap = const Duration(milliseconds: 50),
    this.duplicateWindow = const Duration(milliseconds: 300),
  });

  /// Called for every recognised scan.
  final ValueChanged<ScanEvent> onScan;

  /// Asked before every key. Return false while another page, a dialog or a
  /// payment form should keep the keyboard to itself. Null means always on.
  final bool Function()? enabled;

  /// Called once, when the second fast character shows that a scanner (not a
  /// person) is typing. Shortcut keys that act on a single digit use it to
  /// back out of the first character.
  final VoidCallback? onBurst;

  final int minLength;
  final int maxLength;
  final Duration maxGap;
  final Duration duplicateWindow;

  /// Characters 1 and 2 of a burst reach the page; the third and later do not.
  static const int _swallowFrom = 3;

  final StringBuffer _buffer = StringBuffer();
  final Stopwatch _wall = Stopwatch()..start();
  Duration? _lastStamp;
  Duration _lastWall = Duration.zero;
  _FieldSnapshot? _snapshot;
  String? _lastCode;
  Duration? _lastScanAt;
  bool _attached = false;

  /// True while a burst of at least two fast characters is in progress.
  bool get burstInProgress => _buffer.length >= 2;

  void attach() {
    if (_attached) return;
    _attached = true;
    HardwareKeyboard.instance.addHandler(handle);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    HardwareKeyboard.instance.removeHandler(handle);
    _reset();
  }

  void _reset() {
    _buffer.clear();
    _snapshot = null;
  }

  /// The key handler. Public so tests can feed recorded key sequences.
  /// Returns true when the key was consumed (swallowed).
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent) {
      // Key-up and key-repeat: a held key is a person, not a scanner.
      if (event is KeyRepeatEvent) _reset();
      return false;
    }
    if (!(enabled?.call() ?? true)) {
      _reset();
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      _reset();
      return false;
    }
    final key = event.logicalKey;
    // A scanner sends Shift for capitals; that is part of the burst.
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.capsLock) {
      return false;
    }

    final stamp = event.timeStamp;
    final wall = _wall.elapsed;

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // Some scanners wait a little before the Enter, so it gets a longer
      // allowance than the gap between characters; a long pause is a person.
      var enterGap = wall - _lastWall;
      final lastStamp = _lastStamp;
      if (stamp > Duration.zero &&
          lastStamp != null &&
          lastStamp > Duration.zero) {
        final stampGap = stamp - lastStamp;
        if (stampGap >= Duration.zero) enterGap = stampGap;
      }
      final isScan = _buffer.length >= minLength && enterGap <= maxGap * 5;
      if (!isScan) {
        _reset();
        return false;
      }
      final code = _buffer.toString();
      final at = stamp > Duration.zero ? stamp : wall;
      final repeat = code == _lastCode &&
          _lastScanAt != null &&
          (at - _lastScanAt!) >= Duration.zero &&
          (at - _lastScanAt!) <= duplicateWindow;
      _lastCode = code;
      _lastScanAt = at;
      _snapshot?.restoreIfLeaked();
      _reset();
      onScan(ScanEvent(code: code, at: at, repeat: repeat));
      return true;
    }

    final ch = event.character;
    if (ch == null || ch.isEmpty || ch.runes.length != 1 || _isControl(ch)) {
      _reset();
      return false;
    }

    if (_buffer.isEmpty) {
      _begin(ch, stamp, wall);
      return false;
    }

    var gap = wall - _lastWall;
    final last = _lastStamp;
    if (stamp > Duration.zero && last != null && last > Duration.zero) {
      final stampGap = stamp - last;
      if (stampGap >= Duration.zero) gap = stampGap;
    }
    if (gap > maxGap) {
      _reset();
      _begin(ch, stamp, wall);
      return false;
    }

    _buffer.write(ch);
    _lastStamp = stamp;
    _lastWall = wall;
    if (_buffer.length > maxLength) {
      _reset();
      return false;
    }
    if (_buffer.length == 2) onBurst?.call();
    return _buffer.length >= _swallowFrom;
  }

  void _begin(String ch, Duration stamp, Duration wall) {
    _buffer
      ..clear()
      ..write(ch);
    _lastStamp = stamp;
    _lastWall = wall;
    _snapshot = _FieldSnapshot.capture();
  }

  static bool _isControl(String ch) {
    final code = ch.runes.first;
    return code < 0x20 || code == 0x7f;
  }
}

/// The text of the field that had focus when a burst began, so the one or two
/// characters that slipped in before the burst was recognised can be undone.
class _FieldSnapshot {
  _FieldSnapshot(this.node, this.controller, this.value);

  final FocusNode node;
  final TextEditingController controller;
  final TextEditingValue value;

  static _FieldSnapshot? capture() {
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    if (node == null || context == null) return null;
    EditableTextState? state;
    if (context is StatefulElement && context.state is EditableTextState) {
      state = context.state as EditableTextState;
    } else {
      state = context.findAncestorStateOfType<EditableTextState>();
    }
    if (state == null) return null;
    final controller = state.widget.controller;
    return _FieldSnapshot(node, controller, controller.value);
  }

  void restoreIfLeaked() {
    if (FocusManager.instance.primaryFocus != node) return;
    final now = controller.value;
    if (now.text != value.text && now.text.length <= value.text.length + 2) {
      controller.value = value;
    }
  }
}

/// The status-bar readout "Scanner ready" that flashes the code on every scan.
///
/// Publish it while a page that takes scans is on screen and remove it when the
/// page goes away ([dispose]).
class ScannerStatus {
  ScannerStatus({this.id = 'scanner'});

  final String id;
  Timer? _timer;
  bool _disposed = false;

  /// Shows "Scanner ready". Safe to call from initState: the publish is
  /// deferred until after the frame so the shell is not rebuilt mid-build.
  void show() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _publish(ready: true);
    });
    // Called outside a frame (a test, a timer) the callback would otherwise
    // wait for the next unrelated frame.
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Flashes the scanned code, then goes back to "Scanner ready".
  void flash(String code) {
    if (_disposed) return;
    _timer?.cancel();
    _publish(ready: false, code: code);
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (!_disposed) _publish(ready: true);
    });
  }

  void _publish({required bool ready, String? code}) {
    DesktopStatusRegistry.set(
      DesktopStatusEntry(
        id: id,
        label: ready ? 'Scanner ready' : 'Scanned $code',
        icon: Icons.qr_code_scanner_rounded,
        color: ready ? null : DesignColors.success,
        tooltip: ready
            ? 'Barcode scanner: scan an item to add it to the sale'
            : 'Barcode $code scanned',
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    DesktopStatusRegistry.remove(id);
  }
}
