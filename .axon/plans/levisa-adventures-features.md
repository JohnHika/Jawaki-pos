# Levisa Adventures Payment System Implementation Plan

## Context

This plan implements the payment system features for **Levisa Adventures** (formerly generic "POS System") based on requirements extracted from a PDF document. The system is a hybrid multi-branch POS with NestJS backend, Flutter mobile app, and Next.js store management system.

## Requirements Summary

From the extracted PDF requirements:

1. **Payment Method Integration**: Manual payment method integration to be approved by the system
2. **Payment Holding**: Hold payments for customers who are to pay later
3. **Bulk Payments**: For both customers and merchants
4. **Customer Payment Export**: Export customer payment data (purchase and payment)
5. **Customer Phone Number**: Store and display customer phone numbers
6. **Product per Box**: Optional product-per-box setting
7. **Cash Amount Given**: Track cash amount tendered and change
8. **Receipt Management**: Receipts must include location, customer name, phone number, time; ability to review/reprint
9. **Expense vs Sales Tracking**: Cross-reference expenses against daily total sales

## Current System State

### Already Implemented (from exploration)

✅ **Credit/Pay-Later System**: CREDIT payment method with outstanding balance tracking
✅ **Customer Management**: Full CRUD with phone, email, address, loyalty points
✅ **Customer Export**: CSV/Excel export functionality
✅ **Product Box Settings**: secondaryUnit, secondaryUnitQty, tertiaryUnit, tertiaryaryUnitQty fields
✅ **Expense Tracking**: Full expense module with categories, approval workflow, line items
✅ **Daily Profit & Loss**: Integrated sales and expenses with COGS calculation
✅ **Cash Payment**: Cash payment with change calculation
✅ **Receipt Generation**: Receipts with branch info, items, totals, payment method
✅ **Receipt Screen**: Mobile app receipt view with share/print buttons

### Gaps to Address

❌ **Manual Payment Approval Workflow**: No formal approval process for manual payments
❌ **Bulk Payment Processing**: No UI for processing multiple payments at once
❌ **Enhanced Receipt Fields**: Missing customer phone number on receipts
❌ **Receipt Review/Reprint UI**: No dedicated receipt management page
❌ **Payment Holding Queue**: No dedicated UI for viewing held/pay-later payments
❌ **Levisa Adventures Branding**: System still uses generic "POS System" naming

## Implementation Approach

### Phase 1: Branding Update

**Files to Modify:**
- `store-management-system/package.json` - Update name to "Levisa Adventures"
- `mobile/pubspec.yaml` - Update app name
- `backend/prisma/schema.prisma` - Update Tenant model references
- Receipt templates and UI labels

### Phase 2: Manual Payment Approval Workflow

**New Backend Files:**
- `backend/src/payments/dto/manual-payment.dto.ts` - DTOs for manual payment requests
- `backend/src/payments/services/manual-payment.service.ts` - Approval workflow logic

**New Backend Endpoints:**
```
POST   /api/v1/payments/manual/request    - Request manual payment approval
GET    /api/v1/payments/manual/pending    - List pending approvals
POST   /api/v1/payments/manual/:id/approve - Approve manual payment
POST   /api/v1/payments/manual/:id/reject  - Reject manual payment
```

**Database Changes:**
- Add `ManualPaymentRequest` model to Prisma schema with status (PENDING, APPROVED, REJECTED)

**Frontend (Next.js):**
- `store-management-system/app/payments/manual/page.tsx` - Manual payment approval dashboard

### Phase 3: Bulk Payment Processing

**Backend:**
- `backend/src/payments/dto/bulk-payment.dto.ts` - Bulk payment DTOs
- `backend/src/payments/controllers/bulk-payments.controller.ts` - Bulk payment endpoints
- `backend/src/payments/services/bulk-payment.service.ts` - Bulk processing logic

**Endpoints:**
```
POST /api/v1/payments/bulk/process - Process multiple payments
POST /api/v1/payments/bulk/credit  - Bulk credit payments for customers
GET  /api/v1/payments/bulk/status/:batchId - Check batch status
```

**Mobile App:**
- `mobile/lib/features/sales/presentation/screens/bulk_payment_screen.dart`
- `mobile/lib/features/sales/presentation/providers/bulk_payment_provider.dart`

### Phase 4: Enhanced Receipt Management

**Database:**
- Update Sale model queries to include customer phone in all receipt responses

**Backend:**
- `backend/src/sales/sales.service.ts` - Ensure customer phone is included in formatSale()

**Next.js Receipt Management:**
- `store-management-system/app/receipts/page.tsx` - Receipt list with search/filter
- `store-management-system/app/receipts/[id]/page.tsx` - Receipt detail with reprint
- `store-management-system/app/api/receipts/route.ts` - Receipt listing API
- `store-management-system/app/api/receipts/[id]/route.ts` - Single receipt API

**Mobile Receipt Enhancement:**
- Update `mobile/lib/features/sales/presentation/screens/receipt_screen.dart` to show customer phone

### Phase 5: Payment Holding Queue UI

**Next.js:**
- `store-management-system/app/payments/hold-queue/page.tsx` - View held/pay-later payments
- Filter credit sales by outstanding balance and due date
- Actions: Record payment, send reminder, write off

**Backend:**
- Extend `backend/src/sales/sales.controller.ts` with credit sales management endpoints

### Phase 6: Daily Sales vs Expenses Dashboard

**Next.js:**
- `store-management-system/app/reports/daily-summary/page.tsx` - Enhanced daily report
- Show sales totals by payment method
- Show expenses by category
- Calculate net profit/loss
- Visual charts comparing sales vs expenses

**Backend:**
- Already has `getDailyProfitAndLoss()` in reporting service
- May need to add aggregation endpoint for multiple days

## Technical Considerations

### Database Migrations
All Prisma schema changes require migration:
```bash
cd backend
npx prisma migrate dev --name levisa_features
npx prisma generate
```

### API Client Updates
Mobile app needs API client methods for:
- Manual payment requests
- Bulk payment processing
- Receipt listing

### Testing Strategy
1. Unit tests for new services
2. Integration tests for payment workflows
3. E2E tests for critical paths (credit sale, approval, bulk payment)

## File Inventory

### Files to Create

**Backend:**
- `backend/src/payments/dto/manual-payment.dto.ts`
- `backend/src/payments/services/manual-payment.service.ts`
- `backend/src/payments/dto/bulk-payment.dto.ts`
- `backend/src/payments/services/bulk-payment.service.ts`
- `backend/src/payments/controllers/bulk-payments.controller.ts`

**Next.js:**
- `store-management-system/app/payments/manual/page.tsx`
- `store-management-system/app/payments/hold-queue/page.tsx`
- `store-management-system/app/receipts/page.tsx`
- `store-management-system/app/receipts/[id]/page.tsx`
- `store-management-system/app/reports/daily-summary/page.tsx`
- `store-management-system/app/api/receipts/route.ts`
- `store-management-system/app/api/receipts/[id]/route.ts`

**Mobile:**
- `mobile/lib/features/sales/presentation/screens/bulk_payment_screen.dart`
- `mobile/lib/features/sales/presentation/providers/bulk_payment_provider.dart`

### Files to Modify

**Backend:**
- `backend/prisma/schema.prisma` - Add ManualPaymentRequest model
- `backend/src/sales/sales.service.ts` - Ensure customer phone in receipts
- `backend/src/sales/sales.controller.ts` - Add credit management endpoints
- `backend/src/payments/payments.module.ts` - Import new modules

**Next.js:**
- `store-management-system/package.json` - Update name
- `store-management-system/components/layout/navbar.tsx` - Add new nav items
- `store-management-system/app/products/products-client.tsx` - Verify box settings UI

**Mobile:**
- `mobile/pubspec.yaml` - Update app name
- `mobile/lib/features/sales/presentation/screens/receipt_screen.dart` - Add customer phone
- `mobile/lib/core/network/api_client.dart` - Add new API methods

## Verification Steps

1. **Manual Payment Approval:**
   - Create manual payment request
   - Approve/reject in dashboard
   - Verify status updates

2. **Bulk Payments:**
   - Select multiple credit sales
   - Process bulk payment
   - Verify all balances update

3. **Receipt Management:**
   - View receipt list
   - Search by customer name/phone
   - Reprint receipt
   - Verify customer phone displays

4. **Payment Hold Queue:**
   - View all credit sales with outstanding balances
   - Record partial/full payment
   - Verify balance updates

5. **Daily Summary:**
   - View sales vs expenses for today
   - Verify P&L calculation
   - Check expense categorization

6. **Branding:**
   - Verify "Levisa Adventures" appears in UI
   - Check receipts, emails, page titles
