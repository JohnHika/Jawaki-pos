import 'package:flutter_test/flutter_test.dart';

import 'package:aca/data/models.dart';
import 'package:aca/features/account/account_logic.dart';

SessionInfo _session({
  String id = 's1',
  String? label,
  String? ip,
  DateTime? lastUsed,
  bool current = false,
}) =>
    SessionInfo(
      id: id,
      deviceLabel: label,
      userAgent: null,
      ipAddress: ip,
      createdAt: null,
      lastUsedAt: lastUsed,
      expiresAt: null,
      current: current,
    );

void main() {
  group('PasswordPolicy', () {
    test('lists the five rules in order', () {
      final rules = PasswordPolicy.evaluate('');
      expect(rules.length, 5);
      expect(rules.every((r) => !r.met), isTrue);
      expect(rules.first.label, contains('12'));
    });

    test('reports each rule independently', () {
      bool met(String pw, int i) => PasswordPolicy.evaluate(pw)[i].met;
      // 0 length, 1 upper, 2 lower, 3 digit, 4 symbol
      expect(met('abcdefghijkl', 0), isTrue);
      expect(met('abcdefghijk', 0), isFalse);
      expect(met('abcA', 1), isTrue);
      expect(met('abc', 1), isFalse);
      expect(met('ABCa', 2), isTrue);
      expect(met('ABC', 2), isFalse);
      expect(met('a1', 3), isTrue);
      expect(met('abc', 3), isFalse);
      expect(met('a!', 4), isTrue);
      expect(met('a b', 4), isTrue, reason: 'anything that is not a letter or digit counts as a symbol');
      expect(met('abc123', 4), isFalse);
    });

    test('isValid mirrors the server policy', () {
      expect(PasswordPolicy.isValid('Correct-Horse9'), isTrue);
      expect(PasswordPolicy.isValid('Short-1a'), isFalse, reason: 'under 12 characters');
      expect(PasswordPolicy.isValid('alllowercase123!'), isFalse, reason: 'no upper-case');
      expect(PasswordPolicy.isValid('ALLUPPERCASE123!'), isFalse, reason: 'no lower-case');
      expect(PasswordPolicy.isValid('NoDigitsHere!!!'), isFalse);
      expect(PasswordPolicy.isValid('NoSymbols12345A'), isFalse);
      expect(PasswordPolicy.isValid('Aa1!${'x' * 125}'), isFalse, reason: '129 characters is over the limit');
      expect(PasswordPolicy.isValid('Aa1!${'x' * 124}'), isTrue, reason: 'exactly 128 is allowed');
    });

    test('score counts met rules', () {
      expect(PasswordPolicy.score(''), 0);
      expect(PasswordPolicy.score('abc'), 1);
      expect(PasswordPolicy.score('Correct-Horse9'), 5);
    });
  });

  group('changePasswordProblem', () {
    const good = 'Correct-Horse9';

    test('needs the current password first', () {
      expect(changePasswordProblem(current: '', next: good, confirm: good), isNotNull);
    });

    test('needs a policy-compliant new password', () {
      expect(changePasswordProblem(current: 'old', next: 'weak', confirm: 'weak'), isNotNull);
    });

    test('rejects reusing the current password', () {
      expect(changePasswordProblem(current: good, next: good, confirm: good), contains('different'));
    });

    test('rejects a mismatched confirmation', () {
      expect(changePasswordProblem(current: 'old', next: good, confirm: '${good}x'), contains('match'));
    });

    test('accepts a valid change', () {
      expect(changePasswordProblem(current: 'old', next: good, confirm: good), isNull);
    });
  });

  group('two-step verification codes', () {
    test('groupSecret splits into blocks of four', () {
      expect(groupSecret('JBSWY3DPEHPK3PXP'), 'JBSW Y3DP EHPK 3PXP');
      expect(groupSecret('abcdefghij'), 'ABCD EFGH IJ');
      expect(groupSecret(' jbsw y3dp '), 'JBSW Y3DP', reason: 'whitespace is ignored, case normalised');
      expect(groupSecret(''), '');
    });

    test('groupSecret handles a 32-character secret', () {
      final secret = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
      final grouped = groupSecret(secret);
      expect(grouped.split(' ').length, 8);
      expect(grouped.replaceAll(' ', ''), secret);
    });

    test('rawSecret strips spacing for copying', () {
      expect(rawSecret('JBSW Y3DP EHPK 3PXP'), 'JBSWY3DPEHPK3PXP');
    });

    test('cleanOtp and isSixDigitCode accept the spaced form authenticator apps show', () {
      expect(cleanOtp('123 456'), '123456');
      expect(isSixDigitCode('123456'), isTrue);
      expect(isSixDigitCode('123 456'), isTrue);
      expect(isSixDigitCode('12345'), isFalse);
      expect(isSixDigitCode('1234567'), isFalse);
      expect(isSixDigitCode('12a456'), isFalse);
    });

    test('looksLikeSecondFactor accepts authenticator and backup codes, bounded like the server', () {
      expect(looksLikeSecondFactor('123456'), isTrue);
      expect(looksLikeSecondFactor('K7QD-9MXA'), isTrue);
      expect(looksLikeSecondFactor(''), isFalse);
      expect(looksLikeSecondFactor('   '), isFalse);
      expect(looksLikeSecondFactor('x' * 21), isFalse);
    });

    test('backupCodesText is one code per line', () {
      expect(backupCodesText(['AAAA-1111', 'BBBB-2222']), 'AAAA-1111\nBBBB-2222');
      expect(backupCodesText([]), '');
    });
  });

  group('device sessions', () {
    final now = DateTime(2026, 10, 21, 12, 0);

    test('deviceTitle falls back for blank labels', () {
      expect(deviceTitle(_session(label: 'Pixel 7 · ACA 1.0')), 'Pixel 7 · ACA 1.0');
      expect(deviceTitle(_session(label: null)), 'Unknown device');
      expect(deviceTitle(_session(label: '   ')), 'Unknown device');
    });

    test('sessionSubtitle joins IP and last use, leaving out what is missing', () {
      final recent = now.subtract(const Duration(minutes: 5));
      expect(sessionSubtitle(_session(ip: '41.80.1.2', lastUsed: recent), now: now), '41.80.1.2 · last used 5 min ago');
      expect(sessionSubtitle(_session(ip: '41.80.1.2'), now: now), '41.80.1.2');
      expect(sessionSubtitle(_session(lastUsed: recent), now: now), 'last used 5 min ago');
      expect(sessionSubtitle(_session(), now: now), 'No activity recorded yet');
    });

    test('otherSessions excludes the current device', () {
      final all = [_session(id: 'a', current: true), _session(id: 'b'), _session(id: 'c')];
      expect(otherSessions(all).map((s) => s.id), ['b', 'c']);
      expect(otherSessions([_session(current: true)]), isEmpty);
    });

    test('signedOutOthersMessage pluralises', () {
      expect(signedOutOthersMessage(0), 'No other devices were signed in');
      expect(signedOutOthersMessage(1), 'Signed out 1 other device');
      expect(signedOutOthersMessage(3), 'Signed out 3 other devices');
    });
  });

  test('plural', () {
    expect(plural(1, 'session'), '1 session');
    expect(plural(0, 'session'), '0 sessions');
    expect(plural(2, 'company', 'companies'), '2 companies');
    expect(plural(1, 'company', 'companies'), '1 company');
  });

  test('memberSince formats a date and tolerates null', () {
    expect(memberSince(null), isNull);
    expect(memberSince(DateTime(2026, 3, 12, 9)), '12 Mar 2026');
  });
}
