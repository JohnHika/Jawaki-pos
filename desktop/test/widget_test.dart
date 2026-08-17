import 'package:axon_pos_desktop/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop app loads the overview', (tester) async {
    await tester.pumpWidget(const AxonDesktopApp());

    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Good morning, John'), findsOneWidget);
  });
}
