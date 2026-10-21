// Reset QA state in the THROWAWAY local DB only.
const path = require('path');
const { PrismaClient } = require(path.join(path.resolve(__dirname, '../../backend'), 'node_modules/@prisma/client'));
if (!/localhost|127\.0\.0\.1/.test(process.env.DATABASE_URL || '')) { console.error('REFUSING: not local'); process.exit(1); }
const p = new PrismaClient();
(async () => {
  await p.platformAuditLog.deleteMany({});
  await p.platformAdminSession.deleteMany({});
  await p.platformTenantNote.deleteMany({});
  await p.platformAdmin.deleteMany({ where: { email: { not: 'qa-owner@aca.test' } } });
  await p.platformAdmin.updateMany({ data: { failedLoginAttempts: 0, lockedUntil: null, twoFactorEnabled: false, twoFactorSecretEnc: null, twoFactorBackupHashes: null, mustChangePassword: false } });
  await p.subscriptionInvoice.deleteMany({ where: { plan: 'CREDIT' } });
  await p.tenant.updateMany({ data: { isActive: true } });
  await p.user.updateMany({ data: { isActive: true } });
  console.log('RESET_OK');
})().finally(() => p.$disconnect());
