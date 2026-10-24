import { validate } from 'class-validator';
import { StatementTargetDto } from './statements.dto';

describe('StatementTargetDto', () => {
  it('accepts legacy offline customer IDs', async () => {
    const target = Object.assign(new StatementTargetDto(), {
      customerId: 'legacy-customer-42',
    });

    expect(await validate(target)).toEqual([]);
  });

  it('rejects an empty customer ID and keeps peer shop IDs as UUIDs', async () => {
    const emptyCustomer = Object.assign(new StatementTargetDto(), {
      customerId: '',
    });
    const invalidShop = Object.assign(new StatementTargetDto(), {
      debtorId: 'legacy-shop-42',
    });

    expect((await validate(emptyCustomer)).map((error) => error.property))
      .toContain('customerId');
    expect((await validate(invalidShop)).map((error) => error.property))
      .toContain('debtorId');
  });
});
