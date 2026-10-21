import 'package:aca/core/theme.dart';
import 'package:aca/data/models.dart';
import 'package:aca/features/security/security_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AuditEntry entry({
  String id = 'e',
  String action = 'AUTH_LOGIN_SUCCESS',
  String category = 'AUTH',
  String severity = 'INFO',
  String? summary,
  String? actorEmail,
  String? actorRole,
  String? createdAt,
  Map<String, dynamic>? metadata,
}) =>
    AuditEntry.fromJson({
      'id': id,
      'action': action,
      'category': category,
      'severity': severity,
      'summary': summary,
      'actorEmail': actorEmail,
      'actorRole': actorRole,
      'createdAt': createdAt,
      'metadata': metadata,
    });

void main() {
  group('prettifyAction', () {
    test('drops the platform prefix and the redundant category word', () {
      expect(prettifyAction('PLATFORM_ADMIN_TENANT_EXTENDED'), 'Company extended');
      expect(prettifyAction('PLATFORM_ADMIN_INVOICE_MARKED_PAID'), 'Invoice marked paid');
      expect(prettifyAction('TEAM_STAFF_CREATED'), 'Staff created');
      expect(prettifyAction('SECURITY_ACCOUNT_UNLOCKED'), 'Account unlocked');
      expect(prettifyAction('BILLING_CREDIT_ISSUED'), 'Credit issued');
      expect(prettifyAction('AUTH_PASSWORD_CHANGED'), 'Password changed');
    });

    test('keeps the subject for company and licence events', () {
      expect(prettifyAction('TENANT_NOTE_ADDED'), 'Company note added');
      expect(prettifyAction('LICENSE_UPDATED'), 'Licence updated');
    });

    test('uses plain words for sign-in vocabulary', () {
      expect(prettifyAction('AUTH_LOGIN_SUCCESS'), 'Sign-in success');
      expect(prettifyAction('AUTH_LOGOUT'), 'Sign-out');
      expect(prettifyAction('AUTH_2FA_ENABLED'), 'Two-step enabled');
    });

    test('has hand-written wording for the awkward ones', () {
      expect(prettifyAction('AUTH_LOGIN_BLOCKED_LOCKED'), 'Sign-in blocked (account locked)');
      expect(prettifyAction('AUTH_2FA_FAILED'), 'Two-step code rejected');
    });

    test('handles odd input without throwing', () {
      expect(prettifyAction(null), 'Unknown action');
      expect(prettifyAction('  '), 'Unknown action');
      expect(prettifyAction('LOGIN'), 'Sign-in');
      expect(prettifyAction('some_new_action'), 'Some new action');
      expect(prettifyAction('__X__'), 'X');
    });
  });

  group('entry text', () {
    test('title prefers the summary and falls back to the action', () {
      expect(entryTitle(entry(summary: 'qa-owner@aca.test signed in')), 'qa-owner@aca.test signed in');
      expect(entryTitle(entry(summary: '   ', action: 'TEAM_STAFF_DISABLED', category: 'TEAM')), 'Staff disabled');
      expect(entryTitle(entry(summary: null, action: 'TEAM_STAFF_DISABLED')), 'Staff disabled');
    });

    test('actor line shows email and role, or says nobody was signed in', () {
      expect(actorLine(entry(actorEmail: 'a@x.com', actorRole: 'SECURITY')), 'a@x.com · Security');
      expect(actorLine(entry(actorEmail: 'a@x.com')), 'a@x.com');
      expect(actorLine(entry()), 'No staff account');
    });

    test('user agents are collapsed and trimmed', () {
      expect(trimUserAgent(null), isNull);
      expect(trimUserAgent('   '), isNull);
      expect(trimUserAgent('curl/8.18.0'), 'curl/8.18.0');
      expect(trimUserAgent('A   B\n C'), 'A B C');
      final long = 'x' * 200;
      final t = trimUserAgent(long, max: 50)!;
      expect(t.length, 50);
      expect(t.endsWith('…'), isTrue);
    });
  });

  group('severity and coverage', () {
    test('severity maps to a tone and a pill only for warnings and critical', () {
      expect(severityTone('CRITICAL'), Tone.danger);
      expect(severityTone('WARN'), Tone.warning);
      expect(severityTone('INFO'), Tone.neutral);
      expect(showSeverityPill('INFO'), isFalse);
      expect(showSeverityPill('WARN'), isTrue);
      expect(showSeverityPill('CRITICAL'), isTrue);
      expect(severityLabel('WARN'), 'Warning');
      expect(severityLabel('CRITICAL'), 'Critical');
    });

    test('two-factor coverage tone', () {
      expect(coverageTone(100), Tone.success);
      expect(coverageTone(99), Tone.warning);
      expect(coverageTone(17), Tone.warning);
      expect(coverageTone(0), Tone.danger);
    });
  });

  group('categories', () {
    test('every filter category has a label and a distinct icon', () {
      final icons = <IconData>{};
      for (final (value, label) in auditCategoryFilters.where((f) => f.$1 != null)) {
        expect(categoryLabel(value!), label);
        icons.add(categoryIcon(value));
      }
      expect(icons.length, 6);
      expect(categoryLabel('SOMETHING_NEW'), 'Something new');
      expect(categoryIcon('SOMETHING_NEW'), Icons.history_rounded);
    });

    test('filters offer the contract values', () {
      expect(auditCategoryFilters.map((f) => f.$1), [null, 'AUTH', 'TEAM', 'TENANT', 'BILLING', 'LICENSE', 'SECURITY']);
      expect(auditSeverityFilters.map((f) => f.$1), [null, 'WARN', 'CRITICAL']);
    });
  });

  group('unlockLabel', () {
    final now = DateTime(2026, 10, 21, 12);

    test('future lock expiry reads "unlocks in ..."', () {
      expect(unlockLabel(now.add(const Duration(minutes: 12)), now: now), 'unlocks in 12 min');
      expect(unlockLabel(now.add(const Duration(hours: 2)), now: now), 'unlocks in 2 h');
    });

    test('past or unknown expiry', () {
      expect(unlockLabel(now.subtract(const Duration(minutes: 1)), now: now), 'unlock due');
      expect(unlockLabel(now, now: now), 'unlock due');
      expect(unlockLabel(null, now: now), 'locked');
    });
  });

  group('day grouping', () {
    final now = DateTime(2026, 10, 21, 15, 30);

    test('dayLabel: Today, Yesterday, then the date', () {
      expect(dayLabel(DateTime(2026, 10, 21, 0, 5), now: now), 'Today');
      expect(dayLabel(DateTime(2026, 10, 20, 23, 59), now: now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 10, 19), now: now), '19 Oct 2026');
      expect(dayLabel(null), 'Unknown date');
    });

    test('rows get one header per day and keep entry order', () {
      final entries = [
        entry(id: 'a', createdAt: DateTime(2026, 10, 21, 14).toIso8601String()),
        entry(id: 'b', createdAt: DateTime(2026, 10, 21, 9).toIso8601String()),
        entry(id: 'c', createdAt: DateTime(2026, 10, 20, 22).toIso8601String()),
        entry(id: 'd', createdAt: DateTime(2026, 10, 18, 8).toIso8601String()),
      ];
      final rows = buildAuditRows(entries, now: now);
      expect(rows.map((r) => r.isHeader ? 'H:${r.header}' : r.entry!.id).toList(), [
        'H:Today',
        'a',
        'b',
        'H:Yesterday',
        'c',
        'H:18 Oct 2026',
        'd',
      ]);
    });

    test('undated entries go last under "Unknown date"', () {
      final rows = buildAuditRows([
        entry(id: 'x'),
        entry(id: 'a', createdAt: DateTime(2026, 10, 21, 14).toIso8601String()),
      ], now: now);
      expect(rows.map((r) => r.isHeader ? 'H:${r.header}' : r.entry!.id).toList(), [
        'H:Today',
        'a',
        'H:Unknown date',
        'x',
      ]);
    });

    test('an empty list produces no rows', () {
      expect(buildAuditRows(const []), isEmpty);
    });

    test('appending a later page into the same day does not repeat the header', () {
      final page1 = [entry(id: 'a', createdAt: DateTime(2026, 10, 20, 23).toIso8601String())];
      final page2 = [entry(id: 'b', createdAt: DateTime(2026, 10, 20, 7).toIso8601String())];
      final rows = buildAuditRows([...page1, ...page2], now: now);
      expect(rows.where((r) => r.isHeader).length, 1);
    });
  });

  group('metadata', () {
    test('humanizeKey', () {
      expect(humanizeKey('twoFactor'), 'Two factor');
      expect(humanizeKey('two_factor'), 'Two factor');
      expect(humanizeKey('amountKes'), 'Amount KES');
      expect(humanizeKey('ipAddress'), 'IP address');
      expect(humanizeKey('mpesaCode'), 'M-Pesa code');
      expect(humanizeKey('id'), 'ID');
      expect(humanizeKey('PlatformAdmin'), 'Platform admin');
    });

    test('values are shown as people read them', () {
      expect(formatMetadataValue(true), 'Yes');
      expect(formatMetadataValue(false), 'No');
      expect(formatMetadataValue(30), '30');
      expect(formatMetadataValue(3200, key: 'amountKes'), 'KES 3,200');
      expect(formatMetadataValue('DISABLED'), 'DISABLED');
      expect(formatMetadataValue('2026-10-21T09:05:00'), '21 Oct 2026, 09:05');
      expect(formatMetadataValue('not-a-date-2026'), 'not-a-date-2026');
    });

    test('flattenMetadata nests, skips empties and never dumps raw JSON for plain data', () {
      final rows = flattenMetadata({
        'device': null,
        'twoFactor': false,
        'note': '   ',
        'tags': ['a', 'b'],
        'emptyList': <String>[],
        'before': {'name': 'QA Viewer', 'status': 'ACTIVE'},
        'after': {'status': 'DISABLED'},
        'days': 30,
      });
      expect(rows, const [
        MetaPair('Two factor', 'No'),
        MetaPair('Tags', 'a, b'),
        MetaPair('Before › Name', 'QA Viewer'),
        MetaPair('Before › Status', 'ACTIVE'),
        MetaPair('After › Status', 'DISABLED'),
        MetaPair('Days', '30'),
      ]);
    });

    test('lists of objects and very deep maps fall back to compact JSON', () {
      final rows = flattenMetadata({
        'items': [
          {'a': 1}
        ],
        'a': {
          'b': {
            'c': {'d': 1}
          }
        },
      });
      expect(rows[0], const MetaPair('Items', '[{"a":1}]'));
      expect(rows[1], const MetaPair('A › B › C', '{"d":1}'));
    });

    test('null or empty metadata gives no rows', () {
      expect(flattenMetadata(null), isEmpty);
      expect(flattenMetadata(const {}), isEmpty);
    });

    test('target types are prettified', () {
      expect(prettifyTargetType('PlatformAdmin'), 'Platform admin');
      expect(prettifyTargetType('SubscriptionInvoice'), 'Subscription invoice');
      expect(prettifyTargetType(null), '—');
    });
  });
}
