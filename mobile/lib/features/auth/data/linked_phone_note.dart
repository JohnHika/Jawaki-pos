import 'package:shared_preferences/shared_preferences.dart';

/// Which phone signed this computer in, kept on the computer so Settings can
/// say "John's phone" without asking the online service each time.
class LinkedPhoneNote {
  const LinkedPhoneNote({required this.device, this.person});

  static const _deviceKey = 'linked_phone_device';
  static const _personKey = 'linked_phone_person';

  final String device;
  final String? person;

  /// "John's phone" or, when only the person is known, "Approved by John".
  String get label => device;

  static Future<void> save({String? device, String? person}) async {
    final name = device?.trim() ?? '';
    final who = person?.trim() ?? '';
    if (name.isEmpty && who.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceKey, name.isNotEmpty ? name : "$who's phone");
      if (who.isNotEmpty) await prefs.setString(_personKey, who);
    } catch (_) {
      // Remembering the phone is a nicety; signing in must not depend on it.
    }
  }

  static Future<LinkedPhoneNote?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final device = prefs.getString(_deviceKey);
      if (device == null || device.isEmpty) return null;
      return LinkedPhoneNote(
        device: device,
        person: prefs.getString(_personKey),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deviceKey);
      await prefs.remove(_personKey);
    } catch (_) {}
  }
}
