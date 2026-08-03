import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:axon_pos/features/auth/presentation/screens/company_setup_screen.dart';

void main() {
  testWidgets('registration is a guided four-step flow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CompanySetupScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    expect(find.text('Build your workspace'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Admin Account'), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'Acme Retail');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of 4'), findsOneWidget);
    expect(find.text('Meet the owner'), findsOneWidget);
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('company name rejects server-invalid characters on step one',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CompanySetupScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

    await tester.enterText(find.byType(TextFormField), 'Acme%20Retail');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Only letters, numbers, spaces, &, ' and - are allowed",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Step 1 of 4'), findsOneWidget);
  });

  test('maps duplicate workspace responses to concise user-facing copy', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/auth/register-company'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/auth/register-company'),
        statusCode: 400,
        data: {
          'message': 'Company with this slug already exists',
          'error': 'Bad Request',
          'statusCode': 400,
        },
      ),
      type: DioExceptionType.badResponse,
    );

    expect(
      companySetupErrorMessage(error),
      'A workspace with this name already exists. Choose a different name.',
    );
  });
}
