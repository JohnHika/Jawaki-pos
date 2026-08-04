-- Add subscription plan fields to tenants table
ALTER TABLE "tenants"
  ADD COLUMN "plan" TEXT NOT NULL DEFAULT 'TRIAL',
  ADD COLUMN "subscriptionStatus" TEXT,
  ADD COLUMN "subscriptionProvider" TEXT,
  ADD COLUMN "subscriptionReference" TEXT,
  ADD COLUMN "currentPeriodStart" TIMESTAMP(3),
  ADD COLUMN "currentPeriodEnd" TIMESTAMP(3),
  ADD COLUMN "setupFeePaidAt" TIMESTAMP(3),
  ADD COLUMN "maxBranches" INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN "maxUsers" INTEGER NOT NULL DEFAULT 3;

-- Existing active tenants get CORE plan with reasonable limits
UPDATE "tenants"
SET "plan" = 'CORE',
    "subscriptionStatus" = 'ACTIVE',
    "maxBranches" = 3,
    "maxUsers" = 10
WHERE "activationStatus" = 'ACTIVE';

CREATE UNIQUE INDEX "tenants_subscriptionReference_key"
  ON "tenants"("subscriptionReference");

-- Create subscription_invoices table
CREATE TABLE "subscription_invoices" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT,
    "plan" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'KES',
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "provider" TEXT,
    "reference" TEXT,
    "periodStart" TIMESTAMP(3),
    "periodEnd" TIMESTAMP(3),
    "paidAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subscription_invoices_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "subscription_invoices_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE,
    CONSTRAINT "subscription_invoices_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE SET NULL
);

CREATE UNIQUE INDEX "subscription_invoices_reference_key"
  ON "subscription_invoices"("reference");

CREATE INDEX "subscription_invoices_tenantId_createdAt_idx"
  ON "subscription_invoices"("tenantId", "createdAt");
