import 'package:flutter/material.dart';

/// Stable GlobalKeys for the specific bottom-nav destinations the staff
/// first-login coach-mark tour spotlights. Kept as static finals (created
/// once, not derived from HomeScreen's per-build nav item list) so the
/// same key identity survives rebuilds and can be referenced from outside
/// HomeScreen without threading state through it.
///
/// Only items actually targeted by a tour step need a key here — not
/// every nav destination.
class HomeNavKeys {
  HomeNavKeys._();

  static final pos = GlobalKey(debugLabel: 'nav-pos');
  static final more = GlobalKey(debugLabel: 'nav-more');

  // Live inside the "More" bottom sheet, not the main bottom bar — only
  // mounted while that sheet is open. The tour opens the sheet via
  // CoachMarkStep.beforeShow before spotlighting these.
  static final moreSheetInventory = GlobalKey(debugLabel: 'nav-more-inventory');
  static final moreSheetReports = GlobalKey(debugLabel: 'nav-more-reports');
  static final moreSheetSettings = GlobalKey(debugLabel: 'nav-more-settings');

  /// External open/close signal for the "More" bottom sheet, listened to by
  /// HomeScreen's state. Exists so the tour (outside HomeScreen, which has
  /// a private State class) can drive the sheet open/closed between steps
  /// without a GlobalKey<State> or making HomeScreen's internals public.
  static final moreSheetOpenRequest = ValueNotifier<bool>(false);
}
