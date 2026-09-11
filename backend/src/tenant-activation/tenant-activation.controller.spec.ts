import { TenantActivationController } from './tenant-activation.controller';

describe('TenantActivationController payment callback', () => {
  it('returns a URL-encoded Axon deep link for the payment reference', () => {
    const controller = new TenantActivationController({} as any, {} as any);

    const html = controller.callback('AXON-tenant/ref?paid=true');

    expect(html).toContain('Payment received');
    expect(html).toContain(
      'axonpos://payment/activation?reference=AXON-tenant%2Fref%3Fpaid%3Dtrue',
    );
    expect(html).toContain('window.location.replace');
  });

  it('does not embed an untrusted raw reference in the callback URL', () => {
    const controller = new TenantActivationController({} as any, {} as any);

    const html = controller.callback('" /><script>alert(1)</script>');

    expect(html).not.toContain('" /><script>');
    expect(html).toContain('axonpos://payment/activation?reference=');
  });
});
