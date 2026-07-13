-- CreateTable
CREATE TABLE "print_jobs" (
    "id" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "requestedById" TEXT NOT NULL,
    "requestedByUserId" TEXT,
    "claimedById" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "payload" JSONB NOT NULL,
    "errorMessage" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "print_jobs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "print_jobs_branchId_status_createdAt_idx" ON "print_jobs"("branchId", "status", "createdAt");

-- AddForeignKey
ALTER TABLE "print_jobs" ADD CONSTRAINT "print_jobs_branchId_fkey" FOREIGN KEY ("branchId") REFERENCES "branches"("id") ON DELETE CASCADE ON UPDATE CASCADE;
