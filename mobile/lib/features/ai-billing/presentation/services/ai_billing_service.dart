import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/storage_service.dart';

class AiBillingService {
  AiBillingService._internal();
  static final AiBillingService _instance = AiBillingService._internal();
  factory AiBillingService() => _instance;

  final List<Map<String, dynamic>> _subscriptions = [];

  String get _baseUrl {
    final storage = getIt<StorageService>();
    final savedUrl = storage.getServerBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      return savedUrl;
    }
    final ip = storage.getBackendServerIp();
    final port = storage.getBackendServerPort();
    if (ip != null && ip.isNotEmpty) {
      return 'http://$ip:$port/api/v1';
    }
    return 'https://arche-axon-pos-api.onrender.com/api/v1';
  }

  List<Map<String, dynamic>> get subscriptions => List.unmodifiable(_subscriptions);

  /// Monthly price for the AI assistant subscription. Kept in sync with
  /// AiBillingService.SUBSCRIPTION_PRICE on the backend.
  static const double subscriptionPrice = 1500.0;

  Future<Map<String, dynamic>> getStatus(String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ai-billing/status/$branchId'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        throw Exception('Failed to get status: ${response.statusCode}');
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiBilling] Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submitPayment(
    String branchId,
    String mpesaCode, {
    String? senderPhone,
    String? smsRaw,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ai-billing/submit-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branchId': branchId,
          'mpesaCode': mpesaCode,
          'senderPhone': senderPhone,
          'smsRaw': smsRaw,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Payment failed');
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiBilling] Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> verifySms(
    String branchId,
    String mpesaCode,
    String amount,
    String recipient,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ai-billing/verify-sms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branchId': branchId,
          'mpesaCode': mpesaCode,
          'amount': amount,
          'recipient': recipient,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        throw Exception('SMS verification failed: ${response.statusCode}');
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiBilling] Error: $e');
      rethrow;
    }
  }

  /// Starts a Paystack card checkout for this branch's subscription.
  /// Returns the URL to open in a webview/browser; once the customer pays,
  /// Paystack's webhook activates the subscription and saves the card for
  /// automatic monthly renewal — no further action needed from them.
  Future<String> initializePaystackPayment(
    String branchId,
    String email,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ai-billing/paystack/initialize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'branchId': branchId, 'email': email}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final payload = data['data'] ?? data;
        return payload['authorizationUrl'] as String;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Could not start payment');
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiBilling] Error: $e');
      rethrow;
    }
  }

  Future<bool> launchMpesa() async {
    final amount = subscriptionPrice.toStringAsFixed(0);
    const phone = '0742126582';

    // Try the M-Pesa app with the payment prefilled
    final mpesaUri = Uri(
      scheme: 'mpesa',
      path: 'payment',
      query: 'phone=$phone&amount=$amount&reference=Axon%20AI',
    );
    if (await canLaunchUrl(mpesaUri)) {
      await launchUrl(mpesaUri);
      return true;
    }

    // Try the M-Pesa Express app
    final mpesaExpressUri = Uri(scheme: 'mpesaexpress', path: 'payment');
    if (await canLaunchUrl(mpesaExpressUri)) {
      await launchUrl(mpesaExpressUri);
      return true;
    }

    // Fallback to web
    final Uri webUri = Uri.parse('https://mobile.mpesa.co.ke');
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri);
      return true;
    }

    throw Exception('M-Pesa app not found. Please install M-Pesa.');
  }

  String formatCurrency(double amount) {
    final formatter = NumberFormat('#,##0.00', 'en_KE');
    return formatter.format(amount);
  }
}
