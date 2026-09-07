-- Add Pesapal recurring card subscription tokens (card auto-renew).
-- One token mapping per tenant: Pesapal tokenizes the card; we only ever
-- store the Pesapal-side identifiers, never raw card data.
-- IF NOT EXISTS + guarded FKs keep shared dev/prod DBs idempotent (same
-- pattern as 20260907090000_add_payment_claims).
CREATE TABLE IF NOT EXISTS "subscription_card_tokens" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "pesapalCorrelationId" TEXT NOT NULL,
    "orderTrackingId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "billingCycle" TEXT NOT NULL DEFAULT 'MONTHLY',
    "plan" TEXT NOT NULL DEFAULT 'CORE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "cancelledAt" TIMESTAMP(3),

    CONSTRAINT "subscription_card_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "subscription_card_tokens_tenantId_key" ON "subscription_card_tokens"("tenantId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "subscription_card_tokens_orderTrackingId_key" ON "subscription_card_tokens"("orderTrackingId");

-- AddForeignKey (guarded: skip if an identical constraint already exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'subscription_card_tokens_tenantId_fkey'
    ) THEN
        ALTER TABLE "subscription_card_tokens" ADD CONSTRAINT "subscription_card_tokens_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;