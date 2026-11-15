import 'package:axon_pos/features/settings/presentation/desktop/desktop_recorded_rules_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

DesktopRecordedRulesView _view({
  bool isOwner = true,
  bool saved = false,
  ValueChanged<bool>? onEnabled,
  VoidCallback? onSave,
}) =>
    DesktopRecordedRulesView(
      enabled: true,
      requireMessage: false,
      isOwner: isOwner,
      saved: saved,
      limitController: TextEditingController(text: '5000'),
      tillController: TextEditingController(text: '5 123 456'),
      onEnabledChanged: onEnabled ?? (_) {},
      onRequireMessageChanged: (_) {},
      onFieldChanged: () {},
      onSave: onSave ?? () {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('recorded-rules', () => _view());
  shotMatrix('recorded-rules-viewer', () => _view(isOwner: false, saved: true));

  testWidgets('the owner can switch the rule and save with Ctrl+S',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    bool? enabled;
    var saves = 0;
    await tester.pumpWidget(desktopApp(
      _view(onEnabled: (v) => enabled = v, onSave: () => saves++),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    expect(enabled, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(saves, 1);
    expect(find.text('Save rules'), findsOneWidget);
  });

  testWidgets('someone who is not the owner cannot change or save',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var saves = 0;
    await tester.pumpWidget(
      desktopApp(_view(isOwner: false, onSave: () => saves++)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Only the owner can change these rules.'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(saves, 0);
  });
}
