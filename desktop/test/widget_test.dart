import 'package:axon_pos_desktop/core/desktop_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop workspace is assigned to its local branch', () {
    expect(localWorkspaceBranchId, 'local-main');
  });
}
