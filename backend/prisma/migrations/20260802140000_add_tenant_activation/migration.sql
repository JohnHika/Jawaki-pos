-- One-time paid activation for newly created Axon tenants.
ALTER TABLE "tenants"
  ADD COLUMN "activationStatus" TEXT NOT NULL DEFAULT 'PENDING',
  ADD COLUMN "activationAmount" DECIMAL(12,2) NOT NULL DEFAULT 50000.00,
  ADD COLUMN "activationReference" TEXT,
  ADD COLUMN "activationProvider" TEXT,
  ADD COLUMN "activationAuthorizationUrl" TEXT,
  ADD COLUMN "activationPaidAt" TIMESTAMP(3);

-- Existing production tenants are already active and must not be locked by
-- the new default intended only for tenants created after this migration.
UPDATE "tenants"
SET "activationStatus" = 'ACTIVE'
WHERE "activationStatus" = 'PENDING';

CREATE UNIQUE INDEX "tenants_activationReference_key"
  ON "tenants"("activationReference");
