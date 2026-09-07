-- Add platform_admins table for the Jawaki platform-admin control plane.
-- Table already exists in shared dev/prod DBs (created via prisma db push
-- before this migration was authored); IF NOT EXISTS keeps both paths safe.
CREATE TABLE IF NOT EXISTS "platform_admins" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "name" TEXT NOT NULL DEFAULT 'Platform Owner',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "platform_admins_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "platform_admins_email_key" ON "platform_admins"("email");