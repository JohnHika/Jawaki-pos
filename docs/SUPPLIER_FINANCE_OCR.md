# Supplier Finance Receipt OCR

This feature adds supplier accountability to the mobile Finance screen.

## What It Does

- Captures a supplier receipt from the camera or gallery.
- Runs on-device OCR using Google ML Kit text recognition.
- Suggests the supplier name, invoice or receipt number, total, and line items.
- Lets the user review and correct extracted items before saving.
- Records the supplier invoice, payment terms, due date, paid amount, and balance due.
- Creates or updates catalog products from confirmed receipt items.
- Increases local branch stock for received items.
- Shows supplier balances, invoice counts, overdue counts, payment progress, and invoice history.

## User Flow

1. Open the mobile app.
2. Go to `Finance`.
3. Tap `Scan Receipt`.
4. Choose camera or gallery.
5. Review the OCR summary and extracted line items.
6. Correct supplier, invoice number, terms, due date, paid amount, item names, quantities, and costs.
7. Tap `Save Invoice`.

The invoice is saved only after user confirmation. OCR output is treated as a draft, not as trusted accounting data.

## Data Model

The mobile SQLite database now creates these raw SQL tables:

- `supplier_invoices`
- `supplier_invoice_items`

These extend the existing:

- `suppliers`
- `supplier_payments`

Supplier balances are calculated as:

`total supplier invoice amount - total supplier payments`

## Catalog Update Behavior

When an invoice is saved:

- Each confirmed line item is matched by product name or SKU.
- Existing products have `cost_price` updated.
- New products are created in the `Supplier Receipts` category.
- Local stock is increased for the active branch, falling back to `branch-main`.

## Notes

- OCR is local/offline and does not send receipt images to a cloud AI provider.
- The parsing is intentionally conservative and review-first. Receipts vary a lot, so the user must confirm the extracted data.
- Future server sync should map `supplier_invoices` and `supplier_invoice_items` into backend Prisma models if supplier accounting needs central reporting across devices.
