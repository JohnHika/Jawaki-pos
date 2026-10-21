// QA FIXTURES for a THROWAWAY local database only (aca_dev on localhost:54329).
// Never run against production. Refuses to run unless DATABASE_URL is localhost.
const path = require('path');
const BACKEND = path.resolve(__dirname, '../../backend');
const { PrismaClient } = require(path.join(BACKEND, 'node_modules/@prisma/client'));

if (!/localhost|127\.0\.0\.1/.test(process.env.DATABASE_URL || '')) {
  console.error('REFUSING: DATABASE_URL is not local');
  process.exit(1);
}

const prisma = new PrismaClient();
const day = 86_400_000;

async function main() {
  const now = Date.now();
  const mk = async (name, slug, plan, status, endOffsetDays, extra = {}) =>
    prisma.tenant.upsert({
      where: { slug },
      update: {},
      create: {
        name, slug, plan, subscriptionStatus: status,
        currentPeriodStart: new Date(now - (30 - endOffsetDays) * day),
        currentPeriodEnd: new Date(now + endOffsetDays * day),
        activationStatus: 'PAID',
        ...extra,
      },
    });

  const t1 = await mk('QA Fixture Mart', 'qa-fixture-mart', 'CORE', 'ACTIVE', 9);
  const t2 = await mk('QA Fixture Pharmacy', 'qa-fixture-pharmacy', 'CORE', 'PAST_DUE', -3);
  const t3 = await mk('QA Fixture Hardware', 'qa-fixture-hardware', 'TRIAL', 'TRIAL', 5, { activationStatus: 'PENDING' });

  for (const [t, emails] of [[t1, ['owner@qa-mart.test', 'cashier@qa-mart.test']], [t2, ['owner@qa-pharm.test']], [t3, ['owner@qa-hw.test']]]) {
    for (const [i, email] of emails.entries()) {
      await prisma.user.upsert({
        where: { tenantId_email: { tenantId: t.id, email } },
        update: {},
        create: {
          tenantId: t.id, email, firstName: i === 0 ? 'Owner' : 'Cashier', lastName: 'Fixture',
          role: i === 0 ? 'ADMIN' : 'CASHIER', passwordHash: 'x', lastLoginAt: new Date(now - i * day),
        },
      });
    }
  }

  let branch = await prisma.branch.findFirst({ where: { tenantId: t1.id } });
  if (!branch) branch = await prisma.branch.create({ data: { tenantId: t1.id, name: 'Main Branch', code: 'QA1' } });
  await prisma.device.upsert({
    where: { deviceUuid: 'qa-device-1' }, update: {},
    create: { branchId: branch.id, deviceUuid: 'qa-device-1', name: 'Till 1', model: 'SM-A15', osVersion: '14', appVersion: '1.0.74', lastActiveAt: new Date(now - 3_600_000), lastSyncAt: new Date(now - 3_000_000) },
  });

  const inv = async (tenant, status, amount, ageDays, ref) => {
    const exists = await prisma.subscriptionInvoice.findFirst({ where: { reference: ref } });
    if (exists) return exists;
    return prisma.subscriptionInvoice.create({
      data: {
        tenantId: tenant.id, plan: 'CORE', amount, status, provider: status === 'PAID' ? 'PAYSTACK' : null,
        reference: ref, periodStart: new Date(now - ageDays * day), periodEnd: new Date(now - (ageDays - 30) * day),
        paidAt: status === 'PAID' ? new Date(now - ageDays * day) : null, createdAt: new Date(now - ageDays * day),
      },
    });
  };
  await inv(t1, 'PAID', 3200, 5, 'QA-INV-1');
  await inv(t1, 'PAID', 3200, 35, 'QA-INV-2');
  await inv(t1, 'PAID', 3200, 65, 'QA-INV-3');
  const pending = await inv(t2, 'PENDING', 3200, 12, 'QA-INV-4');
  await inv(t2, 'PAID', 35000, 40, 'QA-INV-5');

  if (!(await prisma.subscriptionPaymentClaim.findFirst({ where: { mpesaCode: 'QA1MPESA01' } }))) {
    await prisma.subscriptionPaymentClaim.create({
      data: { tenantId: t2.id, invoiceId: pending.id, mpesaCode: 'QA1MPESA01', amount: 3200 },
    });
  }
  console.log('FIXTURES_OK', { t1: t1.id, t2: t2.id, t3: t3.id });
}
main().catch((e) => { console.error(e); process.exit(1); }).finally(() => prisma.$disconnect());
