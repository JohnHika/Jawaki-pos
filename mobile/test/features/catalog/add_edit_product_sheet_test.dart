import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';
import 'package:axon_pos/features/catalog/presentation/providers/catalog_categories_provider.dart';
import 'package:axon_pos/features/catalog/presentation/widgets/add_edit_product_sheet.dart';

void main() {
  testWidgets('uses readable dark-theme colors in the Add Product form',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: SizedBox(height: 700, child: AddEditProductSheet()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(find.byType(TextField).first);

    expect(nameField.style?.color, DesignColors.darkTextPrimary);
    expect(
      nameField.decoration?.labelStyle?.color,
      DesignColors.darkTextSecondary,
    );
    expect(
      nameField.decoration?.hintStyle?.color,
      DesignColors.darkTextTertiary,
    );
  });

  testWidgets('the save button stays on screen on a short phone', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100); // 800 x 550 dp: short, not narrow
    tester.view.devicePixelRatio = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AddEditProductSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(SignInButton, 'Save product');
    expect(button, findsOneWidget);
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(550));
  });

  testWidgets('asks for name, price and unit first, and keeps the rest under More details',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(height: 800, child: AddEditProductSheet())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product name'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Sold per'), findsOneWidget);
    expect(find.text('More details'), findsOneWidget);
    expect(find.text('Save and add another'), findsOneWidget);
    // Not on the first screen any more.
    expect(find.text('Warn me when fewer than'), findsNothing);
    expect(find.text('Barcode or code'), findsNothing);
  });

  testWidgets('a name tapped from the starter list starts the form', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 800, child: AddEditProductSheet(initialName: 'Sugar')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Sugar');
  });
}
