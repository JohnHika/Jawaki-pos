ALTER TABLE "stock_transfers"
ADD COLUMN "requestId" TEXT;

CREATE UNIQUE INDEX "stock_transfers_requestId_key"
ON "stock_transfers"("requestId");