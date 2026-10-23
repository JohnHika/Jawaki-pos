CREATE TABLE "merchant_payment_accounts" (
    "tenantId" TEXT NOT NULL,
    "provider" TEXT NOT NULL DEFAULT 'PAYSTACK',
    "subaccountCode" TEXT NOT NULL,
    "bankCode" TEXT NOT NULL,
    "bankName" TEXT NOT NULL,
    "accountName" TEXT,
    "accountLast4" TEXT NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'KES',
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "merchant_payment_accounts_pkey" PRIMARY KEY ("tenantId")
);

CREATE UNIQUE INDEX "merchant_payment_accounts_subaccountCode_key" ON "merchant_payment_accounts"("subaccountCode");

ALTER TABLE "merchant_payment_accounts" ADD CONSTRAINT "merchant_payment_accounts_tenantId_fkey"
    FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "merchant_charges" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "requestId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "cashierId" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "subaccountCode" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'KES',
    "phone" TEXT NOT NULL,
    "customerEmail" TEXT NOT NULL,
    "salePayload" JSONB NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "providerStatus" TEXT,
    "saleId" TEXT,
    "receiptNumber" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "merchant_charges_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "merchant_charges_reference_key" ON "merchant_charges"("reference");
CREATE UNIQUE INDEX "merchant_charges_tenantId_requestId_key" ON "merchant_charges"("tenantId", "requestId");
CREATE UNIQUE INDEX "merchant_charges_saleId_key" ON "merchant_charges"("saleId");
CREATE INDEX "merchant_charges_tenantId_createdAt_idx" ON "merchant_charges"("tenantId", "createdAt");

ALTER TABLE "merchant_charges" ADD CONSTRAINT "merchant_charges_tenantId_fkey"
    FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
