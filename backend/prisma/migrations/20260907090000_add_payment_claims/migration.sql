-- Add payment claims table for manual (paybill) recurring-billing payments.
-- Table already exists in shared dev/prod DBs (created via prisma db push
-- before this migration was authored); IF NOT EXISTS keeps both paths safe.
CREATE TABLE IF NOT EXISTS "subscription_payment_claims" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "invoiceId" TEXT NOT NULL,
    "mpesaCode" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "submittedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedAt" TIMESTAMP(3),

    CONSTRAINT "subscription_payment_claims_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "subscription_payment_claims_mpesaCode_key" ON "subscription_payment_claims"("mpesaCode");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "subscription_payment_claims_tenantId_status_idx" ON "subscription_payment_claims"("tenantId", "status");

-- AddForeignKey (guarded: skip if an identical constraint already exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'subscription_payment_claims_tenantId_fkey'
    ) THEN
        ALTER TABLE "subscription_payment_claims" ADD CONSTRAINT "subscription_payment_claims_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'subscription_payment_claims_invoiceId_fkey'
    ) THEN
        ALTER TABLE "subscription_payment_claims" ADD CONSTRAINT "subscription_payment_claims_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "subscription_invoices"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;