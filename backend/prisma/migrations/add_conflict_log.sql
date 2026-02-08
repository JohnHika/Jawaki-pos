-- Add conflict log table for tracking sync conflicts
-- Run this migration after updating schema.prisma

CREATE TABLE IF NOT EXISTS "conflict_logs" (
  "id" TEXT NOT NULL,
  "table_name" TEXT NOT NULL,
  "record_id" TEXT NOT NULL,
  "conflict_type" TEXT NOT NULL,
  "resolution" TEXT NOT NULL,
  "server_data" JSONB,
  "client_data" JSONB,
  "resolved_data" JSONB,
  "notes" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "created_by" TEXT,
  
  CONSTRAINT "conflict_logs_pkey" PRIMARY KEY ("id")
);

-- Add indexes for querying
CREATE INDEX "conflict_logs_table_name_record_id_idx" ON "conflict_logs"("table_name", "record_id");
CREATE INDEX "conflict_logs_created_at_idx" ON "conflict_logs"("created_at");
CREATE INDEX "conflict_logs_conflict_type_idx" ON "conflict_logs"("conflict_type");

-- Add audit log table for deletion tracking
CREATE TABLE IF NOT EXISTS "audit_logs" (
  "id" TEXT NOT NULL,
  "table_name" TEXT NOT NULL,
  "record_id" TEXT NOT NULL,
  "action" TEXT NOT NULL, -- INSERT, UPDATE, DELETE
  "old_data" JSONB,
  "new_data" JSONB,
  "user_id" TEXT,
  "ip_address" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- Add indexes for audit log
CREATE INDEX "audit_logs_table_name_record_id_idx" ON "audit_logs"("table_name", "record_id");
CREATE INDEX "audit_logs_action_idx" ON "audit_logs"("action");
CREATE INDEX "audit_logs_created_at_idx" ON "audit_logs"("created_at");
