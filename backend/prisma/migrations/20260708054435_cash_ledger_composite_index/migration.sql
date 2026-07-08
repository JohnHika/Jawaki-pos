-- DropIndex
DROP INDEX "cash_ledger_entries_branchId_createdAt_idx";

-- CreateIndex
CREATE INDEX "cash_ledger_entries_branchId_type_createdAt_idx" ON "cash_ledger_entries"("branchId", "type", "createdAt");
