-- Store per-base-unit prices precisely when a bulk tier's price does not
-- divide evenly into its base-unit conversion (for example, KES 100 / 3).
ALTER TABLE "sale_items"
ALTER COLUMN "unitPrice" TYPE DECIMAL(18, 8)
USING "unitPrice"::DECIMAL(18, 8);
