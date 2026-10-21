import 'package:aca/core/theme.dart';
import 'package:aca/data/models.dart';
import 'package:aca/features/billing/billing_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Invoice invoice({
  String status = 'PENDING',
  Object amount = '3200',
  String? provider,
  String? reference,
  String plan = 'CORE',
  String? paidAt,
  String? createdAt = '2026-10-09T10:00:00Z',
}) =>
    Invoice.fromJson({
      'id': 'inv-1',
      'tenantId': 't-1',
      'tenantName': 'Fixture Mart',
      'plan': plan,
      'amount': amount,
      'currency': 'KES',
      'status': status,
      'provider': provider,
      'reference': reference,
      'paidAt': paidAt,
      'createdAt': createdAt,
    });

Claim claim({String? invoiceStatus}) => Claim.fromJson({
      'id': 'c-${invoiceStatus ?? 'x'}',
      'tenantId': 't-1',
      'invoiceId': 'inv-1',
      'invoiceStatus': invoiceStatus,
      'mpesaCode': 'ABC12345XY',
      'amount': '3200',
    });

void main() {
  group('providerLabel', () {
    test('maps every provider the billing code writes', () {
      expect(providerLabel('PAYSTACK'), 'Paystack');
      expect(providerLabel('PAYSTACK_INITIALIZING'), 'Paystack (checkout started)');
      expect(providerLabel('PAYSTACK_FAILED'), 'Paystack (failed)');
      expect(providerLabel('JENGA_STK'), 'M-Pesa STK push');
      expect(providerLabel('MPESA_MANUAL'), 'M-Pesa (manual)');
      expect(providerLabel('PESAPAL_CARD'), 'Card (Pesapal)');
      expect(providerLabel('CREDIT'), 'Goodwill credit');
    });

    test('is case-insensitive and tolerant of blanks', () {
      expect(providerLabel('mpesa_manual'), 'M-Pesa (manual)');
      expect(providerLabel(null), 'Not paid yet');
      expect(providerLabel('  '), 'Not paid yet');
    });

    test('prettifies unknown providers instead of showing raw codes', () {
      expect(providerLabel('BANK_TRANSFER'), 'Bank transfer');
    });
  });

  group('creditReason', () {
    test('extracts the reason after the CREDIT: prefix', () {
      expect(creditReason('CREDIT:Outage on 3 Oct'), 'Outage on 3 Oct');
      expect(creditReason('  CREDIT:  spaced out  '), 'spaced out');
      expect(creditReason('credit:lower case prefix'), 'lower case prefix');
    });

    test('returns null when there is no credit reason', () {
      expect(creditReason(null), isNull);
      expect(creditReason(''), isNull);
      expect(creditReason('CREDIT:'), isNull);
      expect(creditReason('CREDIT:   '), isNull);
      expect(creditReason('QA-INV-1'), isNull);
    });
  });

  group('invoiceReferenceText', () {
    test('credits show their reason, never the CREDIT: marker', () {
      final i = invoice(status: 'PAID', amount: '-100', provider: 'CREDIT', reference: 'CREDIT:Goodwill');
      expect(i.isCredit, isTrue);
      expect(invoiceReferenceText(i), 'Goodwill');
    });

    test('normal invoices show the stored reference', () {
      expect(invoiceReferenceText(invoice(reference: 'QA-INV-4')), 'QA-INV-4');
      expect(invoiceReferenceText(invoice(reference: '  ')), isNull);
      expect(invoiceReferenceText(invoice()), isNull);
    });
  });

  group('invoice status', () {
    test('labels and tones', () {
      expect(invoiceStatusLabel('PAID'), 'Paid');
      expect(invoiceStatusLabel('PENDING'), 'Pending');
      expect(invoiceStatusLabel('PENDING_CONFIRMATION'), 'Awaiting confirmation');
      expect(invoiceStatusLabel('VOID'), 'Void');
      expect(invoiceStatusTone('PAID'), Tone.success);
      expect(invoiceStatusTone('PENDING'), Tone.warning);
      expect(invoiceStatusTone('PENDING_CONFIRMATION'), Tone.warning);
      expect(invoiceStatusTone('VOID'), Tone.neutral);
      expect(invoiceStatusTone(null), Tone.neutral);
    });

    test('anything unpaid can be reconciled, paid invoices cannot', () {
      expect(invoiceCanBeMarkedPaid(invoice(status: 'PENDING')), isTrue);
      expect(invoiceCanBeMarkedPaid(invoice(status: 'PENDING_CONFIRMATION')), isTrue);
      expect(invoiceCanBeMarkedPaid(invoice(status: 'PAID')), isFalse);
    });
  });

  group('invoiceCountLabel', () {
    test('pluralises and qualifies by filter', () {
      expect(invoiceCountLabel(42, null), '42 invoices');
      expect(invoiceCountLabel(1, null), '1 invoice');
      expect(invoiceCountLabel(0, 'PAID'), '0 paid invoices');
      expect(invoiceCountLabel(1, 'PENDING'), '1 pending invoice');
      expect(invoiceCountLabel(5, 'PENDING'), '5 pending invoices');
    });
  });

  group('periodLabel', () {
    test('formats a range, null when unknown', () {
      final a = DateTime(2026, 10, 1);
      final b = DateTime(2026, 10, 31);
      expect(periodLabel(a, b), '1 Oct – 31 Oct');
      expect(periodLabel(a, b, withYear: true), '1 Oct 2026 – 31 Oct 2026');
      expect(periodLabel(null, null), isNull);
      expect(periodLabel(a, null), '1 Oct – —');
    });
  });

  group('invoiceTimelineLabel', () {
    final now = DateTime.utc(2026, 10, 21, 12);

    test('paid invoices read "Paid ..."', () {
      final i = invoice(status: 'PAID', paidAt: '2026-10-21T09:00:00Z');
      expect(invoiceTimelineLabel(i, now: now), 'Paid 3 h ago');
    });

    test('unpaid invoices read "Created ..."', () {
      final i = invoice(createdAt: '2026-10-19T12:00:00Z');
      expect(invoiceTimelineLabel(i, now: now), 'Created 2 d ago');
    });

    test('paid without a paid date falls back to created', () {
      final i = invoice(status: 'PAID', createdAt: '2026-10-21T11:00:00Z');
      expect(invoiceTimelineLabel(i, now: now), 'Created 1 h ago');
    });
  });

  group('M-Pesa code', () {
    test('normalises case and whitespace', () {
      expect(normalizeMpesaCode(' sbx12 ab34cd '), 'SBX12AB34CD');
      expect(normalizeMpesaCode('   '), isNull);
      expect(normalizeMpesaCode(null), isNull);
    });

    test('validates the 8-15 alphanumeric shape the billing service accepts', () {
      expect(isValidMpesaCode('SBX12AB34CD'), isTrue);
      expect(isValidMpesaCode('ABCD1234'), isTrue);
      expect(isValidMpesaCode('ABC1234'), isFalse); // 7
      expect(isValidMpesaCode('ABCDEFGHIJ123456'), isFalse); // 16
      expect(isValidMpesaCode('ABC-12345'), isFalse);
    });

    test('the optional field only complains about non-blank, malformed input', () {
      expect(mpesaCodeError(''), isNull);
      expect(mpesaCodeError('   '), isNull);
      expect(mpesaCodeError('sbx12ab34cd'), isNull);
      expect(mpesaCodeError('abc'), isNotNull);
    });
  });

  group('claims', () {
    test('only claims with an unpaid invoice need action', () {
      expect(claimNeedsAction(claim(invoiceStatus: 'PENDING')), isTrue);
      expect(claimNeedsAction(claim(invoiceStatus: 'PENDING_CONFIRMATION')), isTrue);
      expect(claimNeedsAction(claim(invoiceStatus: null)), isTrue);
      expect(claimNeedsAction(claim(invoiceStatus: 'PAID')), isFalse);
    });

    test('actionable count ignores settled ones', () {
      final list = [claim(invoiceStatus: 'PAID'), claim(invoiceStatus: 'PENDING'), claim(invoiceStatus: 'PENDING')];
      expect(actionableClaimCount(list), 2);
      expect(actionableClaimCount(const []), 0);
    });

    test('sortClaims puts actionable first and keeps the server order otherwise', () {
      final a = claim(invoiceStatus: 'PAID');
      final b = claim(invoiceStatus: 'PENDING');
      final c = claim(invoiceStatus: 'PAID');
      final d = claim(invoiceStatus: 'PENDING_CONFIRMATION');
      expect(sortClaims([a, b, c, d]), [b, d, a, c]);
    });
  });
}
