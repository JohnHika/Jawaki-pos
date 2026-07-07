-- AlterEnum
-- Add UNPAID as a new subscription state. TRIAL is kept on the enum
-- (rather than dropped) so any existing rows with that value remain
-- valid; new subscriptions are never created with it going forward.
-- Split into its own migration because PostgreSQL does not allow a
-- newly-added enum value to be referenced in the same transaction
-- that added it.
ALTER TYPE "AiSubscriptionStatus" ADD VALUE IF NOT EXISTS 'UNPAID';
