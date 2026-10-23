ALTER TABLE "merchant_charges"
  ADD COLUMN "purpose" TEXT NOT NULL DEFAULT 'SALE',
  ADD COLUMN "receivableType" TEXT,
  ADD COLUMN "receivableId" TEXT,
  ADD COLUMN "receivablePaymentId" TEXT;

CREATE INDEX "merchant_charges_tenant_purpose_status_idx"
  ON "merchant_charges"("tenantId", "purpose", "status");
