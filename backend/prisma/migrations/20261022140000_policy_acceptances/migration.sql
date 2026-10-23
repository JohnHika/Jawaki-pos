CREATE TABLE "policy_acceptances" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "acceptedByUserId" TEXT NOT NULL,
    "policyType" TEXT NOT NULL,
    "policyVersion" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "policy_acceptances_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "policy_acceptances_owner_type_version_key"
    ON "policy_acceptances"("tenantId", "acceptedByUserId", "policyType", "policyVersion");

CREATE INDEX "policy_acceptances_tenant_type_version_idx"
    ON "policy_acceptances"("tenantId", "policyType", "policyVersion");

ALTER TABLE "policy_acceptances"
    ADD CONSTRAINT "policy_acceptances_tenantId_fkey"
    FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "tenants" ALTER COLUMN "autoRenewEnabled" SET DEFAULT false;

UPDATE "tenants" AS tenant
SET "autoRenewEnabled" = false
WHERE tenant."autoRenewEnabled" = true
  AND NOT EXISTS (
    SELECT 1
    FROM "policy_acceptances" AS acceptance
    WHERE acceptance."tenantId" = tenant."id"
      AND acceptance."policyType" = 'AUTO_RENEWAL_AUTHORIZATION'
      AND acceptance."policyVersion" = '2026-10-22-v1'
  );
