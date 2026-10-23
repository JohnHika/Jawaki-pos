ALTER TYPE "CashFundingSource" ADD VALUE IF NOT EXISTS 'BANK_OR_MPESA';

ALTER TABLE "supplier_payments"
  ADD COLUMN "fundingSource" "CashFundingSource" NOT NULL DEFAULT 'CASH_TILL',
  ADD COLUMN "requestId" TEXT;

CREATE UNIQUE INDEX "supplier_payments_requestId_key"
  ON "supplier_payments"("requestId");
