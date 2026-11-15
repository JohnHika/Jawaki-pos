import 'package:axon_pos/features/licence/presentation/desktop/desktop_plan_licence_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

Widget _view({
  TextEditingController? code,
  String? error,
  bool busy = false,
  bool paused = false,
  VoidCallback? onApply,
}) =>
    DesktopPlanLicenceView(
      statusLabel: paused ? 'New sales paused' : 'Active',
      statusColor: paused ? const Color(0xFFD94B4B) : const Color(0xFF2E9E6B),
      sellingOn: !paused,
      detail: paused
          ? 'Pay to start selling again. Your records are safe and you can still view and export them.'
          : 'Next payment due 5 Dec 2026 (21 days).',
      planLabel: 'Core',
      dueCaption: 'Next payment due',
      dueLabel: '5 Dec 2026',
      timeLeft: '21 days',
      shopId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      codeController: code ?? TextEditingController(),
      graceDays: 3,
      error: error,
      busy: busy,
      onPaste: () {},
      onApply: onApply ?? () {},
      onCopyShopId: () {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('desktop-plan-licence', () => _view());
  shotMatrix(
    'desktop-plan-licence-paused',
    () => _view(
      paused: true,
      error: 'That code is not valid. Ask us for a new one.',
    ),
  );

  testWidgets('Apply code and Ctrl+Enter both call apply', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var applied = 0;
    await tester.pumpWidget(desktopApp(_view(onApply: () => applied++)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply code'));
    expect(applied, 1);
    await tester.tap(find.byType(TextField));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(applied, 2);
  });
}
