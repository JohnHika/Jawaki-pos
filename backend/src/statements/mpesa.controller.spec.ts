import { GoneException } from '@nestjs/common';
import { MpesaController } from './mpesa.controller';

describe('MpesaController', () => {
  const service = { history: jest.fn() } as any;
  const controller = new MpesaController(service);

  beforeEach(() => jest.clearAllMocks());

  it.each([
    ['parse', () => controller.parse()],
    ['apply', () => controller.apply()],
    ['ignore', () => controller.ignore()],
  ])('retires manual M-Pesa %s actions', (_action, invoke) => {
    expect(invoke).toThrow(GoneException);
    try {
      invoke();
    } catch (error) {
      expect((error as GoneException).message).toContain(
        'A copied message cannot verify payment',
      );
    }
  });

  it('keeps the existing matched-payment history read-only', async () => {
    service.history.mockResolvedValue([]);
    await expect(controller.history('tenant-1')).resolves.toEqual([]);
    expect(service.history).toHaveBeenCalledWith('tenant-1');
  });
});
