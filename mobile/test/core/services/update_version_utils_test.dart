import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/services/update_version_utils.dart';

void main() {
  group('composeComparableVersion', () {
    test('includes the build number when one exists', () {
      expect(composeComparableVersion('1.0.2', '2003'), '1.0.2+2003');
    });

    test('returns the semantic version when the build number is empty', () {
      expect(composeComparableVersion('1.0.2', ''), '1.0.2');
    });
  });

  group('isNewerAppVersion', () {
    test('treats a higher build number as newer within the same semantic version', () {
      expect(isNewerAppVersion('1.0.2+2004', '1.0.2+2003'), isTrue);
    });

    test('treats a lower build number as not newer within the same semantic version', () {
      expect(isNewerAppVersion('1.0.2+2003', '1.0.2+2004'), isFalse);
    });

    test('treats a higher semantic version as newer regardless of build metadata', () {
      expect(isNewerAppVersion('1.0.3', '1.0.2+9999'), isTrue);
    });
  });
}
