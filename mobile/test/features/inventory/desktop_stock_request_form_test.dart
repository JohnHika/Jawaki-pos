import 'package:axon_pos/features/inventory/presentation/desktop/desktop_stock_request_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

class _Host extends StatefulWidget {
  const _Host({this.sent, this.log});
  final String? product = 'Brookside Milk 500ml';
  final String? sent;
  final List<String>? log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final formKey = GlobalKey<FormState>();
  final qty = TextEditingController(text: '24');
  final reason = TextEditingController();
  String priority = 'normal';

  @override
  void dispose() {
    qty.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopStockRequestForm(
        formKey: formKey,
        quantity: qty,
        reason: reason,
        unit: 'piece',
        priority: priority,
        priorities: const [
          DesktopRequestPriority('low', 'Low'),
          DesktopRequestPriority('normal', 'Normal'),
          DesktopRequestPriority('high', 'High'),
          DesktopRequestPriority('urgent', 'Urgent'),
        ],
        quickReasons: const ['Running low', 'Out of stock'],
        photos: const [],
        productName: widget.product,
        onHand: widget.product == null ? null : 'You have 6 pieces now',
        summary: widget.product == null ? null : 'Requesting 24 pieces of Milk',
        sentMessage: widget.sent,
        onPickProduct: () => widget.log?.add('pick'),
        onPriority: (v) => setState(() => priority = v),
        onReason: (r) => setState(() => reason.text = r),
        onChanged: () => setState(() {}),
        onAddPhoto: () {},
        onRemovePhoto: (_) {},
        onSubmit: () {
          widget.log
              ?.add(formKey.currentState!.validate() ? 'submit' : 'invalid');
        },
        onCancel: () => widget.log?.add('cancel'),
      );
}

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('stock-request-form', () => const _Host());
  shotMatrix(
    'stock-request-sent',
    () => const _Host(sent: 'Your request is sent.'),
  );

  testWidgets('Ctrl+Enter sends, empty quantity is refused, Esc leaves',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(desktopApp(_Host(log: log)));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(log, ['submit']);

    await tester.enterText(find.byKey(const ValueKey('request-quantity')), '');
    await tester.tap(find.byKey(const ValueKey('send-request')));
    await tester.pump();
    expect(log.last, 'invalid');
    expect(find.text('Enter how many you need'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(log.last, 'cancel');
  });

  testWidgets('quick-add chips update the quantity', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(const _Host()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('priority-urgent')));
    await tester.tap(find.text('+10'));
    await tester.pump();
    expect(find.widgetWithText(TextFormField, '34'), findsOneWidget);
  });
}
