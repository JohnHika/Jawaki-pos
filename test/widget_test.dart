import 'package:flutter_test/flutter_test.dart';
import 'package:jawaki_admin/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const JawakiAdminApp());
    await tester.pumpAndSettle();

    // Verify the app renders
    expect(find.byType(JawakiAdminApp), findsOneWidget);
  });
}
