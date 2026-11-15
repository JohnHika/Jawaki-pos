import 'package:axon_pos/features/subscription/presentation/desktop/desktop_plan_selection_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

/// Holds the choice the way the routed screen does.
class _Host extends StatefulWidget {
  const _Host({this.error, this.onContinue});

  final String? error;
  final VoidCallback? onContinue;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? _plan = 'business';
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => DesktopPlanSelectionView(
        companyName: 'Njeri Hardware',
        selectedPlanId: _plan,
        onSelectPlan: (id) => setState(() {
          if (_plan != id) _accepted = false;
          _plan = id;
        }),
        acceptedTerms: _accepted,
        onAcceptTerms: (v) => setState(() => _accepted = v),
        termsLabel: const Text('I agree to the billing terms for the plan shown.'),
        termsLink: const Text('Read subscription and billing terms'),
        setupFeeLabel: 'KSh 35,000',
        error: widget.error,
        onContinue: _plan != null && _accepted
            ? (widget.onContinue ?? () {})
            : null,
      );
}

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('desktop-plan-selection', () => const _Host());
  shotMatrix(
    'desktop-plan-selection-error',
    () => const _Host(error: 'Server error. Please try again in a moment.'),
  );

  testWidgets('Continue needs the terms, and picking another plan clears them',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var continued = 0;
    await tester.pumpWidget(
      desktopApp(_Host(onContinue: () => continued++)),
    );
    await tester.pumpAndSettle();

    FilledButton button() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue with this plan'));
    expect(button().onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(continued, 1);

    await tester.tap(find.text('ENTERPRISE').last);
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
  });
}
