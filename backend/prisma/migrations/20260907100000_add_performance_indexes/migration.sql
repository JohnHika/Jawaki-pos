-- Performance indexes for the hottest dashboard/catalog paths.
-- Each index matches a real WHERE/ORDER BY shape used by reporting,
-- catalog, and sales queries — see the audit notes inline.

-- getTopProducts / getCategorySales group SaleItem by productId filtering
-- on the parent sale's branch/tenant/date/status. Composite covers the
-- join-back filter.
CREATE INDEX IF NOT EXISTS "sale_items_saleId_idx" ON "sale_items"("saleId");
CREATE INDEX IF NOT EXISTS "sale_items_productId_idx" ON "sale_items"("productId");

-- Dashboard WHERE (branchId, status, createdAt) — covers
-- getSalesSummary/getSalesTrend/getDailyProfitAndLoss on the sale table.
CREATE INDEX IF NOT EXISTS "sales_branchId_status_createdAt_idx" ON "sales"("branchId", "status", "createdAt");

-- Product list ORDER BY (sortOrder, name) within a tenant.
CREATE INDEX IF NOT EXISTS "products_tenantId_sortOrder_name_idx" ON "products"("tenantId", "sortOrder", "name");

-- Expense listing per branch over time.
CREATE INDEX IF NOT EXISTS "expenses_branchId_createdAt_idx" ON "expenses"("branchId", "createdAt");