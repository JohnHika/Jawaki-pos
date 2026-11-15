import 'package:axon_pos/features/subscription/domain/subscription_plans.dart';
import 'package:axon_pos/features/subscription/presentation/desktop/desktop_subscription_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

const _green = Color(0xFF2E9E6B);
const _amber = Color(0xFFE0A100);

final _invoices = [
  const DesktopInvoice(
    id: 'inv-1',
    description: 'Subscription, CORE, October',
    dateLabel: 'Oct 3, 2026',
    dateSort: 1790000000000,
    amountLabel: 'KES 3000',
    amountSort: 3000,
    statusLabel: 'Active',
    statusColor: _green,
  ),
  const DesktopInvoice(
    id: 'inv-2',
    description: 'Workspace activation',
    dateLabel: 'Sep 12, 2026',
    dateSort: 1787000000000,
    amountLabel: 'KES 35000',
    amountSort: 35000,
    statusLabel: 'Past Due',
    statusColor: _amber,
  ),
];

DesktopSubscriptionView _view({
  bool trial = true,
  List<DesktopInvoice>? invoices,
  String? error,
  bool noPlan = false,
  VoidCallback? onChoosePlan,
}) =>
    DesktopSubscriptionView(
      planName: noPlan ? null : 'CORE',
      statusLabel: trial ? 'Free Trial' : 'Active',
      statusColor: _green,
      priceLabel: 'KES 3,000',
      dateCaption: trial ? 'Trial ends' : 'Next billing',
      dateLabel: 'Nov 20, 2026',
      pendingPlanLabel: trial ? 'Business' : null,
      features: [for (final f in kAvailablePlans.first.features) f.text],
      invoices: invoices ?? _invoices,
      error: error,
      onChoosePlan: trial ? (onChoosePlan ?? () {}) : null,
      paidPlanNote: !trial,
      onRefresh: () {},
      onRetry: () {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('desktop-subscription', () => _view());
  shotMatrix('desktop-subscription-paid', () => _view(trial: false));
  shotMatrix('desktop-subscription-empty', () => _view(invoices: const []));

  testWidgets('a click picks an invoice, Esc brings the plan back',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view()));
    await tester.pumpAndSettle();
    expect(find.text('Included in CORE'), findsOneWidget);

    await tester.tap(find.text('Workspace activation'));
    await tester.pumpAndSettle();
    expect(find.text('Included in CORE'), findsNothing);
    expect(find.text('Invoice'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Included in CORE'), findsOneWidget);
  });

  testWidgets('a trial can choose its next plan, a paid shop cannot',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var chosen = 0;
    await tester.pumpWidget(desktopApp(_view(onChoosePlan: () => chosen++)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose plan'));
    expect(chosen, 1);

    await tester.pumpWidget(desktopApp(_view(trial: false)));
    await tester.pumpAndSettle();
    expect(find.text('Choose plan'), findsNothing);
    expect(find.textContaining('Plan changes are not available'),
        findsOneWidget);
  });

  testWidgets('a plan that could not load shows the error and retry',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(
        desktopApp(_view(noPlan: true, error: 'Could not reach the server.')));
    await tester.pumpAndSettle();
    expect(find.text('Could not load subscription details'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
