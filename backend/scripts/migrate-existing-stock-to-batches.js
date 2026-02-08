const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * Migration Script: Convert Existing Stock to Batches
 * 
 * This script creates default batches for existing stock records
 * that don't have batch tracking yet.
 * 
 * Run after applying Prisma migration:
 * node scripts/migrate-existing-stock-to-batches.js
 */

async function migrateExistingStock() {
  console.log('🚀 Starting migration of existing stock to batches...\n');

  try {
    // Get all stock records with quantity > 0
    const stockRecords = await prisma.stock.findMany({
      where: {
        quantity: {
          gt: 0,
        },
      },
      include: {
        product: {
          select: {
            id: true,
            name: true,
            sku: true,
          },
        },
        branch: {
          select: {
            id: true,
            name: true,
            code: true,
          },
        },
        batches: true, // Check if batches already exist
      },
    });

    console.log(`📦 Found ${stockRecords.length} stock records to process\n`);

    let created = 0;
    let skipped = 0;
    let errors = 0;

    for (const stock of stockRecords) {
      // Skip if batches already exist
      if (stock.batches.length > 0) {
        console.log(
          `⏭️  Skipping ${stock.product.name} at ${stock.branch.name} - batches already exist`,
        );
        skipped++;
        continue;
      }

      try {
        // Create default batch
        const batch = await prisma.stockBatch.create({
          data: {
            stockId: stock.id,
            batchNumber: `MIGRATED-${Date.now()}-${stock.id.slice(0, 8).toUpperCase()}`,
            quantity: stock.quantity,
            reservedQty: stock.reservedQty || 0,
            expiryDate: null, // No expiry date for migrated stock
            manufactureDate: null,
            costPrice: null,
            supplierRef: 'MIGRATION',
            notes: `Auto-created batch during migration from legacy stock record. Original quantity: ${stock.quantity}`,
            isBlocked: false,
          },
        });

        console.log(
          `✅ Created batch ${batch.batchNumber} for ${stock.product.name} (${stock.product.sku}) at ${stock.branch.name} - Qty: ${stock.quantity}`,
        );
        created++;
      } catch (error) {
        console.error(
          `❌ Error creating batch for ${stock.product.name} at ${stock.branch.name}:`,
          error.message,
        );
        errors++;
      }
    }

    console.log('\n' + '='.repeat(60));
    console.log('📊 Migration Summary:');
    console.log('='.repeat(60));
    console.log(`✅ Batches Created: ${created}`);
    console.log(`⏭️  Skipped (already had batches): ${skipped}`);
    console.log(`❌ Errors: ${errors}`);
    console.log(`📦 Total Processed: ${stockRecords.length}`);
    console.log('='.repeat(60) + '\n');

    if (created > 0) {
      console.log('⚠️  IMPORTANT NEXT STEPS:');
      console.log('1. Review migrated batches in the system');
      console.log('2. Update batch numbers and expiry dates for medicines');
      console.log('3. Block any batches you cannot verify');
      console.log('4. Train staff on new batch receiving workflow\n');
    }

    console.log('✨ Migration completed successfully!\n');
  } catch (error) {
    console.error('💥 Fatal error during migration:', error);
    throw error;
  }
}

// Run migration
migrateExistingStock()
  .catch((error) => {
    console.error('Migration failed:', error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
