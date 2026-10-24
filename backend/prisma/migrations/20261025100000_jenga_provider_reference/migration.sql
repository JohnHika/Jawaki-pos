ALTER TABLE "mpesa_transactions"
ADD COLUMN "providerReference" TEXT;

CREATE UNIQUE INDEX "mpesa_transactions_providerReference_key"
ON "mpesa_transactions"("providerReference");
