import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keep widget tests independent from the host platform's shader defaults.
///
/// Flutter's Android Material 3 default uses InkSparkle, which requires the
/// engine's compiled ink_sparkle.frag runtime asset. The headless test engine
/// does not need that visual effect and can reject the shader manifest when
/// the SDK and test engine caches differ, so use the ripple default instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await testMain();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
