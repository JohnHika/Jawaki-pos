import 'package:axon_pos/core/providers/local_workspace_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTPSMS settings is allowed without widening restricted paths', () {
    expect(
        LocalWorkspaceCapabilities.supportsPath('/settings/httpsms'), isTrue);
    expect(LocalWorkspaceCapabilities.supportsPath('/billing'), isFalse);
    expect(LocalWorkspaceCapabilities.supportsPath('/containers'), isFalse);
    expect(LocalWorkspaceCapabilities.supportsPath('/coupons'), isFalse);
    expect(
      LocalWorkspaceCapabilities.supportsPath('/settings/httpsms/extra'),
      isFalse,
    );
  });
}
