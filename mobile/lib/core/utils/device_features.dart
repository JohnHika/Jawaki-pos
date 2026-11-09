import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// What this device can do that the Windows edition cannot yet.
///
/// The phone and the computer share one app. Features whose plugin has no
/// Windows version are hidden on a computer instead of failing when tapped.
class DeviceFeatures {
  const DeviceFeatures._();

  static bool get isPhone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isComputer =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Google's account picker exists only on phones in this build.
  static bool get googleSignIn => isPhone;

  /// Camera barcode reading. A computer takes codes from a USB scanner.
  static bool get cameraScanner => isPhone;

  /// Taking a photo. A computer chooses a picture file instead.
  static bool get cameraCapture => isPhone;

  /// Reading text from a photo without Axon AI (phone only).
  static bool get onDeviceTextReading => isPhone;
}
