const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
async function main() {
  const tenant = await prisma.tenant.findUnique({ where: { slug: 'levisa-ventures' } });
  if (!tenant) { console.log('Tenant not found'); process.exit(1); return; }

  const email = 'johnkimani576@gmail.com';
  const existing = await prisma.user.findFirst({ where: { tenantId: tenant.id, email } });
  if (existing) {
    console.log('User already exists:', existing.id, existing.email);
    await prisma.$disconnect();
    return;
  }

  // Get the first branch
  const branch = await prisma.branch.findFirst({ where: { tenantId: tenant.id } });
  if (!branch) { console.log('No branch found'); process.exit(1); return; }

  // Get the Admin role
  const adminRole = await prisma.role.findFirst({ where: { tenantId: tenant.id, name: 'Admin' } });
  if (!adminRole) { console.log('Admin role not found'); process.exit(1); return; }

  const user = await prisma.user.create({
    data: {
      tenantId: tenant.id,
      email: email,
      passwordHash: null,
      firstName: 'John',
      lastName: 'Hika',
      role: 'ADMIN',
      identityProvider: 'GOOGLE',
      identityVerifiedAt: new Date(),
      isActive: true,
      branches: { create: { branchId: branch.id, isPrimary: true } },
    },
  });

  await prisma.userRole.create({
    data: { userId: user.id, roleId: adminRole.id },
  });

  console.log('Created user:', user.id, user.email, 'in tenant', tenant.name);
  await prisma.$disconnect();
}
main().catch(e => { console.error(e); process.exit(1); });
