-- AlterTable
-- Trial dates are no longer required for new subscriptions (no free trial).
ALTER TABLE "ai_subscriptions" ALTER COLUMN "trialStartedAt" DROP NOT NULL;
ALTER TABLE "ai_subscriptions" ALTER COLUMN "trialStartedAt" DROP DEFAULT;
ALTER TABLE "ai_subscriptions" ALTER COLUMN "trialEndsAt" DROP NOT NULL;

-- AlterTable
-- New subscriptions default to UNPAID (must pay before use) instead of TRIAL.
ALTER TABLE "ai_subscriptions" ALTER COLUMN "status" SET DEFAULT 'UNPAID';
ALTER TABLE "ai_subscriptions" ALTER COLUMN "price" SET DEFAULT 1500.00;

-- Data migration: any subscription still sitting in TRIAL is reclassified
-- as UNPAID now that trials no longer exist.
UPDATE "ai_subscriptions" SET "status" = 'UNPAID' WHERE "status" = 'TRIAL';
