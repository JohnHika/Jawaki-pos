import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/partners/presentation/screens/partners_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineApi extends ApiClient {
  _OfflineApi() : super(Dio());
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> getTradePartners() async {
    calls++;
    throw DioException(
      requestOptions: RequestOptions(path: '/partners'),
      type: DioExceptionType.connectionError,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed load says so and offers Try again, not "no partners"',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    final api = _OfflineApi();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    if (getIt.isRegistered<StorageService>()) {
      getIt.unregister<StorageService>();
    }
    getIt.registerSingleton<ApiClient>(api);
    getIt.registerSingleton<StorageService>(storage);
    addTearDown(() {
      if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
      if (getIt.isRegistered<StorageService>()) {
        getIt.unregister<StorageService>();
      }
    });

    final router = GoRouter(
      routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const ProviderScope(child: PartnersScreen())),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text("Couldn't load your partners"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Connect with the businesses you trade with'),
        findsNothing);

    // A retry in flight must not flip the page back to the neutral message.
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text("Couldn't load your partners"), findsOneWidget);
    expect(api.calls, greaterThanOrEqualTo(2));
  });
}
