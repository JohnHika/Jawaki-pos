-- AlterTable
ALTER TABLE "products" ADD COLUMN     "minPrice" DECIMAL(10,2);

-- AlterTable
ALTER TABLE "customers" ADD COLUMN     "creditLimit" DECIMAL(12,2),
ADD COLUMN     "guarantorName" TEXT,
ADD COLUMN     "guarantorPhone" TEXT,
ADD COLUMN     "idNumber" TEXT;

-- CreateTable
CREATE TABLE "accountability_alerts" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT,
    "type" TEXT NOT NULL,
    "severity" TEXT NOT NULL DEFAULT 'MEDIUM',
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "actorUserId" TEXT,
    "entityType" TEXT,
    "entityId" TEXT,
    "data" JSONB NOT NULL DEFAULT '{}',
    "acknowledgedAt" TIMESTAMP(3),
    "acknowledgedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "accountability_alerts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_counts" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "title" TEXT,
    "status" TEXT NOT NULL DEFAULT 'IN_PROGRESS',
    "blind" BOOLEAN NOT NULL DEFAULT true,
    "notes" TEXT,
    "createdById" TEXT NOT NULL,
    "submittedById" TEXT,
    "submittedAt" TIMESTAMP(3),
    "approvedById" TEXT,
    "approvedAt" TIMESTAMP(3),
    "totalVarianceValue" DECIMAL(14,2),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "stock_counts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_count_items" (
    "id" TEXT NOT NULL,
    "countId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "productName" TEXT NOT NULL,
    "sku" TEXT,
    "expectedQty" DECIMAL(10,3) NOT NULL,
    "countedQty" DECIMAL(10,3),
    "unitCost" DECIMAL(10,2) NOT NULL DEFAULT 0,
    "reason" TEXT,
    "countedById" TEXT,
    "countedAt" TIMESTAMP(3),

    CONSTRAINT "stock_count_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "import_shipments" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "reference" TEXT,
    "title" TEXT NOT NULL,
    "origin" TEXT,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "fxRate" DECIMAL(14,4) NOT NULL DEFAULT 1,
    "allocationBasis" TEXT NOT NULL DEFAULT 'VALUE',
    "status" TEXT NOT NULL DEFAULT 'PLANNED',
    "expectedArrival" TIMESTAMP(3),
    "arrivedAt" TIMESTAMP(3),
    "receivedAt" TIMESTAMP(3),
    "receivedById" TEXT,
    "notes" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "import_shipments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "import_costs" (
    "id" TEXT NOT NULL,
    "shipmentId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "label" TEXT,
    "amount" DECIMAL(14,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'KES',
    "fxRate" DECIMAL(14,4) NOT NULL DEFAULT 1,
    "amountKes" DECIMAL(14,2) NOT NULL,
    "paidAt" TIMESTAMP(3),
    "reference" TEXT,
    "receiptUrl" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "import_costs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "import_participants" (
    "id" TEXT NOT NULL,
    "shipmentId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "isSelf" BOOLEAN NOT NULL DEFAULT false,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "import_participants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "import_items" (
    "id" TEXT NOT NULL,
    "shipmentId" TEXT NOT NULL,
    "participantId" TEXT,
    "productId" TEXT,
    "description" TEXT NOT NULL,
    "quantity" DECIMAL(12,3) NOT NULL,
    "unit" TEXT NOT NULL DEFAULT 'piece',
    "unitCost" DECIMAL(14,4) NOT NULL,
    "cbm" DECIMAL(12,4),
    "weightKg" DECIMAL(12,3),
    "receivedQty" DECIMAL(12,3),
    "goodsValueKes" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "allocatedCostKes" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "landedUnitCostKes" DECIMAL(14,4) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "import_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "import_payments" (
    "id" TEXT NOT NULL,
    "shipmentId" TEXT NOT NULL,
    "participantId" TEXT NOT NULL,
    "amountKes" DECIMAL(14,2) NOT NULL,
    "method" TEXT,
    "reference" TEXT,
    "notes" TEXT,
    "paidAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "recordedById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "import_payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "news_items" (
    "id" TEXT NOT NULL,
    "sourceKey" TEXT NOT NULL,
    "sourceName" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "summary" TEXT,
    "url" TEXT NOT NULL,
    "imageUrl" TEXT,
    "publishedAt" TIMESTAMP(3) NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'GENERAL',
    "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "impact" TEXT NOT NULL DEFAULT 'LOW',
    "fetchedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "news_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "news_sources" (
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "lastFetchedAt" TIMESTAMP(3),
    "lastError" TEXT,
    "consecutiveFailures" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "news_sources_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "exchange_rate_snapshots" (
    "id" TEXT NOT NULL,
    "base" TEXT NOT NULL DEFAULT 'USD',
    "rates" JSONB NOT NULL,
    "providerUpdatedAt" TIMESTAMP(3),
    "fetchedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "exchange_rate_snapshots_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "accountability_alerts_tenantId_createdAt_idx" ON "accountability_alerts"("tenantId", "createdAt");

-- CreateIndex
CREATE INDEX "accountability_alerts_tenantId_acknowledgedAt_idx" ON "accountability_alerts"("tenantId", "acknowledgedAt");

-- CreateIndex
CREATE INDEX "accountability_alerts_tenantId_branchId_createdAt_idx" ON "accountability_alerts"("tenantId", "branchId", "createdAt");

-- CreateIndex
CREATE INDEX "stock_counts_tenantId_branchId_status_idx" ON "stock_counts"("tenantId", "branchId", "status");

-- CreateIndex
CREATE INDEX "stock_counts_tenantId_createdAt_idx" ON "stock_counts"("tenantId", "createdAt");

-- CreateIndex
CREATE INDEX "stock_count_items_countId_idx" ON "stock_count_items"("countId");

-- CreateIndex
CREATE UNIQUE INDEX "stock_count_items_countId_productId_key" ON "stock_count_items"("countId", "productId");

-- CreateIndex
CREATE INDEX "import_shipments_tenantId_status_idx" ON "import_shipments"("tenantId", "status");

-- CreateIndex
CREATE INDEX "import_shipments_tenantId_createdAt_idx" ON "import_shipments"("tenantId", "createdAt");

-- CreateIndex
CREATE INDEX "import_costs_shipmentId_idx" ON "import_costs"("shipmentId");

-- CreateIndex
CREATE INDEX "import_participants_shipmentId_idx" ON "import_participants"("shipmentId");

-- CreateIndex
CREATE INDEX "import_items_shipmentId_idx" ON "import_items"("shipmentId");

-- CreateIndex
CREATE INDEX "import_items_participantId_idx" ON "import_items"("participantId");

-- CreateIndex
CREATE INDEX "import_payments_shipmentId_idx" ON "import_payments"("shipmentId");

-- CreateIndex
CREATE INDEX "import_payments_participantId_idx" ON "import_payments"("participantId");

-- CreateIndex
CREATE UNIQUE INDEX "news_items_url_key" ON "news_items"("url");

-- CreateIndex
CREATE INDEX "news_items_publishedAt_idx" ON "news_items"("publishedAt");

-- CreateIndex
CREATE INDEX "news_items_category_publishedAt_idx" ON "news_items"("category", "publishedAt");

-- CreateIndex
CREATE INDEX "news_items_impact_publishedAt_idx" ON "news_items"("impact", "publishedAt");

-- CreateIndex
CREATE INDEX "exchange_rate_snapshots_fetchedAt_idx" ON "exchange_rate_snapshots"("fetchedAt");

-- AddForeignKey
ALTER TABLE "stock_count_items" ADD CONSTRAINT "stock_count_items_countId_fkey" FOREIGN KEY ("countId") REFERENCES "stock_counts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "import_costs" ADD CONSTRAINT "import_costs_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "import_shipments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "import_participants" ADD CONSTRAINT "import_participants_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "import_shipments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "import_items" ADD CONSTRAINT "import_items_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "import_shipments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "import_items" ADD CONSTRAINT "import_items_participantId_fkey" FOREIGN KEY ("participantId") REFERENCES "import_participants"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "import_payments" ADD CONSTRAINT "import_payments_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "import_shipments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "import_payments" ADD CONSTRAINT "import_payments_participantId_fkey" FOREIGN KEY ("participantId") REFERENCES "import_participants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
