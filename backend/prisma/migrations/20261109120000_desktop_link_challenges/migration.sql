-- Computer sign-in approved from a signed-in phone. The computer keeps a
-- random verifier and only its SHA-256 is stored (claimSecretHash).
-- Written to be safe if an earlier draft of this table was created by hand.
CREATE TABLE IF NOT EXISTS "desktop_link_challenges" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "claimSecretHash" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "mode" TEXT NOT NULL DEFAULT 'approval',
    "desktopName" TEXT,
    "userId" TEXT,
    "branchId" TEXT,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "ip" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "approvedAt" TIMESTAMP(3),
    "claimedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "desktop_link_challenges_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "desktop_link_challenges" ADD COLUMN IF NOT EXISTS "platform" TEXT;
ALTER TABLE "desktop_link_challenges" ADD COLUMN IF NOT EXISTS "place" TEXT;
ALTER TABLE "desktop_link_challenges" ADD COLUMN IF NOT EXISTS "approverIp" TEXT;
ALTER TABLE "desktop_link_challenges" DROP COLUMN IF EXISTS "accessTokenHash";
ALTER TABLE "desktop_link_challenges" DROP COLUMN IF EXISTS "refreshTokenHash";

-- Codes repeat once a request is finished; only live ones must differ.
DROP INDEX IF EXISTS "desktop_link_challenges_code_key";
CREATE INDEX IF NOT EXISTS "desktop_link_challenges_code_status_idx" ON "desktop_link_challenges"("code", "status");
CREATE INDEX IF NOT EXISTS "desktop_link_challenges_status_expiresAt_idx" ON "desktop_link_challenges"("status", "expiresAt");
CREATE INDEX IF NOT EXISTS "desktop_link_challenges_userId_createdAt_idx" ON "desktop_link_challenges"("userId", "createdAt");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'desktop_link_challenges_userId_fkey'
    ) THEN
        ALTER TABLE "desktop_link_challenges"
            ADD CONSTRAINT "desktop_link_challenges_userId_fkey"
            FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
END $$;
