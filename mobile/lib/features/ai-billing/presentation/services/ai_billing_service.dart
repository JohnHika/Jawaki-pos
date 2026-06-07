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

  Future<Map<String, dynamic>> startTrial(String branchId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ai-billing/trial'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'branchId': branchId}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _subscriptions.add(data);
        return data;
      } else {
        throw Exception('Failed to start trial: ${response.statusCode}');
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiBilling] Error: $e');
      rethrow;
    }
  }

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

  Future<bool> launchMpesa() async {
    final Uri uri = Uri(
      scheme: 'mpesa',
      path: 'payment',
      query: 'phone=0742126582&amount=600&reference=Axon%20AI',
    );

    // Try the M-Pesa app
    final String? mpesaApp = await _tryLaunch('mpesa://');
    if (mpesaApp != null) return true;

    // Try the M-Pesa Express app
    final String? mpesaExpress = await _tryLaunch('mpesaexpress://');
    if (mpesaExpress != null) return true;

    // Fallback to web
    final Uri webUri = Uri.parse('https://mobile.mpesa.co.ke');
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri);
      return true;
    }

    throw Exception('M-Pesa app not found. Please install M-Pesa.');
  }

  Future<String?> _tryLaunch(String scheme) async {
    final Uri uri = Uri(scheme: scheme);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return 'launched';
    }
    return null;
  }

  String formatCurrency(double amount) {
    final formatter = NumberFormat('#,##0.00', 'en_KE');
    return formatter.format(amount);
  }
}
