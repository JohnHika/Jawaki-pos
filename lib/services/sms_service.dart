import 'dart:async';

class SmsService {
  // Simulates reading auto-verification SMS from M-Pesa
  final bool _useMock;

  SmsService({bool useMock = true}) : _useMock = useMock;

  /// Verify an M-Pesa payment by code
  /// In production, reads SMS from M-Pesa to auto-verify
  Future<bool> verifyMpesaCode(String code) async {
    if (_useMock) {
      // Mock: wait 3 seconds, then simulate verification
      await Future.delayed(const Duration(seconds: 3));
      return code.length >= 6;
    }
    // Real implementation would:
    // 1. Use sms_autofill to listen for SMS
    // 2. Extract confirmation from M-Pesa message
    // 3. Call API to verify
    return false;
  }

  /// Listen for incoming SMS
  /// Returns the first matching M-Pesa confirmation SMS content
  Stream<String> listenForSms() {
    if (_useMock) {
      return _mockSmsStream();
    }
    // Real implementation would use sms_autofill or telephony package
    return _mockSmsStream();
  }

  Stream<String> _mockSmsStream() {
    return Stream.periodic(
      const Duration(seconds: 3),
      (count) {
        if (count == 0) {
          return 'M-PESA confirmed. KES 600 sent to Jawaki AI. New M-PESA transaction ID: ABC123';
        }
        return '';
      },
    ).take(1).where((msg) => msg.isNotEmpty);
  }

  /// Extract confirmation code from M-Pesa SMS
  String? extractCodeFromSms(String smsBody) {
    // Try to find transaction ID in SMS
    final idMatch = RegExp(r'[A-Z0-9]{6,12}').firstMatch(smsBody);
    return idMatch?.group(0);
  }
}
