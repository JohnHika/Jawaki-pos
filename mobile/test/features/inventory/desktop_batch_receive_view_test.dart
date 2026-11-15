import 'package:axon_pos/features/inventory/presentation/desktop/desktop_batch_receive_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

class _B {
  _B(String q, this.unit) : qty = TextEditingController(text: q);
  final TextEditingController qty;
  final cost = TextEditingController();
  final ref = TextEditingController();
  final notes = TextEditingController();
  String unit;

  void dispose() {
    qty.dispose();
    cost.dispose();
    ref.dispose();
    notes.dispose();
  }
}

class _Host extends StatefulWidget {
  const _Host({this.log, this.filled = true});
  final List<String>? log;
  final bool filled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final formKey = GlobalKey<FormState>();
  final batches = <_B>[];

  @override
  void initState() {
    super.initState();
    batches.add(_B(widget.filled ? '5' : '', 'carton'));
    if (widget.filled) batches.add(_B('12', 'piece'));
  }

  @override
  void dispose() {
    for (final b in batches) {
      b.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopBatchReceiveView(
        formKey: formKey,
        productName: 'Brookside Milk 500ml',
        baseUnit: 'piece',
        units: const ['piece', 'carton'],
        onHandLabel: 'On hand now: 6 pieces',
        packSizes: const ['1 carton = 24 piece'],
        totalLabel: widget.filled ? 'Adding 132 pieces' : null,
        afterLabel: widget.filled ? '138 on hand after' : null,
        rows: [
          for (final b in batches)
            DesktopBatchRow(
              quantity: b.qty,
              cost: b.cost,
              supplierRef: b.ref,
              notes: b.notes,
              unit: b.unit,
              expiry: b.unit == 'carton' ? DateTime(2027, 2, 14) : null,
              conversion: b.unit == 'carton' ? '= 120 piece' : null,
            ),
        ],
        onAdd: () {
          widget.log?.add('add');
          setState(() => batches.add(_B('', 'piece')));
        },
        onRemove: (i) => setState(() => batches.removeAt(i).dispose()),
        onUnit: (i, u) => setState(() => batches[i].unit = u),
        onPickDate: (i, {required expiry}) =>
            widget.log?.add('date $i $expiry'),
        onChanged: () => setState(() {}),
        onSave: () => widget.log
            ?.add(formKey.currentState!.validate() ? 'save' : 'invalid'),
        onCancel: () => widget.log?.add('cancel'),
      );
}

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('batch-receive', () => const _Host());

  testWidgets('empty quantity blocks saving, Ctrl+Enter saves a valid one',
      (tester) async {
    useWindow(tester, desktopSizes['1093']!);
    final log = <String>[];
    await tester.pumpWidget(desktopApp(_Host(log: log, filled: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('receive-batches')));
    await tester.pump();
    expect(log, ['invalid']);
    expect(find.text('Enter how many'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('batch-qty-0')), '10');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(log.last, 'save');
  });

  testWidgets('Add batch appends a row and focuses its quantity',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(desktopApp(_Host(log: log)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('batch-row-2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('add-batch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('batch-row-2')), findsOneWidget);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('batch-qty-2')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue);
    expect(log, ['add']);
  });

  testWidgets('the side panel follows the selected batch', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(const _Host()));
    await tester.pumpAndSettle();
    expect(find.text('Batch 1 details'), findsOneWidget);
    expect(find.text('= 120 piece'), findsOneWidget);
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.text('Batch 2 details'), findsOneWidget);
    expect(find.text('= 120 piece'), findsNothing);
  });
}
