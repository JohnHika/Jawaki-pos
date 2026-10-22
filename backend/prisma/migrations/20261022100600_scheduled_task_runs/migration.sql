CREATE TABLE "scheduled_task_runs" (
    "id" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'RUNNING',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "leaseExpiresAt" TIMESTAMP(3) NOT NULL,
    "completedAt" TIMESTAMP(3),
    "lastError" TEXT,

    CONSTRAINT "scheduled_task_runs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "scheduled_task_runs_startedAt_idx"
ON "scheduled_task_runs"("startedAt");
