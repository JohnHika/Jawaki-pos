import { parseMpesaText } from './mpesa.parse';
import { nameOverlap, nineDigits, phoneMatches, rankCandidates } from './mpesa.match';
import { planAllocations } from './debt-collection.service';

describe('parseMpesaText', () => {
  it('reads a personal-number receipt', () => {
    const { entries } = parseMpesaText(
      'QJK1A2B3C4 Confirmed. You have received Ksh1,500.00 from JOHN KAMAU 0712345678 on 12/10/26 at 2:15 PM. New M-PESA balance is Ksh8,200.00. Transaction cost, Ksh0.00.',
    );
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      code: 'QJK1A2B3C4',
      amount: 1500,
      senderName: 'JOHN KAMAU',
      senderPhone: '0712345678',
    });
    // 2:15 PM in Nairobi (UTC+3) is 11:15 UTC.
    expect(entries[0].paidAt?.toISOString()).toBe('2026-10-12T11:15:00.000Z');
  });

  it('keeps a masked phone number as written', () => {
    const { entries } = parseMpesaText(
      'SGH5X6Y7Z8 Confirmed. Ksh2,000.00 received from MARY WANJIKU 0722***456 on 13/10/26 at 9:05 AM. New Business Balance is Ksh9,000.00',
    );
    expect(entries[0]).toMatchObject({ amount: 2000, senderName: 'MARY WANJIKU', senderPhone: '0722***456' });
  });

  it('reads the till wording with the number before the name', () => {
    const { entries } = parseMpesaText(
      'QKA1B2C3D4 Confirmed.Ksh500.00 received from 254712345678 JANE DOE. Account Number 12345 New Utility balance is Ksh3,000.00',
    );
    expect(entries[0]).toMatchObject({ code: 'QKA1B2C3D4', amount: 500, senderName: 'JANE DOE', senderPhone: '254712345678' });
  });

  it('ignores money that went out', () => {
    const { entries, skipped } = parseMpesaText(
      'QJL1A2B3C4 Confirmed. Ksh500.00 sent to PETER OTIENO 0733123456 on 12/10/26 at 3:00 PM. New M-PESA balance is Ksh7,700.00.\n' +
        'QJL1A2B3C5 Confirmed. Ksh1,200.00 paid to KENYA POWER. on 12/10/26 at 3:10 PM.',
    );
    expect(entries).toHaveLength(0);
    expect(skipped).toBe(2);
  });

  it('splits several pasted messages and drops a repeated one', () => {
    const one = 'QJK1A2B3C4 Confirmed. You have received Ksh1,500.00 from JOHN KAMAU 0712345678 on 12/10/26 at 2:15 PM. New M-PESA balance is Ksh8,200.00.';
    const two = 'QJK1A2B3C5 Confirmed. You have received Ksh300.00 from ANN MUTHONI 0701234567 on 12/10/26 at 4:00 PM. New M-PESA balance is Ksh8,500.00.';
    const { entries, skipped } = parseMpesaText(`${one}\n\n${two}\n${one}`);
    expect(entries.map((e) => e.code)).toEqual(['QJK1A2B3C4', 'QJK1A2B3C5']);
    expect(skipped).toBe(1);
  });

  it('reads an M-Pesa statement CSV and only takes money in', () => {
    const csv = [
      'Receipt No.,Completion Time,Details,Transaction Status,Paid In,Withdrawn,Balance',
      'QJK1A2B3C4,2026-10-12 14:15:00,Funds received from - 254712345678 JOHN KAMAU,Completed,1500.00,,8200.00',
      'QJK1A2B3C5,2026-10-12 15:00:00,Customer Payment to Small Business,Completed,,500.00,7700.00',
      '"QJK1A2B3C6",2026-10-13 08:00:00,"Funds received from - 0722***456 MARY W",Completed,"2,000.00",,9700.00',
    ].join('\n');
    const { entries, skipped } = parseMpesaText(csv);
    expect(entries.map((e) => [e.code, e.amount])).toEqual([
      ['QJK1A2B3C4', 1500],
      ['QJK1A2B3C6', 2000],
    ]);
    expect(entries[0]).toMatchObject({ senderName: 'JOHN KAMAU', senderPhone: '254712345678' });
    expect(entries[0].paidAt?.toISOString()).toBe('2026-10-12T11:15:00.000Z');
    expect(skipped).toBe(1);
  });

  it('copes with junk', () => {
    expect(parseMpesaText('')).toEqual({ entries: [], skipped: 0 });
    expect(parseMpesaText('hello there, nothing to see').entries).toHaveLength(0);
  });
});

describe('matching a payment to who owes', () => {
  const candidates = [
    { kind: 'CUSTOMER' as const, id: 'c1', name: 'John Kamau', phone: '0712345678', outstanding: 1500 },
    { kind: 'CUSTOMER' as const, id: 'c2', name: 'Mary Wanjiku', phone: '+254722111456', outstanding: 800 },
    { kind: 'SHOP' as const, id: 's1', name: 'Kamau General Stores', phone: null, outstanding: 20000 },
  ];

  it('normalises numbers to their last nine digits', () => {
    expect(nineDigits('0712345678')).toBe('712345678');
    expect(nineDigits('+254 712 345 678')).toBe('712345678');
    expect(nineDigits('0722***456')).toBe('722***456');
    expect(nineDigits('12345')).toBeNull();
  });

  it('matches a masked number against a full one, but not a different one', () => {
    expect(phoneMatches('0722***456', '+254722111456')).toBe(true);
    expect(phoneMatches('0722***456', '0722111999')).toBe(false);
    expect(phoneMatches('0722***456', null)).toBe(false);
    expect(phoneMatches('0*********', '0722111456')).toBe(false);
  });

  it('scores name overlap by the sender\'s words', () => {
    expect(nameOverlap('JOHN KAMAU', 'John Kamau')).toBe(1);
    expect(nameOverlap('JOHN KAMAU', 'Kamau General Stores')).toBe(0.5);
    expect(nameOverlap(null, 'John')).toBe(0);
  });

  it('ranks the phone-and-name match first, with an amount bonus', () => {
    const ranked = rankCandidates({ senderName: 'JOHN KAMAU', senderPhone: '0712345678', amount: 1500 }, candidates);
    expect(ranked[0]).toMatchObject({ id: 'c1', confidence: 'HIGH' });
    expect(ranked[0].reasons).toEqual(expect.arrayContaining(['Phone number matches', 'Name matches', 'Amount equals what they owe']));
    // The shop only shares one name word, so it ranks lower.
    expect(ranked.map((r) => r.id)).toEqual(['c1', 's1']);
  });

  it('trusts the code a customer sent from their own statement link above all', () => {
    const ranked = rankCandidates(
      { senderName: 'SOMEONE ELSE', senderPhone: '0799000000', amount: 100 },
      candidates,
      { kind: 'CUSTOMER', id: 'c2' },
    );
    expect(ranked[0]).toMatchObject({ id: 'c2', confidence: 'HIGH' });
  });

  it('offers nothing when there is no sign of who paid', () => {
    expect(rankCandidates({ senderName: 'NOBODY KNOWN', senderPhone: '0700000000', amount: 5 }, candidates)).toEqual([]);
  });
});

describe('planAllocations', () => {
  const open = [
    { id: 'a', branchId: 'b1', outstanding: 500 },
    { id: 'b', branchId: 'b1', outstanding: 700 },
    { id: 'c', branchId: 'b2', outstanding: 300 },
  ];

  it('pays the oldest debt first and never more than is owed', () => {
    const plan = planAllocations(open, 900);
    expect(plan.allocations).toEqual([
      { receivableId: 'a', branchId: 'b1', amount: 500 },
      { receivableId: 'b', branchId: 'b1', amount: 400 },
    ]);
    expect(plan).toMatchObject({ applied: 900, unallocated: 0 });
  });

  it('reports what was more than they owed', () => {
    const plan = planAllocations(open, 2000);
    expect(plan.applied).toBe(1500);
    expect(plan.unallocated).toBe(500);
    expect(plan.allocations).toHaveLength(3);
  });

  it('keeps cents exact', () => {
    const plan = planAllocations([{ id: 'a', branchId: 'b', outstanding: 10.1 }, { id: 'b', branchId: 'b', outstanding: 10.2 }], 10.15);
    expect(plan.allocations).toEqual([{ receivableId: 'a', branchId: 'b', amount: 10.1 }, { receivableId: 'b', branchId: 'b', amount: 0.05 }]);
    expect(plan.unallocated).toBe(0);
  });

  it('does nothing when nothing is owed', () => {
    expect(planAllocations([], 100)).toEqual({ allocations: [], applied: 0, unallocated: 100 });
  });
});
