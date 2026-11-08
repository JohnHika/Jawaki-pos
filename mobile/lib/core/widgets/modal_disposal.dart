import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Disposes text controllers (or other notifiers) that a sheet or dialog
/// used, once it has really gone.
///
/// `await showModalBottomSheet(...)` and `await showDialog(...)` return as
/// soon as the route is popped, but the route keeps rebuilding its fields
/// while it animates out (the keyboard closing triggers those rebuilds).
/// Disposing at that moment throws "used after being disposed" and blanks the
/// screen, which is how "Save till close" crashed on a phone.
///
/// Pass the sheet's [route] (`ModalRoute.of(context)` inside its builder)
/// when it is at hand: the controllers then go exactly when the route is
/// removed. Without it they go once the closing animation has finished.
void disposeAfterModalCloses(
  Iterable<ChangeNotifier> notifiers, {
  ModalRoute<dynamic>? route,
}) {
  final pending = notifiers.toList(growable: false);
  void disposeAll() {
    for (final notifier in pending) {
      notifier.dispose();
    }
  }

  if (route != null) {
    route.completed.whenComplete(disposeAll);
  } else {
    _afterAnimationsSettle().then((_) => disposeAll());
  }
}

/// Waits for frames until no animation is running (a popped sheet or dialog
/// animates out over a few frames), then one more frame so the closed route
/// is removed from the screen. Frames, not a timer: a timer would outlive a
/// widget test. Capped so an endless animation elsewhere (a spinner) cannot
/// keep the controllers alive.
Future<void> _afterAnimationsSettle() async {
  final scheduler = SchedulerBinding.instance;
  for (var frame = 0; frame < 90; frame++) {
    await scheduler.endOfFrame;
    if (scheduler.transientCallbackCount == 0) break;
  }
  await scheduler.endOfFrame;
}
