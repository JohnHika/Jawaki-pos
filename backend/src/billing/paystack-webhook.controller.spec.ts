import { createHmac } from 'crypto';
import { ConfigService } from '@nestjs/config';
import { UnauthorizedException } from '@nestjs/common';
import { PaystackWebhookController } from './paystack-webhook.controller';

describe('PaystackWebhookController', () => {
  const testSecret = 'sk_test_counterbase_webhook_fixture';
  let activation: { handleWebhook: jest.Mock };
  let billing: { handleWebhook: jest.Mock };
  let merchant: { handleWebhook: jest.Mock };
  let controller: PaystackWebhookController;

  function request(body: unknown) {
    const rawBody = Buffer.from(JSON.stringify(body));
    const signature = createHmac('sha512', testSecret).update(rawBody).digest('hex');
    return {
      req: { rawBody, body } as any,
      signature,
    };
  }

  beforeEach(() => {
    activation = { handleWebhook: jest.fn().mockResolvedValue({ handled: true }) };
    billing = { handleWebhook: jest.fn().mockResolvedValue({ handled: true }) };
    merchant = { handleWebhook: jest.fn().mockResolvedValue({ handled: true }) };
    controller = new PaystackWebhookController(
      { get: jest.fn().mockReturnValue(testSecret) } as unknown as ConfigService,
      activation as any,
      billing as any,
      merchant as any,
    );
  });

  it('verifies the test-mode signature and routes activation events', async () => {
    const event = {
      event: 'charge.success',
      data: { reference: 'CB-QA-ACT-1', metadata: { product: 'axon_startup_activation' } },
    };
    const signed = request(event);

    await expect(controller.webhook(signed.req, signed.signature)).resolves.toEqual({
      handled: true,
    });
    expect(activation.handleWebhook).toHaveBeenCalledWith(event.event, event.data);
    expect(billing.handleWebhook).not.toHaveBeenCalled();
  });

  it('routes monthly subscription events, including JSON metadata', async () => {
    const event = {
      event: 'charge.success',
      data: {
        reference: 'CB-QA-SUB-1',
        metadata: JSON.stringify({ product: 'axon_subscription_invoice' }),
      },
    };
    const signed = request(event);

    await expect(controller.webhook(signed.req, signed.signature)).resolves.toEqual({
      handled: true,
    });
    expect(billing.handleWebhook).toHaveBeenCalledWith(event.event, event.data);
    expect(activation.handleWebhook).not.toHaveBeenCalled();
  });

  it('rejects a webhook signed with the wrong key', async () => {
    const signed = request({ event: 'charge.success', data: {} });

    await expect(controller.webhook(signed.req, '0'.repeat(128))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(activation.handleWebhook).not.toHaveBeenCalled();
    expect(billing.handleWebhook).not.toHaveBeenCalled();
  });

  it('routes a signed merchant sale notification even when Paystack omits metadata', async () => {
    const event = { event: 'charge.success', data: { reference: 'CBSALE-123' } };
    const signed = request(event);
    await expect(controller.webhook(signed.req, signed.signature)).resolves.toEqual({ handled: true });
    expect(merchant.handleWebhook).toHaveBeenCalledWith(event.event, event.data);
    expect(activation.handleWebhook).not.toHaveBeenCalled();
    expect(billing.handleWebhook).not.toHaveBeenCalled();
  });
});
