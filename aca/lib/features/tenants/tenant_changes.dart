import 'package:flutter/foundation.dart';

/// Tells the Overview and the Clients list that a company changed (suspended,
/// extended, locked out, credited...) so they can refresh quietly when the
/// user comes back to them. Screens in this feature listen; the detail screen
/// calls [bump] after every successful change.
class TenantChangeSignal extends ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void bump() {
    _count++;
    notifyListeners();
  }
}

final TenantChangeSignal tenantChanges = TenantChangeSignal();
