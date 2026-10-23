import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { ImportsService } from './imports.service';

const D = (n: number) => new Prisma.Decimal(n);

function shipment(over: Record<string, unknown> = {}) {
  return {
    id: 's1',
    tenantId: 't1',
    branchId: 'b1',
    title: 'Container 1',
    reference: 'MSKU123',
    currency: 'USD',
    fxRate: D(130),
    allocationBasis: 'VALUE',
    status: 'ARRIVED',
    createdAt: new Date(),
    expectedArrival: null,
    arrivedAt: null,
    receivedAt: null,
    notes: null,
    origin: null,
    participants: [
      { id: 'me', name: 'My shop', phone: null, isSelf: true, notes: null },
      { id: 'wanjiru', name: 'Wanjiru', phone: null, isSelf: false, notes: null },
    ],
    items: [
      {
        id: 'mine', participantId: 'me', productId: 'p1', description: 'Sufuria set',
        quantity: D(100), unit: 'piece', unitCost: D(2), cbm: null, weightKg: null, receivedQty: null,
      },
      {
        id: 'theirs', participantId: 'wanjiru', productId: null, description: 'Plastic basins',
        quantity: D(100), unit: 'piece', unitCost: D(2), cbm: null, weightKg: null, receivedQty: null,
      },
    ],
    // 200 USD each side = 26,000 KES each; costs are 26,000 total => 50% uplift
    costs: [{ id: 'c1', type: 'FREIGHT', amountKes: D(26_000), amount: D(26_000), currency: 'KES', fxRate: D(1), createdAt: new Date() }],
    payments: [],
    ...over,
  };
}

function build(s: any, product: any = { id: 'p1', name: 'Sufuria set', costPrice: D(200), basePrice: D(300), unit: 'piece' }) {
  const prisma: any = {
    importShipment: {
      findFirst: jest.fn().mockResolvedValue(s),
      update: jest.fn(),
    },
    importItem: { update: jest.fn() },
    importCost: { create: jest.fn() },
    importParticipant: { findFirst: jest.fn().mockResolvedValue({ id: 'me' }) },
    product: {
      findFirst: jest.fn().mockResolvedValue(product),
      update: jest.fn(),
    },
    stock: { findUnique: jest.fn().mockResolvedValue({ quantity: D(0) }) },
    $transaction: jest.fn(async (ops: any[]) => Promise.all(ops)),
  };
  const redis: any = { invalidatePattern: jest.fn() };
  const rates: any = { rateFor: jest.fn().mockResolvedValue(6.5) };
  const inventory: any = { receiveBatch: jest.fn().mockResolvedValue({}) };
  const accountability: any = { record: jest.fn(), raise: jest.fn() };
  const service = new ImportsService(prisma, redis, rates, inventory, accountability);
  jest.spyOn(service, 'get').mockResolvedValue({ id: 's1' } as any);
  return { service, prisma, redis, rates, inventory, accountability };
}

describe('ImportsService.receive', () => {
  it('books my goods at their true landed cost and ignores other traders\' lines', async () => {
    const { service, inventory, prisma } = build(shipment());
    const result = await service.receive('u1', 't1', 's1', {});

    expect(inventory.receiveBatch).toHaveBeenCalledTimes(1);
    const dto = inventory.receiveBatch.mock.calls[0][2];
    // 100 pcs x $2 x 130 = 26,000 goods + 13,000 freight share = 39,000 / 100
    expect(dto.batches[0].costPrice).toBe(390);
    expect(dto.batches[0].quantity).toBe(100);
    expect(dto.productId).toBe('p1');
    expect(dto.reference).toBe('import:s1');

    expect(prisma.importShipment.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ status: 'RECEIVED' }) }),
    );
    expect(result.booked).toHaveLength(1);
  });

  it('carries a short delivery on the units that did arrive', async () => {
    const { service, inventory } = build(shipment());
    await service.receive('u1', 't1', 's1', { items: [{ itemId: 'mine', receivedQty: 80 }] });
    // 39,000 spread over 80 pieces, not 100
    expect(inventory.receiveBatch.mock.calls[0][2].batches[0].costPrice).toBe(487.5);
    expect(inventory.receiveBatch.mock.calls[0][2].batches[0].quantity).toBe(80);
  });

  it('averages the new cost with stock already on the shelf', async () => {
    const { service, prisma } = build(shipment());
    prisma.stock.findUnique.mockResolvedValue({ quantity: D(100) }); // 100 @ 200 on hand
    await service.receive('u1', 't1', 's1', {});
    // (100*200 + 100*390) / 200 = 295
    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { costPrice: 295 } });
  });

  it('warns the owner, with a suggested price, when the new cost eats the margin', async () => {
    const { service, accountability } = build(shipment());
    await service.receive('u1', 't1', 's1', {});
    // cost 200 -> 390 and the shelf price is 300: the stock now costs more than it sells for.
    const call = accountability.raise.mock.calls.find((c: any[]) => c[0].type === 'PRICE_REVIEW');
    expect(call).toBeDefined();
    expect(call[0].severity).toBe('HIGH');
    expect(call[0].title).toMatch(/below landed cost/i);
  });

  it('suggests a price that keeps the usual markup when the cost merely rises', async () => {
    const { service, accountability } = build(
      shipment(),
      { id: 'p1', name: 'Sufuria set', costPrice: D(200), basePrice: D(600), unit: 'piece' },
    );
    await service.receive('u1', 't1', 's1', {});
    const call = accountability.raise.mock.calls.find((c: any[]) => c[0].type === 'PRICE_REVIEW')[0];
    expect(call.severity).toBe('MEDIUM');
    // 3x markup on a 390 cost = 1,170
    expect(call.body).toContain('1,170');
  });

  it('skips a line that is not linked to a product instead of failing the whole receipt', async () => {
    const s = shipment();
    (s.items[0] as any).productId = null;
    const { service, inventory } = build(s);
    const result = await service.receive('u1', 't1', 's1', {});
    expect(inventory.receiveBatch).not.toHaveBeenCalled();
    expect(result.skipped[0].reason).toMatch(/not linked/i);
  });

  it('cannot be received twice', async () => {
    const { service, inventory } = build(shipment({ status: 'RECEIVED' }));
    await expect(service.receive('u1', 't1', 's1', {})).rejects.toBeInstanceOf(ConflictException);
    expect(inventory.receiveBatch).not.toHaveBeenCalled();
  });

  it('cannot be received before it has left port', async () => {
    const { service } = build(shipment({ status: 'PLANNED' }));
    await expect(service.receive('u1', 't1', 's1', {})).rejects.toBeInstanceOf(ConflictException);
  });

  it('rejects a received line that is not part of the shipment', async () => {
    const { service } = build(shipment());
    await expect(
      service.receive('u1', 't1', 's1', { items: [{ itemId: 'nope', receivedQty: 1 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('ImportsService.addCost', () => {
  it('converts a foreign-currency cost at the live rate when none is given', async () => {
    const { service, prisma, rates } = build(shipment({ status: 'IN_TRANSIT' }));
    prisma.importShipment.findUnique = jest.fn().mockResolvedValue(shipment({ status: 'IN_TRANSIT' }));
    await service.addCost('u1', 't1', 's1', { type: 'FREIGHT', amount: 1000, currency: 'usd' } as any);
    expect(rates.rateFor).toHaveBeenCalledWith('USD');
    const data = prisma.importCost.create.mock.calls[0][0].data;
    expect(data.fxRate).toBe(6.5);
    expect(data.amountKes).toBe(6500);
  });

  it('keeps KES costs at face value', async () => {
    const { service, prisma, rates } = build(shipment({ status: 'IN_TRANSIT' }));
    prisma.importShipment.findUnique = jest.fn().mockResolvedValue(shipment({ status: 'IN_TRANSIT' }));
    await service.addCost('u1', 't1', 's1', { type: 'CLEARING', amount: 15_000 } as any);
    expect(rates.rateFor).not.toHaveBeenCalled();
    expect(prisma.importCost.create.mock.calls[0][0].data.amountKes).toBe(15_000);
  });

  it('will not change the costs of a shipment that is already in stock', async () => {
    const { service } = build(shipment({ status: 'RECEIVED' }));
    await expect(
      service.addCost('u1', 't1', 's1', { type: 'DUTY', amount: 100 } as any),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});
