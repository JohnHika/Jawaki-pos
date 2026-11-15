-- New shops are quoted the owner-approved setup fee of KES 125,000.
-- Existing rows keep the amount they already have (35,000 stays on record for
-- shops that paid it); the service quotes unpaid shops the current fee.
ALTER TABLE "tenants" ALTER COLUMN "activationAmount" SET DEFAULT 125000.00;
