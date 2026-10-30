#!/usr/bin/env node
// Prepare one shop's existing Prisma JSON archive for a device-only Counterbase
// restore. This script reads only the local archive directory and never calls
// the retired POS API or database.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');

const ARCHIVE_AAD_PREFIX = 'counterbase-local-archive:v2';
const ARCHIVE_KDF_ITERATIONS = 310000;
const MAX_ARCHIVE_PAYLOAD_BYTES = 45 * 1024 * 1024;
const MAX_ARCHIVE_RECORDS = 250000;

function parseArgs(argv) {
  const result = {};
  for (let index = 2; index < argv.length; index += 1) {
    const key = argv[index];
    if (!key.startsWith('--')) throw new Error(`Unexpected argument: ${key}`);
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`Missing value for ${key}`);
    result[key.slice(2)] = value;
    index += 1;
  }
  return result;
}

function readRows(inputDir, model) {
  const file = path.join(inputDir, `${model}.json`);
  if (!fs.existsSync(file)) return [];
  const value = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!Array.isArray(value)) throw new Error(`${model}.json must contain a JSON array`);
  return value;
}

function clean(value) {
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(clean);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clean(item)]));
  }
  if (typeof value === 'bigint') return value.toString();
  return value;
}

function cleanPayment(row) {
  const {
    id,
    saleId,
    method,
    amount,
    status,
    transactionId,
    paidAt,
    createdAt,
  } = row;
  return { id, saleId, method, amount, status, transactionId, paidAt, createdAt };
}

function requiredId(row, label) {
  if (!row || typeof row.id !== 'string' || !row.id.trim()) {
    throw new Error(`${label} contains a record without an id`);
  }
  return row.id;
}

function selectRows(rows, predicate, label) {
  const selected = rows.filter(predicate);
  selected.forEach((row) => requiredId(row, label));
  return selected;
}

function readSecret(promptText) {
  const input = process.stdin;
  if (!input.isTTY || typeof input.setRawMode !== 'function') {
    throw new Error('Run this command in an interactive terminal so the archive password is not echoed.');
  }
  readline.emitKeypressEvents(input);
  input.setRawMode(true);
  input.resume();
  process.stdout.write(promptText);
  return new Promise((resolve, reject) => {
    const characters = [];
    const cleanup = () => {
      input.removeListener('keypress', onKeypress);
      input.setRawMode(false);
      process.stdout.write('\n');
    };
    const onKeypress = (character, key = {}) => {
      if (key.ctrl && key.name === 'c') {
        cleanup();
        reject(new Error('Archive preparation cancelled.'));
        return;
      }
      if (key.name === 'return' || key.name === 'enter') {
        cleanup();
        resolve(characters.join(''));
        return;
      }
      if (key.name === 'backspace') {
        if (characters.length > 0) {
          characters.pop();
          process.stdout.write('\b \b');
        }
        return;
      }
      if (character && !key.ctrl && !key.meta && character !== '\u0000') {
        characters.push(character);
        process.stdout.write('*');
      }
    };
    input.on('keypress', onKeypress);
  });
}

async function readArchivePassword() {
  const password = await readSecret('Choose archive password (12+ characters): ');
  if ([...password].length < 12) throw new Error('Use an archive password with at least 12 characters.');
  const confirmation = await readSecret('Confirm archive password: ');
  if (password !== confirmation) throw new Error('The archive passwords did not match.');
  return password;
}

async function main() {
  const args = parseArgs(process.argv);
  const inputDir = path.resolve(args.input || path.join(__dirname, '..', 'pos-archive-2026-10-27'));
  const selector = (args.tenant || '').trim().toLowerCase();
  const outputFile = args.output ? path.resolve(args.output) : '';
  if (!selector) throw new Error('Pass --tenant with the exact shop id, slug, or name from the archive.');
  if (!outputFile) throw new Error('Pass --output with a path outside the source archive.');
  const relativeOutput = path.relative(inputDir, outputFile);
  if (relativeOutput === '' || (!relativeOutput.startsWith(`..${path.sep}`) && relativeOutput !== '..' && !path.isAbsolute(relativeOutput))) {
    throw new Error('Choose an output path outside the source archive directory.');
  }

  const tenants = readRows(inputDir, 'Tenant');
  const matches = tenants.filter((tenant) => [tenant.id, tenant.slug, tenant.name]
    .some((value) => typeof value === 'string' && value.trim().toLowerCase() === selector));
  if (matches.length !== 1) {
    throw new Error(matches.length === 0
      ? 'No shop matched that exact id, slug, or name.'
      : 'More than one shop matched. Use its exact id.');
  }

  const tenant = matches[0];
  const tenantId = requiredId(tenant, 'Tenant.json');
  const branches = selectRows(readRows(inputDir, 'Branch'), (row) => row.tenantId === tenantId, 'Branch.json');
  const branchIds = new Set(branches.map((row) => row.id));
  if (branches.length === 0) throw new Error('The selected shop has no branches in the archive.');

  const users = selectRows(readRows(inputDir, 'User'), (row) => row.tenantId === tenantId,
    'User.json').map(({ id, firstName, lastName, role, isActive }) => ({
    id, firstName, lastName, role, isActive,
  }));
  const userIds = new Set(users.map((row) => row.id));
  const categories = selectRows(readRows(inputDir, 'Category'), (row) => row.tenantId === tenantId,
    'Category.json').map(({ id, parentId, name, slug, description, sortOrder, isActive, createdAt, updatedAt }) => ({
    id, parentId, name, slug, description, sortOrder, isActive, createdAt, updatedAt,
  }));
  const products = selectRows(readRows(inputDir, 'Product'), (row) => row.tenantId === tenantId,
    'Product.json').map(({ id, sku, name, description, basePrice, costPrice, minPrice, taxRate, unit,
    minStock, trackInventory, allowFractions, isActive, isFavorite, sortOrder, metadata, createdAt, updatedAt }) => ({
    id, sku, name, description, basePrice, costPrice, minPrice, taxRate, unit, minStock,
    trackInventory, allowFractions, isActive, isFavorite, sortOrder, metadata, createdAt, updatedAt,
  }));
  const productIds = new Set(products.map((row) => row.id));
  const productCategories = selectRows(readRows(inputDir, 'ProductCategory'),
    (row) => productIds.has(row.productId), 'ProductCategory.json');
  const pricingTiers = selectRows(readRows(inputDir, 'ProductPricingTier'),
    (row) => productIds.has(row.productId), 'ProductPricingTier.json');
  const customers = selectRows(readRows(inputDir, 'Customer'), (row) => row.tenantId === tenantId,
    'Customer.json').map(({ id, name, phone, email, address, loyaltyPoints, creditLimit, idNumber,
    guarantorName, guarantorPhone, isActive, createdAt, updatedAt }) => ({
    id, name, phone, email, address, loyaltyPoints, creditLimit, idNumber, guarantorName,
    guarantorPhone, isActive, createdAt, updatedAt,
  }));
  const customerIds = new Set(customers.map((row) => row.id));
  const suppliers = selectRows(readRows(inputDir, 'Supplier'),
    (row) => row.tenantId === tenantId, 'Supplier.json').map(({
    id, name, contactName, phone, email, address, isActive, createdAt, updatedAt,
  }) => ({ id, name, contactName, phone, email, address, isActive, createdAt, updatedAt }));
  const supplierIds = new Set(suppliers.map((row) => row.id));
  const supplierInvoices = selectRows(readRows(inputDir, 'SupplierInvoice'),
    (row) => row.tenantId === tenantId && branchIds.has(row.branchId) && supplierIds.has(row.supplierId),
    'SupplierInvoice.json').map(({
    id, tenantId: invoiceTenantId, branchId, supplierId, invoiceNumber,
    subtotal, paidAmount, totalAmount, dueAmount, dueDate, status, fundingSource,
    createdAt, updatedAt,
  }) => ({
    id, tenantId: invoiceTenantId, branchId, supplierId, invoiceNumber,
    subtotal, paidAmount, totalAmount, dueAmount, dueDate, status, fundingSource,
    createdAt, updatedAt,
  }));
  const supplierInvoiceIds = new Set(supplierInvoices.map((row) => row.id));
  const supplierPayments = selectRows(readRows(inputDir, 'SupplierPayment'),
    (row) => supplierIds.has(row.supplierId) &&
      (row.invoiceId == null || supplierInvoiceIds.has(row.invoiceId)),
    'SupplierPayment.json').map(({
    id, supplierId, invoiceId, amount, notes, fundingSource, paidAt, createdAt,
  }) => ({ id, supplierId, invoiceId, amount, notes, fundingSource, paidAt, createdAt }));
  const sales = selectRows(readRows(inputDir, 'Sale'), (row) => branchIds.has(row.branchId), 'Sale.json');
  const saleIds = new Set(sales.map((row) => row.id));
  const saleItems = selectRows(readRows(inputDir, 'SaleItem'), (row) => saleIds.has(row.saleId), 'SaleItem.json');
  const saleItemIds = new Set(saleItems.map((row) => row.id));
  const stock = selectRows(readRows(inputDir, 'Stock'),
    (row) => branchIds.has(row.branchId) && productIds.has(row.productId), 'Stock.json');
  const stockIds = new Set(stock.map((row) => row.id));
  const stockBatches = selectRows(readRows(inputDir, 'StockBatch'), (row) => stockIds.has(row.stockId), 'StockBatch.json');
  const stockMovements = selectRows(readRows(inputDir, 'StockMovement'),
    (row) => branchIds.has(row.branchId) && productIds.has(row.productId), 'StockMovement.json');
  const payments = selectRows(readRows(inputDir, 'Payment'), (row) => saleIds.has(row.saleId), 'Payment.json').map(cleanPayment);
  const receivables = selectRows(readRows(inputDir, 'RetailReceivable'),
    (row) => row.tenantId === tenantId && branchIds.has(row.branchId), 'RetailReceivable.json');
  const receivableIds = new Set(receivables.map((row) => row.id));
  const receivablePayments = selectRows(readRows(inputDir, 'RetailReceivablePayment'),
    (row) => receivableIds.has(row.receivableId), 'RetailReceivablePayment.json').map(({
    id, receivableId, branchId, amount, method, reference, notes, paidAt, createdAt,
  }) => ({ id, receivableId, branchId, amount, method, reference, notes, paidAt, createdAt }));
  const stockCounts = selectRows(readRows(inputDir, 'StockCount'),
    (row) => row.tenantId === tenantId && branchIds.has(row.branchId), 'StockCount.json');
  const stockCountIds = new Set(stockCounts.map((row) => row.id));

  const rows = {
    tenant: { id: tenantId, name: tenant.name, slug: tenant.slug },
    branches,
    users,
    userBranches: selectRows(readRows(inputDir, 'UserBranch'),
      (row) => userIds.has(row.userId) && branchIds.has(row.branchId), 'UserBranch.json'),
    categories,
    products,
    productCategories,
    pricingTiers,
    customers,
    suppliers,
    supplierInvoices,
    supplierInvoiceItems: selectRows(readRows(inputDir, 'SupplierInvoiceItem'),
      (row) => supplierInvoiceIds.has(row.invoiceId), 'SupplierInvoiceItem.json').map(({
      id, invoiceId, productId, productName, quantity, unit, unitCost, lineTotal, createdAt,
    }) => ({ id, invoiceId, productId, productName, quantity, unit, unitCost, lineTotal, createdAt })),
    supplierPayments,
    sales,
    saleItems,
    saleItemBatches: selectRows(readRows(inputDir, 'SaleItemBatch'),
      (row) => saleItemIds.has(row.saleItemId), 'SaleItemBatch.json'),
    payments,
    stock,
    stockBatches,
    stockMovements,
    stockCounts,
    stockCountItems: selectRows(readRows(inputDir, 'StockCountItem'),
      (row) => stockCountIds.has(row.countId), 'StockCountItem.json'),
    retailReceivables: receivables,
    retailReceivablePayments: receivablePayments,
    cashLedgerEntries: selectRows(readRows(inputDir, 'CashLedgerEntry'),
      (row) => branchIds.has(row.branchId), 'CashLedgerEntry.json'),
    cashReconciliations: selectRows(readRows(inputDir, 'CashReconciliation'),
      (row) => branchIds.has(row.branchId), 'CashReconciliation.json'),
    dailyCloses: selectRows(readRows(inputDir, 'DailyClose'),
      (row) => branchIds.has(row.branchId), 'DailyClose.json'),
  };
  const recordCount = Object.values(rows)
    .filter(Array.isArray)
    .reduce((total, values) => total + values.length, 0);
  if (recordCount > MAX_ARCHIVE_RECORDS) {
    throw new Error('This shop archive has too many records for the current restore flow (250,000 maximum).');
  }
  // Keep only local business information. Login secrets, session tokens, API
  // keys, AI conversations, provider payloads, payment-account credentials,
  // and statement-access tokens are intentionally excluded.
  const payload = JSON.stringify(clean(rows));
  if (Buffer.byteLength(payload, 'utf8') > MAX_ARCHIVE_PAYLOAD_BYTES) {
    throw new Error('This shop archive is too large for the current restore flow (45 MB maximum).');
  }
  const password = await readArchivePassword();
  const salt = crypto.randomBytes(16);
  const nonce = crypto.randomBytes(12);
  const createdAt = new Date().toISOString();
  const aad = Buffer.from(`${ARCHIVE_AAD_PREFIX}:${createdAt}:${salt.toString('base64')}:${nonce.toString('base64')}:${ARCHIVE_KDF_ITERATIONS}`, 'utf8');
  const key = crypto.pbkdf2Sync(password, salt, ARCHIVE_KDF_ITERATIONS, 32, 'sha256');
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce, { authTagLength: 16 });
  cipher.setAAD(aad);
  const ciphertext = Buffer.concat([cipher.update(payload, 'utf8'), cipher.final()]);
  const envelope = {
    format: 'counterbase-local-archive',
    version: 2,
    createdAt,
    encryption: 'AES-256-GCM',
    kdf: 'PBKDF2-HMAC-SHA256',
    iterations: ARCHIVE_KDF_ITERATIONS,
    salt: salt.toString('base64'),
    nonce: nonce.toString('base64'),
    ciphertext: ciphertext.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
  };

  fs.mkdirSync(path.dirname(outputFile), { recursive: true });
  fs.writeFileSync(outputFile, `${JSON.stringify(envelope)}\n`, { flag: 'wx', mode: 0o600 });
  const summary = Object.fromEntries(Object.entries(rows)
    .filter(([, value]) => Array.isArray(value))
    .map(([key, value]) => [key, value.length]));
  console.log(`Prepared a local archive for ${tenant.name || 'selected shop'}.`);
  console.log(`Included business records: ${Object.entries(summary).map(([name, count]) => `${name}=${count}`).join(', ')}`);
  console.log('The archive is password-encrypted. Login secrets and payment-provider payloads were excluded.');
  console.log(`Output: ${outputFile}`);
}

main().catch((error) => {
  console.error(`Archive preparation failed: ${error.message}`);
  process.exitCode = 1;
});
