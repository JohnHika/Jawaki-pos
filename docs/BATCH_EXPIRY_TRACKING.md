# Batch & Expiry Tracking System

## Overview

The POS system now includes comprehensive **batch and expiry tracking** specifically designed for JAWAKI ADVENTURES' medicine inventory management. This feature ensures legal compliance and safety by preventing the sale of expired products.

## Key Features

### 1. **Batch Management**
- Track individual batches with unique batch numbers
- Record manufacture dates and expiry dates for each batch
- Store supplier references and cost prices per batch
- Support for batch-specific notes and metadata

### 2. **FEFO (First-Expired-First-Out) Logic**
- Automatically allocates stock from batches closest to expiry
- Prevents sale of expired items (auto-blocked)
- Optimizes inventory rotation to minimize waste
- Real-time batch allocation during POS transactions

### 3. **Expiry Dashboard**
- **Red Zone**: Already expired items (auto-blocked from sales)
- **Orange Zone**: Items expiring in 30, 60, or 90 days
- View total stock value at risk
- Trigger clearance sales for expiring items

### 4. **Automated Safety Controls**
- Expired batches are automatically blocked from POS
- Sales validation checks for expired stock
- Prevent accidental sale of expired medicines

## Database Schema

### New Tables

#### `stock_batches`
Tracks individual batches of stock with expiry information.

```sql
- id: Unique batch ID
- stockId: Link to stock record
- batchNumber: Unique batch number/code
- quantity: Current quantity in batch
- reservedQty: Reserved for pending sales
- expiryDate: When batch expires (nullable)
- manufactureDate: When batch was manufactured (nullable)
- costPrice: Cost price for this batch
- supplierRef: Supplier invoice/reference
- notes: Additional notes
- isBlocked: Manually blocked (true for expired)
- createdAt, updatedAt
```

#### `sale_item_batches`
Tracks which batches were used for each sale (audit trail).

```sql
- id: Unique ID
- saleItemId: Link to sale item
- stockBatchId: Batch that was sold
- quantity: Quantity sold from this batch
- batchNumber: Denormalized batch number
- expiryDate: Denormalized expiry date
```

### Updated Tables

#### `stock_movements`
Added batch tracking fields:
- `batchId`: Links movement to specific batch
- `batchNumber`: Denormalized batch number
- `expiryDate`: Denormalized expiry date

### New Stock Movement Types
- `BATCH_RECEIVE`: New batch received
- `EXPIRY`: Batch expired and blocked

## API Endpoints

### Batch Management

#### 1. **Receive Stock with Batches**
```http
POST /v1/inventory/batches/receive
Authorization: Bearer <token>
Roles: SUPERVISOR, MANAGER, ADMIN
```

**Request Body:**
```json
{
  "branchId": "branch-uuid",
  "productId": "product-uuid",
  "reference": "PO-2024-001",
  "batches": [
    {
      "batchNumber": "BATCH-001",
      "quantity": 100,
      "expiryDate": "2026-12-31",
      "manufactureDate": "2024-01-15",
      "costPrice": 50.00,
      "supplierRef": "INV-12345",
      "notes": "Received in good condition"
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "stockId": "stock-uuid",
  "batchesReceived": 1,
  "totalQuantity": 100,
  "batches": [/* batch details */]
}
```

#### 2. **Get Stock with Batch Details**
```http
GET /v1/inventory/batches/:branchId/:productId
Authorization: Bearer <token>
```

**Response:**
```json
{
  "productId": "product-uuid",
  "sku": "MED-001",
  "productName": "Panadol 500mg",
  "totalQuantity": 250,
  "totalReservedQty": 0,
  "totalAvailableQty": 250,
  "batches": [
    {
      "id": "batch-uuid",
      "batchNumber": "BATCH-001",
      "quantity": 100,
      "reservedQty": 0,
      "availableQty": 100,
      "expiryDate": "2026-03-15T00:00:00.000Z",
      "manufactureDate": "2024-01-15T00:00:00.000Z",
      "costPrice": 50.00,
      "supplierRef": "INV-12345",
      "isBlocked": false,
      "isExpired": false,
      "daysUntilExpiry": 402,
      "expiryStatus": "good",
      "createdAt": "2024-01-20T10:00:00.000Z"
    }
  ],
  "hasExpiredBatches": false,
  "hasExpiringSoonBatches": false
}
```

#### 3. **Update Batch**
```http
PUT /v1/inventory/batches/:batchId
Authorization: Bearer <token>
Roles: SUPERVISOR, MANAGER, ADMIN
```

**Request Body:**
```json
{
  "quantity": 95,
  "expiryDate": "2026-12-31",
  "isBlocked": false,
  "notes": "Adjusted after count"
}
```

#### 4. **Get FEFO Batch Allocation**
```http
GET /v1/inventory/batches/fefo/:branchId/:productId?quantity=10
Authorization: Bearer <token>
```

**Response:**
```json
[
  {
    "batchId": "batch-uuid-1",
    "batchNumber": "BATCH-001",
    "quantity": 10,
    "expiryDate": "2026-03-15T00:00:00.000Z"
  }
]
```

### Expiry Dashboard

#### 5. **Get Expiry Dashboard**
```http
GET /v1/inventory/expiry-dashboard?branchId=xxx&zone=30days&page=1&limit=50
Authorization: Bearer <token>
Roles: MANAGER, ADMIN
```

**Query Parameters:**
- `branchId` (required): Branch ID
- `zone` (optional): `expired`, `30days`, `60days`, `90days`
- `search` (optional): Search by product name/SKU
- `page` (optional): Page number (default: 1)
- `limit` (optional): Items per page (default: 50)

**Response:**
```json
{
  "items": [
    {
      "productId": "product-uuid",
      "productName": "Panadol 500mg",
      "sku": "MED-001",
      "batchNumber": "BATCH-001",
      "quantity": 50,
      "expiryDate": "2026-03-15T00:00:00.000Z",
      "daysUntilExpiry": 15,
      "expiryStatus": "critical",
      "isBlocked": false,
      "costValue": 2500.00
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 50,
  "totalPages": 1,
  "summary": {
    "expiredCount": 0,
    "expiredValue": 0,
    "expiring30Days": 5,
    "expiring30DaysValue": 12500.00,
    "expiring60Days": 8,
    "expiring60DaysValue": 20000.00,
    "expiring90Days": 12,
    "expiring90DaysValue": 35000.00
  }
}
```

#### 6. **Auto-Block Expired Batches**
```http
POST /v1/inventory/batches/block-expired
Authorization: Bearer <token>
Roles: ADMIN
```

**Response:**
```json
{
  "success": true,
  "blockedCount": 3,
  "batches": [
    {
      "id": "batch-uuid",
      "batchNumber": "BATCH-OLD-001",
      "expiryDate": "2024-01-01T00:00:00.000Z"
    }
  ]
}
```

## Usage Workflows

### Workflow 1: Stock Keeper Receives Medicine

1. Stock keeper receives new medicine shipment
2. Logs into the system as SUPERVISOR role
3. Navigates to **Inventory > Receive Stock**
4. Selects the product (e.g., "Panadol 500mg")
5. Enters batch details:
   - Batch Number: `BATCH-2026-001`
   - Quantity: 200 units
   - Expiry Date: December 31, 2026
   - Manufacture Date: January 15, 2026
   - Cost Price: KES 45 per unit
   - Supplier Ref: `INV-12345`
6. Saves the batch
7. System automatically:
   - Creates batch record
   - Updates total stock
   - Records stock movement
   - Checks if batch is already expired (auto-blocks if yes)

### Workflow 2: Cashier Makes Sale (POS)

1. Cashier scans item barcode
2. System checks inventory:
   - Finds all non-expired, non-blocked batches
   - Sorts by expiry date (FEFO)
   - Allocates from batch expiring soonest
3. If all available batches are expired:
   - **Blocks the sale**
   - Shows error: "Cannot sell: Product has expired batches"
4. If sufficient non-expired stock:
   - Allocates quantity from appropriate batches
   - Proceeds with sale
   - Records which batches were sold (audit trail)
5. Updates batch quantities automatically

### Workflow 3: Store Manager Reviews Expiry Dashboard

1. Manager logs in with MANAGER role
2. Opens **Expiry Dashboard**
3. Views summary:
   - **Red Zone (Expired)**: 0 items (auto-blocked)
   - **Critical (30 days)**: 5 products worth KES 12,500
   - **Warning (60 days)**: 8 products worth KES 20,000
   - **Caution (90 days)**: 12 products worth KES 35,000
4. Manager decides action:
   - For **Critical** items: Create clearance sale (-20% discount)
   - For **Expired** items: Review and dispose properly
5. Can search/filter by product name or zone
6. Exports report for compliance

### Workflow 4: Admin Blocks Expired Items (Scheduled)

1. System runs daily cron job (e.g., at midnight)
2. Checks all batches for expiry
3. Auto-blocks any batches where `expiryDate < today`
4. Sends notification to managers
5. Blocked batches cannot be sold via POS

## Implementation Checklist

### Database Migration
```bash
cd backend
npx prisma migrate dev --name add_batch_expiry_tracking
npx prisma generate
```

### Testing Scenarios

1. **Receive batch with future expiry** → Should work
2. **Receive batch already expired** → Should auto-block
3. **Sell product with multiple batches** → Should use FEFO
4. **Sell product with only expired batches** → Should block sale
5. **View expiry dashboard** → Should show correct zones
6. **Run auto-block expired** → Should block expired batches

### Security & Permissions

- **Batch Receive**: SUPERVISOR, MANAGER, ADMIN only
- **Batch Update**: SUPERVISOR, MANAGER, ADMIN only
- **Expiry Dashboard**: MANAGER, ADMIN only
- **Auto-Block Expired**: ADMIN only
- **View Batches**: All authenticated users

## Benefits for JAWAKI ADVENTURES

### Legal Compliance
✅ Cannot sell expired medicines (auto-blocked)  
✅ Full audit trail of batch movements  
✅ Traceability for regulatory inspections  

### Financial
✅ Reduce waste through FEFO rotation  
✅ Identify expiring stock for clearance sales  
✅ Track cost value of expiring inventory  

### Safety
✅ Prevent customer harm from expired products  
✅ Automated checks at POS  
✅ Manager oversight via dashboard  

### Operational
✅ Easy stock receiving with batch details  
✅ Automatic batch allocation (no manual tracking)  
✅ Clear visibility of inventory health  

## Future Enhancements

- [ ] SMS alerts for items expiring in 7 days
- [ ] Automated clearance sale pricing
- [ ] Batch return/supplier credit tracking
- [ ] Mobile app batch scanning
- [ ] QR code batch labels
- [ ] Regulatory compliance reports

## Support

For questions or issues, contact the development team.

**Last Updated**: February 8, 2026  
**Version**: 1.0.0
