// Local visual preview of the merchant payout screen. It never contacts an API.
// Run only as a debug entrypoint; the regular app uses lib/main.dart.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'core/di/injection.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/payments/presentation/screens/merchant_payout_setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final dio = Dio(BaseOptions(baseUrl: 'https://preview.invalid'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    if (request.method == 'GET' && request.path.endsWith('/merchant-payments/account')) {
      return handler.resolve(Response(
        requestOptions: request,
        data: {'status': 'NOT_CONFIGURED', 'provider': 'PAYSTACK', 'currency': 'KES'},
      ));
    }
    if (request.method == 'GET' && request.path.endsWith('/merchant-payments/banks')) {
      return handler.resolve(Response(
        requestOptions: request,
        data: const <Map<String, dynamic>>[],
      ));
    }
    return handler.reject(DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 403,
        data: {'message': 'Preview only. No account details were sent or saved.'},
      ),
      type: DioExceptionType.badResponse,
    ));
  }));
  getIt.registerSingleton<ApiClient>(ApiClient(dio));
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Counterbase Preview',
    theme: AppTheme.lightTheme,
    home: Column(children: [
      Container(
        width: double.infinity,
        color: const Color(0xFFFFEDD5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const SafeArea(
          bottom: false,
          child: Text('PREVIEW ONLY · No bank details or payments are sent',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ),
      const Expanded(child: MerchantPayoutSetupScreen()),
    ]),
  ));
}
