-- Keep the persisted tenant activation default aligned with the verified
-- activation charge used by TenantActivationService (KES 35,000).
ALTER TABLE "tenants"
  ALTER COLUMN "activationAmount" SET DEFAULT 35000.00;

-- Pending workspaces have not paid the old amount, so move only those
-- unactivated records to the current published fee. Paid tenants are never
-- rewritten.
UPDATE "tenants"
SET "activationAmount" = 35000.00
WHERE "activationStatus" = 'PENDING'
  AND "activationPaidAt" IS NULL;
