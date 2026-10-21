import 'package:flutter/foundation.dart' show immutable;

import '../../core/format.dart';
import '../../data/models.dart';

/// Pure helpers for the Account & security screen (and the small text helpers
/// the Team screens share). Nothing in here touches the network or a widget, so
/// every rule is unit-tested in `test/account_logic_test.dart`.

/// "1 device" / "3 devices". [many] defaults to `${one}s`.
String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

// ------------------------------------------------------------ password policy

@immutable
class PasswordRule {
  const PasswordRule(this.label, this.met);
  final String label;
  final bool met;
}

/// Mirrors `passwordMeetsPolicy` in the backend (`security/totp.util.ts`):
/// 12-128 characters with a lower-case letter, an upper-case letter, a digit
/// and a symbol (anything that is not A-Z, a-z, 0-9). The server is the authority;
/// this only gives live feedback while the person types.
class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 12;
  static const int maxLength = 128;

  static final RegExp _lower = RegExp(r'[a-z]');
  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _symbol = RegExp(r'[^A-Za-z0-9]');

  /// One entry per rule, in the order they are shown.
  static List<PasswordRule> evaluate(String password) => [
        PasswordRule('At least $minLength characters', password.length >= minLength),
        PasswordRule('An upper-case letter (A-Z)', _upper.hasMatch(password)),
        PasswordRule('A lower-case letter (a-z)', _lower.hasMatch(password)),
        PasswordRule('A number (0-9)', _digit.hasMatch(password)),
        PasswordRule('A symbol (for example ! @ # %)', _symbol.hasMatch(password)),
      ];

  static bool isValid(String password) =>
      password.length <= maxLength && evaluate(password).every((r) => r.met);

  /// How many of the rules are met (0-5), for a strength meter.
  static int score(String password) => evaluate(password).where((r) => r.met).length;
}

/// Why the "Change password" form cannot be submitted yet; null when it can.
String? changePasswordProblem({required String current, required String next, required String confirm}) {
  if (current.isEmpty) return 'Enter your current password';
  if (!PasswordPolicy.isValid(next)) return 'Your new password does not meet every rule yet';
  if (next == current) return 'Choose a password different from the current one';
  if (confirm != next) return 'The two new passwords do not match';
  return null;
}

// ------------------------------------------------------------------- 2FA codes

/// Authenticator secret for display: "JBSWY3DPEHPK3PXP" -> "JBSW Y3DP EHPK 3PXP".
String groupSecret(String secret, {int groupSize = 4}) {
  final clean = secret.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (clean.isEmpty || groupSize < 1) return clean;
  final parts = <String>[];
  for (var i = 0; i < clean.length; i += groupSize) {
    parts.add(clean.substring(i, i + groupSize > clean.length ? clean.length : i + groupSize));
  }
  return parts.join(' ');
}

/// What the authenticator app needs when typing the key by hand (no spaces).
String rawSecret(String secret) => secret.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// A 6-digit authenticator code, tolerating the space most apps display ("123 456").
String cleanOtp(String input) => input.replaceAll(RegExp(r'\s+'), '');

bool isSixDigitCode(String input) => RegExp(r'^\d{6}$').hasMatch(cleanOtp(input));

/// Authenticator code OR a backup code such as "K7QD-9MXA" (the server accepts both, max 20 chars).
bool looksLikeSecondFactor(String input) {
  final c = input.trim();
  return c.isNotEmpty && c.length <= 20;
}

/// All backup codes, one per line, for the clipboard.
String backupCodesText(List<String> codes) => codes.join('\n');

// -------------------------------------------------------------------- sessions

String deviceTitle(SessionInfo s) {
  final label = s.deviceLabel?.trim();
  return (label == null || label.isEmpty) ? 'Unknown device' : label;
}

/// "41.80.1.2 · last used 5 min ago". Missing parts are left out.
String sessionSubtitle(SessionInfo s, {DateTime? now}) {
  final parts = <String>[
    if (s.ipAddress != null && s.ipAddress!.trim().isNotEmpty) s.ipAddress!.trim(),
    if (s.lastUsedAt != null) 'last used ${Fmt.ago(s.lastUsedAt, now: now)}',
  ];
  return parts.isEmpty ? 'No activity recorded yet' : parts.join(' · ');
}

/// Sessions other than the one this phone is using.
List<SessionInfo> otherSessions(List<SessionInfo> all) => all.where((s) => !s.current).toList();

/// Toast after "Sign out all other devices".
String signedOutOthersMessage(int count) =>
    count <= 0 ? 'No other devices were signed in' : 'Signed out ${plural(count, 'other device')}';

/// "12 Mar 2026" for the "Member since" line, or null when the server sent no date.
String? memberSince(DateTime? createdAt) => createdAt == null ? null : Fmt.date(createdAt);
