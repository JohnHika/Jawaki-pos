-- DropForeignKey
ALTER TABLE "subscription_invoices" DROP CONSTRAINT "subscription_invoices_tenantId_fkey";

-- DropForeignKey
ALTER TABLE "subscription_invoices" DROP CONSTRAINT "subscription_invoices_userId_fkey";

-- AlterTable
ALTER TABLE "subscription_invoices" ADD COLUMN     "mpesaCheckoutId" TEXT,
ADD COLUMN     "renewalSequence" INTEGER NOT NULL DEFAULT 1;

-- AlterTable
ALTER TABLE "tenants" ADD COLUMN     "autoRenewEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "billingPhone" TEXT;

-- CreateIndex
CREATE INDEX "subscription_invoices_tenantId_periodStart_idx" ON "subscription_invoices"("tenantId", "periodStart");

-- CreateIndex
CREATE INDEX "subscription_invoices_status_idx" ON "subscription_invoices"("status");

-- AddForeignKey
ALTER TABLE "subscription_invoices" ADD CONSTRAINT "subscription_invoices_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription_invoices" ADD CONSTRAINT "subscription_invoices_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
