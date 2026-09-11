-- CreateEnum
CREATE TYPE "ReceivableStatus" AS ENUM ('OPEN', 'PARTIAL', 'PAID', 'WRITTEN_OFF');

-- CreateEnum
CREATE TYPE "ReceivablePaymentMethod" AS ENUM ('CASH', 'MPESA', 'CARD');

-- AlterEnum
ALTER TYPE "CashEntryType" ADD VALUE 'RECEIVABLE_COLLECTION_IN';

-- CreateTable
CREATE TABLE "retail_receivables" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "saleId" TEXT NOT NULL,
    "customerId" TEXT,
    "originalAmount" DECIMAL(12,2) NOT NULL,
    "outstandingAmount" DECIMAL(12,2) NOT NULL,
    "dueDate" TIMESTAMP(3),
    "status" "ReceivableStatus" NOT NULL DEFAULT 'OPEN',
    "offlineId" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "retail_receivables_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "retail_receivable_payments" (
    "id" TEXT NOT NULL,
    "receivableId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "method" "ReceivablePaymentMethod" NOT NULL,
    "reference" TEXT,
    "notes" TEXT,
    "offlineId" TEXT,
    "createdById" TEXT NOT NULL,
    "paidAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "retail_receivable_payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "peer_debtors" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "contactName" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "address" TEXT,
    "notes" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "peer_debtors_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "peer_receivables" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "debtorId" TEXT NOT NULL,
    "reference" TEXT,
    "description" TEXT NOT NULL,
    "originalAmount" DECIMAL(12,2) NOT NULL,
    "outstandingAmount" DECIMAL(12,2) NOT NULL,
    "dueDate" TIMESTAMP(3),
    "status" "ReceivableStatus" NOT NULL DEFAULT 'OPEN',
    "offlineId" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "peer_receivables_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "peer_receivable_payments" (
    "id" TEXT NOT NULL,
    "receivableId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "method" "ReceivablePaymentMethod" NOT NULL,
    "reference" TEXT,
    "notes" TEXT,
    "offlineId" TEXT,
    "createdById" TEXT NOT NULL,
    "paidAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "peer_receivable_payments_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "retail_receivables_saleId_key" ON "retail_receivables"("saleId");
CREATE UNIQUE INDEX "retail_receivables_offlineId_key" ON "retail_receivables"("offlineId");
CREATE INDEX "retail_receivables_tenantId_branchId_status_dueDate_idx" ON "retail_receivables"("tenantId", "branchId", "status", "dueDate");
CREATE INDEX "retail_receivables_tenantId_customerId_idx" ON "retail_receivables"("tenantId", "customerId");

CREATE UNIQUE INDEX "retail_receivable_payments_offlineId_key" ON "retail_receivable_payments"("offlineId");
CREATE INDEX "retail_receivable_payments_tenantId_branchId_paidAt_idx" ON "retail_receivable_payments"("tenantId", "branchId", "paidAt");
CREATE INDEX "retail_receivable_payments_receivableId_paidAt_idx" ON "retail_receivable_payments"("receivableId", "paidAt");

CREATE UNIQUE INDEX "peer_debtors_tenantId_name_key" ON "peer_debtors"("tenantId", "name");
CREATE INDEX "peer_debtors_tenantId_isActive_idx" ON "peer_debtors"("tenantId", "isActive");

CREATE UNIQUE INDEX "peer_receivables_offlineId_key" ON "peer_receivables"("offlineId");
CREATE INDEX "peer_receivables_tenantId_branchId_status_dueDate_idx" ON "peer_receivables"("tenantId", "branchId", "status", "dueDate");
CREATE INDEX "peer_receivables_tenantId_debtorId_idx" ON "peer_receivables"("tenantId", "debtorId");

CREATE UNIQUE INDEX "peer_receivable_payments_offlineId_key" ON "peer_receivable_payments"("offlineId");
CREATE INDEX "peer_receivable_payments_tenantId_branchId_paidAt_idx" ON "peer_receivable_payments"("tenantId", "branchId", "paidAt");
CREATE INDEX "peer_receivable_payments_receivableId_paidAt_idx" ON "peer_receivable_payments"("receivableId", "paidAt");

-- AddForeignKey
ALTER TABLE "retail_receivables" ADD CONSTRAINT "retail_receivables_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "retail_receivables" ADD CONSTRAINT "retail_receivables_branchId_fkey" FOREIGN KEY ("branchId") REFERENCES "branches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "retail_receivables" ADD CONSTRAINT "retail_receivables_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "sales"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "retail_receivables" ADD CONSTRAINT "retail_receivables_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "retail_receivables" ADD CONSTRAINT "retail_receivables_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "retail_receivable_payments" ADD CONSTRAINT "retail_receivable_payments_receivableId_fkey" FOREIGN KEY ("receivableId") REFERENCES "retail_receivables"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "retail_receivable_payments" ADD CONSTRAINT "retail_receivable_payments_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "peer_debtors" ADD CONSTRAINT "peer_debtors_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "peer_receivables" ADD CONSTRAINT "peer_receivables_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "peer_receivables" ADD CONSTRAINT "peer_receivables_branchId_fkey" FOREIGN KEY ("branchId") REFERENCES "branches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "peer_receivables" ADD CONSTRAINT "peer_receivables_debtorId_fkey" FOREIGN KEY ("debtorId") REFERENCES "peer_debtors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "peer_receivables" ADD CONSTRAINT "peer_receivables_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "peer_receivable_payments" ADD CONSTRAINT "peer_receivable_payments_receivableId_fkey" FOREIGN KEY ("receivableId") REFERENCES "peer_receivables"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "peer_receivable_payments" ADD CONSTRAINT "peer_receivable_payments_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
