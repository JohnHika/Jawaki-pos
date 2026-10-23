import pdfMake = require('pdfmake');
import { buildStatementPdf, esc, formatKes, renderExpiredPage, renderStatementPage, shareMessage } from './statements.render';
import { StatementView } from './statements.types';

const view = (over: Partial<StatementView> = {}): StatementView => ({
  business: { name: 'Kamau Imports', phone: '0712 000 111', logo: null, payInstructions: 'Paybill 123456\nAccount: your name' },
  debtor: { name: 'John Kamau', kind: 'CUSTOMER' },
  asOf: new Date('2026-10-24T08:00:00Z'),
  outstanding: 12_500,
  overdue: 4_000,
  oldestOverdueDays: 12,
  items: [
    {
      date: new Date('2026-09-30T08:00:00Z'),
      reference: 'RCP-1001',
      description: 'Sufuria x6, Plates x12',
      original: 8_000,
      paid: 4_000,
      outstanding: 4_000,
      dueDate: new Date('2026-10-12T08:00:00Z'),
      overdueDays: 12,
    },
    {
      date: new Date('2026-10-20T08:00:00Z'),
      reference: 'RCP-1010',
      description: 'Jugs x20',
      original: 8_500,
      paid: 0,
      outstanding: 8_500,
      dueDate: new Date('2026-11-05T08:00:00Z'),
      overdueDays: 0,
    },
  ],
  payments: [{ date: new Date('2026-10-05T08:00:00Z'), amount: 4_000, method: 'MPESA', reference: 'QJK1A2B3C4' }],
  message: null,
  expiresAt: new Date('2026-11-07T08:00:00Z'),
  inviteCode: 'KAMA-7H2Q',
  ...over,
});

const opts = { lang: 'en' as const, token: 'tok_abcdefghijklmnopqrstuvwxyz', nonce: 'NONCE123', appDownloadPath: '/api/v1/app-updates/android/download' };

describe('formatKes', () => {
  it('drops cents when whole and keeps them otherwise', () => {
    expect(formatKes(12500)).toBe('KES 12,500');
    expect(formatKes(12500.5)).toBe('KES 12,500.50');
  });
});

describe('esc', () => {
  it('neutralises markup and quotes', () => {
    expect(esc(`<img src=x onerror="a('b')">&`)).toBe('&lt;img src=x onerror=&quot;a(&#39;b&#39;)&quot;&gt;&amp;');
  });
});

describe('statement page', () => {
  it('shows what is owed, what is late, how to pay, and the invitation with the shop\'s code', () => {
    const html = renderStatementPage(view(), opts);
    expect(html).toContain('KES 12,500');
    expect(html).toContain('Overdue: KES 4,000');
    expect(html).toContain('12 days overdue');
    expect(html).toContain('RCP-1001');
    expect(html).toContain('Paybill 123456');
    expect(html).toContain('KAMA-7H2Q');
    expect(html).toContain('/api/v1/app-updates/android/download');
    expect(html).toContain('I have paid');
    expect(html).toContain('/s/tok_abcdefghijklmnopqrstuvwxyz/pdf?lang=en');
  });

  it('cannot be turned against the reader through names or notes', () => {
    const html = renderStatementPage(
      view({
        debtor: { name: '<script>alert(1)</script>', kind: 'CUSTOMER' },
        message: '"><img src=x onerror=alert(1)>',
        business: { name: 'A&B <b>Shop</b>', phone: null, logo: 'https://cdn.example/x.png" onload="alert(1)', payInstructions: '<i>pay</i>' },
      }),
      opts,
    );
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).not.toContain('<img src=x');
    expect(html).not.toContain('<b>Shop</b>');
    expect(html).not.toContain('<i>pay</i>');
    expect(html).not.toMatch(/onload="alert/);
    // The only script is our own, carrying the nonce.
    expect(html.match(/<script/g)).toHaveLength(1);
    expect(html).toContain('<script nonce="NONCE123">');
  });

  it('offers no payment form once everything is paid', () => {
    const html = renderStatementPage(view({ outstanding: 0, overdue: 0, items: [] }), opts);
    expect(html).toContain('You owe nothing right now');
    expect(html).not.toContain('I have paid');
  });

  it('speaks Kiswahili on request and links back to English', () => {
    const html = renderStatementPage(view(), { ...opts, lang: 'sw' });
    expect(html).toContain('lang="sw"');
    expect(html).toContain('Nimelipa');
    expect(html).toContain('Imechelewa siku 12');
    expect(html).toContain('?lang=en');
  });

  it('shows a plain expired page without any statement data', () => {
    const html = renderExpiredPage('en');
    expect(html).toContain('This link has expired');
    expect(html).not.toContain('KES');
  });
});

describe('share message', () => {
  it('greets by first name and carries the link and any personal note', () => {
    const text = shareMessage(view({ message: 'Please settle by Friday' }), 'https://x.example/s/abc', 'en');
    expect(text).toContain('Hello John');
    expect(text).toContain('KES 12,500');
    expect(text).toContain('https://x.example/s/abc');
    expect(text).toContain('Please settle by Friday');
    expect(shareMessage(view(), 'https://x.example/s/abc', 'sw')).toContain('Habari John');
  });
});

describe('statement PDF', () => {
  beforeAll(() => {
    pdfMake.setFonts({
      Helvetica: { normal: 'Helvetica', bold: 'Helvetica-Bold', italics: 'Helvetica-Oblique', bolditalics: 'Helvetica-BoldOblique' },
    });
    pdfMake.setUrlAccessPolicy(() => false);
  });

  it('renders a real PDF in both languages', async () => {
    for (const lang of ['en', 'sw'] as const) {
      const buffer = await pdfMake.createPdf(buildStatementPdf(view({ message: 'Thank you for your business' }), lang) as any).getBuffer();
      expect(buffer.subarray(0, 5).toString()).toBe('%PDF-');
      expect(buffer.length).toBeGreaterThan(1500);
    }
  });

  it('renders a paid-up statement with no table', async () => {
    const buffer = await pdfMake.createPdf(buildStatementPdf(view({ outstanding: 0, overdue: 0, items: [], payments: [] }), 'en') as any).getBuffer();
    expect(buffer.subarray(0, 5).toString()).toBe('%PDF-');
  });
});
