-- CreateTable
CREATE TABLE "daily_briefs" (
    "id" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "content" TEXT NOT NULL,
    "model" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "daily_briefs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "daily_briefs_branchId_date_idx" ON "daily_briefs"("branchId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "daily_briefs_branchId_date_key" ON "daily_briefs"("branchId", "date");

-- AddForeignKey
ALTER TABLE "daily_briefs" ADD CONSTRAINT "daily_briefs_branchId_fkey" FOREIGN KEY ("branchId") REFERENCES "branches"("id") ON DELETE CASCADE ON UPDATE CASCADE;
