const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
async function main() {
  const tenant = await prisma.tenant.findUnique({ where: { slug: 'levisa-ventures' } });
  if (!tenant) { console.log('Tenant not found'); return; }
  console.log('Tenant:', tenant.id, tenant.name);
  const users = await prisma.user.findMany({ where: { tenantId: tenant.id }, select: { id: true, email: true, firstName: true, lastName: true, role: true, isActive: true } });
  console.log('Users:', JSON.stringify(users, null, 2));
  await prisma.$disconnect();
}
main().catch(e => { console.error(e); process.exit(1); });
