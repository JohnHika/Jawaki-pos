import 'package:axon_pos_desktop/core/desktop_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes a POS server address to the public API base path', () {
    expect(
      normalizeApiUrl('https://example.com/'),
      'https://example.com/api/v1',
    );
    expect(
      normalizeApiUrl('https://example.com/api/v1'),
      'https://example.com/api/v1',
    );
  });
}
