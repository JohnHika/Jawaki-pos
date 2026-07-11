-- CreateTable
CREATE TABLE "daily_closes" (
    "id" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "totalSales" DECIMAL(12,2) NOT NULL,
    "totalTransactions" INTEGER NOT NULL,
    "cashSales" DECIMAL(12,2) NOT NULL,
    "mpesaSales" DECIMAL(12,2) NOT NULL,
    "cardSales" DECIMAL(12,2) NOT NULL,
    "creditSales" DECIMAL(12,2) NOT NULL,
    "outstandingBalance" DECIMAL(12,2) NOT NULL,
    "totalTax" DECIMAL(12,2) NOT NULL,
    "totalDiscount" DECIMAL(12,2) NOT NULL,
    "expectedCash" DECIMAL(12,2) NOT NULL,
    "countedCash" DECIMAL(12,2) NOT NULL,
    "cashDiscrepancy" DECIMAL(12,2) NOT NULL,
    "reconciliationId" TEXT,
    "notes" TEXT,
    "closedById" TEXT NOT NULL,
    "closedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "daily_closes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "daily_closes_branchId_closedAt_idx" ON "daily_closes"("branchId", "closedAt");

-- CreateIndex
CREATE UNIQUE INDEX "daily_closes_branchId_date_key" ON "daily_closes"("branchId", "date");

-- AddForeignKey
ALTER TABLE "daily_closes" ADD CONSTRAINT "daily_closes_branchId_fkey" FOREIGN KEY ("branchId") REFERENCES "branches"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "daily_closes" ADD CONSTRAINT "daily_closes_closedById_fkey" FOREIGN KEY ("closedById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
