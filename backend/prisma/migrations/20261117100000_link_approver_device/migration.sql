-- Which phone approved a computer, so the computer can say it is linked to
-- that phone. Additive and nullable; safe to run twice.
ALTER TABLE "desktop_link_challenges" ADD COLUMN IF NOT EXISTS "approverDevice" TEXT;
ALTER TABLE "linked_computers" ADD COLUMN IF NOT EXISTS "approverDevice" TEXT;
