require('../backend/node_modules/dotenv').config({ path: require('path').resolve(__dirname, '../backend/.env') });
const { PrismaClient } = require('../backend/node_modules/@prisma/client');

const prisma = new PrismaClient();
const TENANT_ID = '1aded45f-edb2-4285-98f1-6607387a4c29';
const T = `'${TENANT_ID}'`;

const tenant = `"tenantId" = ${T}`;
const branch = `"branchId" IN (SELECT "id" FROM "branches" WHERE ${tenant})`;
const user = `"userId" IN (SELECT "id" FROM "users" WHERE ${tenant})`;
const product = `"productId" IN (SELECT "id" FROM "products" WHERE ${tenant})`;
const category = `"categoryId" IN (SELECT "id" FROM "categories" WHERE ${tenant})`;
const role = `"roleId" IN (SELECT "id" FROM "roles" WHERE ${tenant})`;
const sale = `"saleId" IN (SELECT "id" FROM "sales" WHERE ${branch} OR "userId" IN (SELECT "id" FROM "users" WHERE ${tenant}) OR "customerId" IN (SELECT "id" FROM "customers" WHERE ${tenant}))`;
const device = `"deviceId" IN (SELECT "id" FROM "devices" WHERE ${branch})`;
const conversation = `"conversationId" IN (SELECT "id" FROM "ai_conversations" WHERE ${tenant})`;
const subscription = `"subscriptionId" IN (SELECT "id" FROM "ai_subscriptions" WHERE ${branch})`;
const stock = `"stockId" IN (SELECT "id" FROM "stock" WHERE ${branch} OR ${product})`;
const stockBatch = `"stockBatchId" IN (SELECT "id" FROM "stock_batches" WHERE ${stock})`;
const saleItem = `"saleItemId" IN (SELECT "id" FROM "sale_items" WHERE ${sale} OR ${product})`;
const expense = `"expenseId" IN (SELECT "id" FROM "expenses" WHERE ${branch} OR "createdById" IN (SELECT "id" FROM "users" WHERE ${tenant}) OR "approvedById" IN (SELECT "id" FROM "users" WHERE ${tenant}))`;
const supplier = `"supplierId" IN (SELECT "id" FROM "suppliers" WHERE ${tenant})`;
const invoice = `"invoiceId" IN (SELECT "id" FROM "supplier_invoices" WHERE ${tenant} OR ${branch} OR "supplierId" IN (SELECT "id" FROM "suppliers" WHERE ${tenant}) OR "createdById" IN (SELECT "id" FROM "users" WHERE ${tenant}))`;
const transfer = `"transferId" IN (SELECT "id" FROM "stock_transfers" WHERE "fromBranchId" IN (SELECT "id" FROM "branches" WHERE ${tenant}) OR "toBranchId" IN (SELECT "id" FROM "branches" WHERE ${tenant}) OR "createdById" IN (SELECT "id" FROM "users" WHERE ${tenant}))`;

// Child-first order. Tables with no predicate are intentionally global data
// that has no tenant relationship in the live schema and is cleared entirely.
const cleanup = [
  ['audit_logs', user],
  ['ai_messages', conversation],
  ['ai_payments', subscription],
  ['role_permissions', role],
  ['user_roles', user],
  ['user_permission_overrides', user],
  ['product_categories', `${product} OR ${category}`],
  ['product_pricing_tiers', product],
  ['sale_item_batches', `${saleItem} OR ${stockBatch}`],
  ['refund_items', `${saleItem} OR "refundId" IN (SELECT "id" FROM "refunds" WHERE ${sale})`],
  ['expense_items', expense],
  ['supplier_invoice_items', `${invoice} OR ${product}`],
  ['supplier_payments', `${supplier} OR ${invoice} OR "createdById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['payments', sale],
  ['refunds', sale],
  ['manual_payment_requests', `${branch} OR ${sale} OR "requestedById" IN (SELECT "id" FROM "users" WHERE ${tenant}) OR "approvedById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['sync_events', `${device} OR ${branch} OR "userId" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['print_jobs', branch],
  ['daily_briefs', branch],
  ['branch_cash_settings', branch],
  ['cash_ledger_entries', branch],
  ['cash_reconciliations', `${branch} OR "countedById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['daily_closes', `${branch} OR "closedById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['stock_movements', `${branch} OR ${product}`],
  ['stock_requests', `${branch} OR ${product} OR "requestedById" IN (SELECT "id" FROM "users" WHERE ${tenant}) OR "resolvedById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['stock_transfer_items', `${transfer} OR ${product}`],
  ['stock_transfers', `"fromBranchId" IN (SELECT "id" FROM "branches" WHERE ${tenant}) OR "toBranchId" IN (SELECT "id" FROM "branches" WHERE ${tenant}) OR "createdById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['branch_price_overrides', `${branch} OR ${product}`],
  ['sales', `${branch} OR ${device} OR "userId" IN (SELECT "id" FROM "users" WHERE ${tenant}) OR "customerId" IN (SELECT "id" FROM "customers" WHERE ${tenant})`],
  ['stock_batches', stock],
  ['stock', `${branch} OR ${product}`],
  ['supplier_invoices', `${tenant} OR ${branch} OR "supplierId" IN (SELECT "id" FROM "suppliers" WHERE ${tenant}) OR "createdById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['expenses', `${branch} OR "createdById" IN (SELECT "id" FROM "users" WHERE ${tenant}) OR "approvedById" IN (SELECT "id" FROM "users" WHERE ${tenant})`],
  ['ai_subscriptions', branch],
  ['devices', branch],
  ['customers', tenant],
  ['products', `${tenant} OR "id" IN (SELECT "productId" FROM "sale_items" WHERE ${sale}) OR "id" IN (SELECT "productId" FROM "stock" WHERE ${branch}) OR "id" IN (SELECT "productId" FROM "supplier_invoice_items" WHERE ${invoice})`],
  ['suppliers', tenant],
  ['ai_conversations', tenant],
  ['ai_memories', tenant],
  ['push_tokens', user],
  ['refresh_tokens', user],
  ['user_branches', `${user} OR ${branch}`],
  ['categories', tenant],
  ['roles', tenant],
  ['users', tenant],
  ['branches', tenant],
  ['tenants', `"id" = ${T}`],
];

const globalClear = [
  ['mpesa_transactions', null],
  ['pesapal_transactions', null],
  ['touristtap_transactions', null],
  ['conflict_logs', null],
];

async function countTable(tx, table, predicate) {
  const all = await tx.$queryRawUnsafe(`SELECT count(*)::int AS count FROM "${table}"`);
  const keep = predicate
    ? await tx.$queryRawUnsafe(`SELECT count(*)::int AS count FROM "${table}" WHERE ${predicate}`)
    : [{ count: 0 }];
  return { table, total: Number(all[0].count), keep: Number(keep[0].count), remove: Number(all[0].count) - Number(keep[0].count) };
}

async function main() {
  const execute = process.argv.includes('--execute');
  await prisma.$transaction(async (tx) => {
    const target = await tx.tenant.findUnique({ where: { id: TENANT_ID }, select: { id: true, name: true, slug: true } });
    const admin = await tx.user.findFirst({ where: { tenantId: TENANT_ID, email: 'admin@levisa.com' }, select: { id: true, email: true } });
    if (!target || !admin) throw new Error('Safety check failed: target tenant or admin@levisa.com was not found in the same tenant.');

    const report = [];
    for (const [table, predicate] of [...globalClear, ...cleanup]) report.push(await countTable(tx, table, predicate));
    console.log(JSON.stringify({ mode: execute ? 'execute' : 'dry-run', target, admin, report }, null, 2));
    if (!execute) return;

    // Remove references from non-target branches before deleting unused shared POS clients.
    await tx.$executeRawUnsafe(`UPDATE "branches" SET "posClientId" = NULL WHERE "tenantId" <> ${T}`);
    await tx.$executeRawUnsafe(`DELETE FROM "pos_clients" WHERE "id" NOT IN (SELECT "posClientId" FROM "branches" WHERE "posClientId" IS NOT NULL)`);
    await tx.$executeRawUnsafe(`UPDATE "categories" SET "parentId" = NULL WHERE "tenantId" <> ${T}`);

    const deleted = [];
    for (const [table, predicate] of [...globalClear, ...cleanup]) {
      const sql = predicate ? `DELETE FROM "${table}" WHERE NOT (${predicate})` : `DELETE FROM "${table}"`;
      const result = await tx.$executeRawUnsafe(sql);
      deleted.push({ table, deleted: Number(result) });
    }
    console.log(JSON.stringify({ deleted }, null, 2));
  }, { maxWait: 10000, timeout: 120000 });
}

main().catch(async (error) => {
  console.error(error.message || error);
  process.exitCode = 1;
}).finally(async () => {
  await prisma.$disconnect();
});
