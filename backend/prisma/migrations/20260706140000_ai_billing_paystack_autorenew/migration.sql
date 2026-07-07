-- CreateEnum
CREATE TYPE "AiPaymentMethod" AS ENUM ('MPESA_MANUAL', 'PAYSTACK_CARD');

-- AlterTable
-- Paystack recurring billing fields for AiSubscription.
ALTER TABLE "ai_subscriptions" ADD COLUMN "paystackCustomerCode" TEXT;
ALTER TABLE "ai_subscriptions" ADD COLUMN "paystackCustomerEmail" TEXT;
ALTER TABLE "ai_subscriptions" ADD COLUMN "paystackAuthorizationCode" TEXT;
ALTER TABLE "ai_subscriptions" ADD COLUMN "lastRenewalAttemptAt" TIMESTAMP(3);
ALTER TABLE "ai_subscriptions" ADD COLUMN "renewalFailureCount" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
-- Auto-renew defaults to true now that Paystack card auto-charge exists;
-- existing rows are backfilled to false since they have no saved card yet.
ALTER TABLE "ai_subscriptions" ALTER COLUMN "autoRenew" SET DEFAULT true;
UPDATE "ai_subscriptions" SET "autoRenew" = false WHERE "paystackAuthorizationCode" IS NULL;

-- AlterTable
-- ai_payments: mpesaCode becomes optional (Paystack payments have no
-- M-Pesa code), and gains a payment-method + Paystack reference so both
-- flows share one payment history table.
ALTER TABLE "ai_payments" ALTER COLUMN "mpesaCode" DROP NOT NULL;
ALTER TABLE "ai_payments" ALTER COLUMN "recipientPhone" DROP NOT NULL;
ALTER TABLE "ai_payments" ADD COLUMN "method" "AiPaymentMethod" NOT NULL DEFAULT 'MPESA_MANUAL';
ALTER TABLE "ai_payments" ADD COLUMN "paystackReference" TEXT;
ALTER TABLE "ai_payments" ADD COLUMN "isRenewal" BOOLEAN NOT NULL DEFAULT false;

-- CreateIndex
CREATE UNIQUE INDEX "ai_payments_paystackReference_key" ON "ai_payments"("paystackReference");
