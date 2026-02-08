# Batch & Expiry Tracking - Migration Guide

## Overview

This guide will help you migrate your existing POS system to include batch and expiry tracking for medicine inventory.

## Prerequisites

- PostgreSQL database access
- Node.js and npm installed
- Prisma CLI installed
- Backup of current database (REQUIRED)

## Migration Steps

### Step 1: Backup Current Database

**IMPORTANT**: Always backup before migrating!

```bash
# Using pg_dump
pg_dump -U postgres -d pos_system > backup_$(date +%Y%m%d_%H%M%S).sql

# Or using Docker if database is in container
docker exec -t postgres_container pg_dump -U postgres pos_system > backup_$(date +%Y%m%d_%H%M%S).sql
```

### Step 2: Update Prisma Schema

The schema has already been updated with:
- `StockBatch` model
- `SaleItemBatch` model
- Updated `StockMovement` with batch fields
- New enum values for `StockMovementType`

Review the changes in `backend/prisma/schema.prisma`.

### Step 3: Generate Migration

```bash
cd backend

# Generate and apply migration
npx prisma migrate dev --name add_batch_expiry_tracking

# This will:
# 1. Create new tables: stock_batches, sale_item_batches
# 2. Add new columns to stock_movements
# 3. Add new enum values to StockMovementType
```

### Step 4: Regenerate Prisma Client

```bash
npx prisma generate
```

### Step 5: Migrate Existing Stock to Batches (Optional)

If you have existing stock without batches, you can create default batches:

```bash
# Run this Node.js script
node scripts/migrate-existing-stock-to-batches.js
```

Create this script at `backend/scripts/migrate-existing-stock-to-batches.js`:

```javascript
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function migrateExistingStock() {
  console.log('Starting migration of existing stock to batches...');

  // Get all stock records
  const stockRecords = await prisma.stock.findMany({
    where: {
      quantity: {
        gt: 0
      }
    },
    include: {
      product: true,
      branch: true
    }
  });

  console.log(`Found ${stockRecords.length} stock records to migrate`);

  for (const stock of stockRecords) {
    // Check if batch already exists
    const existingBatch = await prisma.stockBatch.findFirst({
      where: { stockId: stock.id }
    });

    if (existingBatch) {
      console.log(`Batch already exists for stock ${stock.id}, skipping...`);
      continue;
    }

    // Create default batch
    await prisma.stockBatch.create({
      data: {
        stockId: stock.id,
        batchNumber: `MIGRATED-${stock.id.slice(0, 8)}`,
        quantity: stock.quantity,
        reservedQty: stock.reservedQty,
        expiryDate: null, // No expiry for migrated stock
        manufactureDate: null,
        costPrice: null,
        supplierRef: 'MIGRATION',
        notes: 'Migrated from existing stock',
        isBlocked: false
      }
    });

    console.log(`Created batch for ${stock.product.name} at ${stock.branch.name}`);
  }

  console.log('Migration complete!');
}

migrateExistingStock()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
```

### Step 6: Install Dependencies

```bash
cd backend
npm install
```

### Step 7: Restart Backend Server

```bash
# Development
npm run start:dev

# Production
npm run build
npm run start:prod
```

### Step 8: Verify Migration

#### Check Tables
```sql
-- Verify tables were created
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('stock_batches', 'sale_item_batches');

-- Check stock_batches structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stock_batches';
```

#### Test API Endpoints
```bash
# 1. Receive a batch
curl -X POST http://localhost:3000/v1/inventory/batches/receive \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "branchId": "branch-id",
    "productId": "product-id",
    "batches": [{
      "batchNumber": "TEST-001",
      "quantity": 10,
      "expiryDate": "2026-12-31"
    }]
  }'

# 2. Get stock with batches
curl http://localhost:3000/v1/inventory/batches/{branchId}/{productId} \
  -H "Authorization: Bearer YOUR_TOKEN"

# 3. Get expiry dashboard
curl "http://localhost:3000/v1/inventory/expiry-dashboard?branchId=xxx" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Rollback Plan

If you need to rollback the migration:

### Option 1: Restore from Backup

```bash
# Restore database from backup
psql -U postgres -d pos_system < backup_TIMESTAMP.sql
```

### Option 2: Revert Migration

```bash
cd backend

# Revert the last migration
npx prisma migrate resolve --rolled-back add_batch_expiry_tracking

# Manually clean up
psql -U postgres -d pos_system -c "
  DROP TABLE IF EXISTS sale_item_batches CASCADE;
  DROP TABLE IF EXISTS stock_batches CASCADE;
"
```

## Data Migration Scenarios

### Scenario 1: Fresh Installation
- No existing stock → Directly use batch receiving
- All new stock will have batch tracking

### Scenario 2: Existing Stock (Non-Medicine)
- Run migration script to create default batches
- Set `expiryDate` to NULL for non-perishable items
- Batch tracking optional for these items

### Scenario 3: Existing Medicine Stock
- **IMPORTANT**: Determine actual batch info from supplier documents
- Manually enter correct batch numbers and expiry dates
- Block any batches you cannot verify expiry for

## Testing Checklist

After migration, test these scenarios:

- [ ] Receive new batch with expiry date
- [ ] Receive batch already expired (should auto-block)
- [ ] View stock with batch details
- [ ] Make sale with batch allocation (FEFO)
- [ ] Attempt sale with only expired batches (should fail)
- [ ] View expiry dashboard
- [ ] Filter expiry dashboard by zones
- [ ] Update batch quantity
- [ ] Block/unblock batch manually
- [ ] Run auto-block expired batches
- [ ] View sale history with batch info

## Common Issues & Solutions

### Issue 1: Migration Fails - Foreign Key Constraint
**Solution**: Ensure all existing `stock` records are valid before migration.

```sql
-- Find orphaned stock records
SELECT s.id, s.branchId, s.productId 
FROM stock s 
LEFT JOIN branches b ON s.branchId = b.id 
LEFT JOIN products p ON s.productId = p.id 
WHERE b.id IS NULL OR p.id IS NULL;

-- Clean up if needed
DELETE FROM stock WHERE branchId NOT IN (SELECT id FROM branches);
```

### Issue 2: Prisma Client Out of Sync
**Solution**: Regenerate Prisma client.

```bash
npx prisma generate
```

### Issue 3: TypeScript Errors After Migration
**Solution**: Restart TypeScript server and rebuild.

```bash
npm run build
```

### Issue 4: Sales Failing Due to Missing Batches
**Solution**: Ensure all products have at least one non-blocked batch.

```sql
-- Find products without batches
SELECT p.id, p.name, p.sku
FROM products p
INNER JOIN stock s ON p.id = s.productId
LEFT JOIN stock_batches sb ON s.id = sb.stockId
WHERE s.quantity > 0 AND sb.id IS NULL;
```

## Performance Considerations

### Index Optimization
The migration creates these indexes automatically:
- `stock_batches.expiryDate` - For expiry queries
- `stock_batches.stockId, expiryDate` - For FEFO allocation
- `stock_movements.batchId` - For batch traceability

### Query Performance
- Batch allocation adds 1-2 extra queries per sale
- Use pagination on expiry dashboard for large datasets
- Consider archiving old stock movements

## Monitoring

After migration, monitor:

1. **Sales Performance**: Ensure FEFO logic doesn't slow down POS
2. **Database Size**: Batch tables will grow over time
3. **Expired Batches**: Run auto-block daily
4. **Error Logs**: Watch for batch allocation errors

## Maintenance Tasks

### Daily
```bash
# Auto-block expired batches
curl -X POST http://localhost:3000/v1/inventory/batches/block-expired \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

### Weekly
- Review expiry dashboard
- Plan clearance sales for expiring items
- Archive old stock movements (optional)

### Monthly
- Audit batch records vs physical inventory
- Review blocked batches
- Clean up obsolete batches

## Support

If you encounter issues during migration:

1. Check logs: `backend/logs/`
2. Review Prisma errors
3. Verify database connection
4. Ensure all ENV variables are set
5. Contact development team

## Next Steps

After successful migration:

1. [ ] Train staff on batch receiving workflow
2. [ ] Setup daily cron job for auto-blocking
3. [ ] Configure expiry notification alerts
4. [ ] Update mobile app to support batch scanning
5. [ ] Create standard operating procedures (SOPs)

---

**Migration Completed**: _____________  
**Migrated By**: _____________  
**Issues Encountered**: _____________  
**Resolution Time**: _____________  
