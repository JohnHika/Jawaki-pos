import { PrismaClient } from '@prisma/client';
import * as bcryptjs from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding database...');

  // ─── Tenant ───
  const tenantId = uuidv4();
  await prisma.tenant.upsert({
    where: { slug: 'jawaki-adventures' },
    update: {},
    create: {
      id: tenantId,
      name: 'JAWAKI ADVENTURES',
      slug: 'jawaki-adventures',
      settings: {},
    },
  });
  console.log('✅ Tenant: JAWAKI ADVENTURES');

  // ─── Branch ───
  const branchId = uuidv4();
  await prisma.branch.upsert({
    where: { tenantId_code: { tenantId, code: 'HQ-001' } },
    update: {},
    create: {
      id: branchId,
      tenantId,
      name: 'Headquarters',
      code: 'HQ-001',
      address: 'Nairobi, Kenya',
      phone: '+254700100200',
      timezone: 'Africa/Nairobi',
    },
  });
  console.log('✅ Branch: Headquarters (HQ-001)');

  // ─── Admin User ───
  const hashedPassword = await bcryptjs.hash('Admin123', 12);
  const hashedPin = await bcryptjs.hash('0000', 12);
  const userId = uuidv4();

  await prisma.user.upsert({
    where: { tenantId_email: { tenantId, email: 'admin@jawaki.com' } },
    update: {},
    create: {
      id: userId,
      tenantId,
      email: 'admin@jawaki.com',
      passwordHash: hashedPassword,
      pin: hashedPin,
      firstName: 'Admin',
      lastName: 'User',
      role: 'ADMIN',
      isActive: true,
    },
  });

  await prisma.userBranch.upsert({
    where: { userId_branchId: { userId, branchId } },
    update: {},
    create: {
      userId,
      branchId,
      isPrimary: true,
    },
  });
  console.log('✅ Admin User: admin@jawaki.com / Admin123');

  console.log('\n🎉 Seeding complete!');
  console.log('Login: admin@jawaki.com / Admin123 / PIN: 0000');
  console.log('\nNo products were seeded. Use the backend API or mobile app to add them.');
}

main()
  .catch((e) => {
    console.error('Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
