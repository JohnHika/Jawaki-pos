import { INestApplication, ValidationPipe, VersioningType } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerModule } from '@nestjs/throttler';
import { StatementsPublicController } from './statements-public.controller';
import { StatementsService } from './statements.service';
import { StatementView } from './statements.types';

const view: StatementView = {
  business: { name: 'Kamau Imports', phone: null, logo: null, payInstructions: 'Paybill 123456' },
  debtor: { name: 'John Kamau', kind: 'CUSTOMER' },
  asOf: new Date('2026-10-24T08:00:00Z'),
  outstanding: 5_000,
  overdue: 0,
  oldestOverdueDays: 0,
  items: [],
  payments: [],
  message: null,
  expiresAt: null,
  inviteCode: 'KAMA-7H2Q',
};

describe('public statement routes', () => {
  let app: INestApplication;
  let base: string;
  const statements = {
    openLink: jest.fn(),
    renderPdfForToken: jest.fn(),
    submitClaim: jest.fn(),
  };
  const TOKEN = 'tok_abcdefghijklmnopqrstuvwxyz012345';

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [ThrottlerModule.forRoot([{ ttl: 60_000, limit: 1000 }])],
      controllers: [StatementsPublicController],
      providers: [{ provide: StatementsService, useValue: statements }],
    }).compile();
    app = moduleRef.createNestApplication();
    // Same versioning and validation as main.ts: the short link must work without /api/v1.
    app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1', prefix: 'api/v' });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
    await app.listen(0);
    base = (await app.getUrl()).replace('[::1]', 'localhost');
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => jest.clearAllMocks());

  it('serves the page at /s/:token with a strict content policy and no caching', async () => {
    statements.openLink.mockResolvedValue(view);
    const res = await fetch(`${base}/s/${TOKEN}`, { headers: { 'user-agent': 'Mozilla/5.0 Chrome/120 Mobile' } });
    const html = await res.text();

    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('text/html');
    expect(html).toContain('KES 5,000');
    const csp = res.headers.get('content-security-policy') ?? '';
    expect(csp).toContain("default-src 'none'");
    expect(csp).toContain("frame-ancestors 'none'");
    const nonce = csp.match(/script-src 'nonce-([^']+)'/)?.[1];
    expect(nonce).toBeTruthy();
    expect(html).toContain(`<script nonce="${nonce}">`);
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(res.headers.get('x-robots-tag')).toContain('noindex');
    expect(statements.openLink).toHaveBeenCalledWith(TOKEN, 'Mozilla/5.0 Chrome/120 Mobile');
  });

  it('picks Kiswahili from the query or the browser language', async () => {
    statements.openLink.mockResolvedValue(view);
    expect(await (await fetch(`${base}/s/${TOKEN}?lang=sw`)).text()).toContain('Nimelipa');
    expect(await (await fetch(`${base}/s/${TOKEN}`, { headers: { 'accept-language': 'sw-KE,sw;q=0.9' } })).text()).toContain('Nimelipa');
    expect(await (await fetch(`${base}/s/${TOKEN}`, { headers: { 'accept-language': 'en-GB' } })).text()).toContain('I have paid');
  });

  it('answers 410 with a plain page, and no script, for a bad or expired link', async () => {
    statements.openLink.mockResolvedValue(null);
    const res = await fetch(`${base}/s/${TOKEN}`);
    const html = await res.text();
    expect(res.status).toBe(410);
    expect(html).toContain('This link has expired');
    expect(html).not.toContain('<script');
    expect(res.headers.get('content-security-policy')).toContain("script-src 'none'");
  });

  it('downloads the PDF as an attachment', async () => {
    statements.renderPdfForToken.mockResolvedValue({ buffer: Buffer.from('%PDF-1.4 test'), filename: 'statement-john-kamau.pdf' });
    const res = await fetch(`${base}/s/${TOKEN}/pdf?lang=en`);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('application/pdf');
    expect(res.headers.get('content-disposition')).toContain('attachment; filename="statement-john-kamau.pdf"');
    expect(Buffer.from(await res.arrayBuffer()).toString()).toContain('%PDF-1.4');
    expect(statements.renderPdfForToken).toHaveBeenCalledWith(TOKEN, 'en');
  });

  it('accepts a reply as JSON and validates it', async () => {
    statements.submitClaim.mockResolvedValue({ received: true, message: 'Thank you. Kamau Imports has been told.' });
    const ok = await fetch(`${base}/s/${TOKEN}/claims`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 1500 }),
    });
    expect(ok.status).toBe(200);
    expect(await ok.json()).toMatchObject({ received: true });
    expect(statements.submitClaim).toHaveBeenCalledWith(TOKEN, expect.objectContaining({ kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 1500 }));

    const bad = await fetch(`${base}/s/${TOKEN}/claims`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'PAID', mpesaCode: 'not a code!', amount: 1500 }),
    });
    expect(bad.status).toBe(400);

    const extra = await fetch(`${base}/s/${TOKEN}/claims`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 1, tenantId: 'someone-else' }),
    });
    expect(extra.status).toBe(400);
  });
});
