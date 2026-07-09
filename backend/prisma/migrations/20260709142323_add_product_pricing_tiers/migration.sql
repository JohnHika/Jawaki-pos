-- The old secondaryUnit*/tertiaryUnit* columns are deliberately NOT dropped
-- in this migration. They stay in place until a follow-up migration runs,
-- after a one-off backfill script has copied their data into
-- product_pricing_tiers -- dropping them here would destroy that data
-- before it could be migrated.

-- CreateTable
CREATE TABLE "product_pricing_tiers" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "quantityPerUnit" DECIMAL(10,3) NOT NULL,
    "price" DECIMAL(10,2) NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "product_pricing_tiers_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "product_pricing_tiers_productId_idx" ON "product_pricing_tiers"("productId");

-- AddForeignKey
ALTER TABLE "product_pricing_tiers" ADD CONSTRAINT "product_pricing_tiers_productId_fkey" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;
