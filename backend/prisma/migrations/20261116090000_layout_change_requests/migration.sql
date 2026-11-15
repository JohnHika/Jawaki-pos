-- A paid shop's business type is locked to what it paid for. To change it the
-- owner sends a request with a reason; the Counterbase team approves or
-- declines it. Safe to run twice.
CREATE TABLE IF NOT EXISTS "layout_change_requests" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "requestedByUserId" TEXT,
    "fromProfileId" TEXT,
    "toProfileId" TEXT NOT NULL,
    "additionalProfileIds" JSONB,
    "reason" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "decisionNote" TEXT,
    "decidedBy" TEXT,
    "decidedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "layout_change_requests_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "layout_change_requests_tenantId_status_idx" ON "layout_change_requests"("tenantId", "status");
CREATE INDEX IF NOT EXISTS "layout_change_requests_status_createdAt_idx" ON "layout_change_requests"("status", "createdAt");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'layout_change_requests_tenantId_fkey'
    ) THEN
        ALTER TABLE "layout_change_requests"
            ADD CONSTRAINT "layout_change_requests_tenantId_fkey"
            FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
