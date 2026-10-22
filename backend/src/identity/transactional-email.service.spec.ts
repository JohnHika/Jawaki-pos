import { ConfigService } from '@nestjs/config';
import { ServiceUnavailableException } from '@nestjs/common';
import { TransactionalEmailService } from './transactional-email.service';

describe('TransactionalEmailService', () => {
  const fetchMock = jest.fn();
  const values: Record<string, string> = {
    ZEPTOMAIL_SEND_API_KEY: 'test-api-key',
    EMAIL_FROM: 'Counterbase <support@arche-axon.xyz>',
  };
  const originalFetch = global.fetch;
  let service: TransactionalEmailService;

  beforeEach(() => {
    jest.clearAllMocks();
    global.fetch = fetchMock as unknown as typeof fetch;
    service = new TransactionalEmailService({
      get: (key: string) => values[key],
    } as unknown as ConfigService);
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('sends OTP email through the HTTPS API with the configured sender', async () => {
    fetchMock.mockResolvedValue({ ok: true });

    await service.sendOtp({
      to: 'support@arche-axon.xyz',
      code: '12345678',
      purpose: 'WORKSPACE_CREATION',
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, request] = fetchMock.mock.calls[0];
    expect(url.toString()).toBe('https://cpaas.zoho.com/v1.1/email');
    expect(request.headers.Authorization).toBe('Zoho-enczapikey test-api-key');
    expect(JSON.parse(request.body)).toEqual({
      from: { address: 'support@arche-axon.xyz', name: 'Counterbase' },
      to: [{ email_address: { address: 'support@arche-axon.xyz' } }],
      subject: 'Your Counterbase verification code',
      textbody:
        'Your Counterbase verification code is 12345678. It expires in 10 minutes.',
    });
  });

  it('reports provider failures without exposing provider details', async () => {
    fetchMock.mockResolvedValue({ ok: false, status: 401 });

    await expect(
      service.sendOtp({
        to: 'support@arche-axon.xyz',
        code: '12345678',
        purpose: 'WORKSPACE_CREATION',
      }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('rejects non-Zoho endpoints before sending the API key', async () => {
    values.ZEPTOMAIL_API_URL = 'https://example.com/v1.1/email';

    await expect(
      service.sendOtp({
        to: 'support@arche-axon.xyz',
        code: '12345678',
        purpose: 'WORKSPACE_CREATION',
      }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(fetchMock).not.toHaveBeenCalled();

    delete values.ZEPTOMAIL_API_URL;
  });
});
