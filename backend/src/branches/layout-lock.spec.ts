import { ForbiddenException } from '@nestjs/common';
import { applyBusinessTypeLock } from './layout-lock';

const paid = (businessLayout?: any, extra: Record<string, any> = {}) => ({
  activationStatus: 'ACTIVE',
  settings: { ...(businessLayout ? { businessLayout } : {}), ...extra },
});

describe('applyBusinessTypeLock', () => {
  const bookshop = { profileId: 'bookshop', additionalProfileIds: [] as string[], hiddenPaths: [] };

  it('lets an unpaid shop change its business type freely', () => {
    const tenant = { activationStatus: 'PENDING', settings: { businessLayout: bookshop } };
    expect(() =>
      applyBusinessTypeLock(tenant, { businessLayout: { ...bookshop, profileId: 'cafe_takeaway' } }),
    ).not.toThrow();
  });

  it('lets a paid shop choose its layout the first time', () => {
    expect(() =>
      applyBusinessTypeLock(paid(), { businessLayout: { profileId: 'kamukunji_counter' } }),
    ).not.toThrow();
  });

  it('keeps tweaks to labels and navigation free for a paid shop', () => {
    const out = applyBusinessTypeLock(paid(bookshop), {
      businessLayout: { ...bookshop, hiddenPaths: ['/reports'], actionLabels: { sell: 'Sell' } },
    });
    expect(out?.businessLayout.hiddenPaths).toEqual(['/reports']);
  });

  it('blocks a paid shop switching business type without approval', () => {
    expect(() =>
      applyBusinessTypeLock(paid(bookshop), { businessLayout: { ...bookshop, profileId: 'cafe_takeaway' } }),
    ).toThrow(ForbiddenException);
  });

  it('blocks adding an extra business type without approval', () => {
    expect(() =>
      applyBusinessTypeLock(paid(bookshop), {
        businessLayout: { ...bookshop, additionalProfileIds: ['cafe_takeaway'] },
      }),
    ).toThrow(ForbiddenException);
  });

  it('allows the approved change once and clears the approval', () => {
    const tenant = paid(bookshop, {
      approvedProfileChange: { requestId: 'r1', profileId: 'cafe_takeaway', additionalProfileIds: [] },
    });
    const out = applyBusinessTypeLock(tenant, { businessLayout: { ...bookshop, profileId: 'cafe_takeaway' } });
    expect(out?.approvedProfileChange).toBeNull();
  });

  it('does not accept a different type than the one approved', () => {
    const tenant = paid(bookshop, {
      approvedProfileChange: { requestId: 'r1', profileId: 'cafe_takeaway', additionalProfileIds: [] },
    });
    expect(() =>
      applyBusinessTypeLock(tenant, { businessLayout: { ...bookshop, profileId: 'pharmacy_retail' } }),
    ).toThrow(ForbiddenException);
  });

  it('ignores an approval a client tries to write for itself', () => {
    const out = applyBusinessTypeLock(paid(bookshop), {
      approvedProfileChange: { profileId: 'cafe_takeaway' },
      businessLayout: bookshop,
    });
    expect(out).not.toHaveProperty('approvedProfileChange');
    expect(() =>
      applyBusinessTypeLock(paid(bookshop), {
        approvedProfileChange: { profileId: 'cafe_takeaway' },
        businessLayout: { ...bookshop, profileId: 'cafe_takeaway' },
      }),
    ).toThrow(ForbiddenException);
  });

  it('leaves settings without a layout alone', () => {
    expect(applyBusinessTypeLock(paid(bookshop), { currency: 'KES' })).toEqual({ currency: 'KES' });
  });
});
