-- Computers signed in by approving on a phone are now listed on that phone, and
-- can be signed out from it. Each sign-in gets a row; the computer's refresh
-- tokens point at it so revoking one computer leaves the others signed in.
-- Safe to run twice.
CREATE TABLE IF NOT EXISTS "linked_computers" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "desktopName" TEXT NOT NULL,
    "platform" TEXT,
    "place" TEXT,
    "ip" TEXT,
    "deviceId" TEXT,
    "linkedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastActiveAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "linked_computers_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "refresh_tokens" ADD COLUMN IF NOT EXISTS "linkedComputerId" TEXT;

CREATE INDEX IF NOT EXISTS "linked_computers_userId_revokedAt_idx" ON "linked_computers"("userId", "revokedAt");
CREATE INDEX IF NOT EXISTS "refresh_tokens_linkedComputerId_idx" ON "refresh_tokens"("linkedComputerId");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'linked_computers_userId_fkey'
    ) THEN
        ALTER TABLE "linked_computers"
            ADD CONSTRAINT "linked_computers_userId_fkey"
            FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'refresh_tokens_linkedComputerId_fkey'
    ) THEN
        ALTER TABLE "refresh_tokens"
            ADD CONSTRAINT "refresh_tokens_linkedComputerId_fkey"
            FOREIGN KEY ("linkedComputerId") REFERENCES "linked_computers"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
