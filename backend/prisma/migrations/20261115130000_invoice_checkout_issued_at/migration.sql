-- When the hosted checkout link on a subscription invoice was issued, so an
-- old link is replaced instead of handed back. Existing rows stay NULL, which
-- counts as stale: the next payment attempt on them opens a fresh link.
ALTER TABLE "subscription_invoices" ADD COLUMN IF NOT EXISTS "authorizationIssuedAt" TIMESTAMP(3);
