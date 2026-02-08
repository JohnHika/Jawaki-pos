# Multi-Unit Inventory System - Quick Reference Guide

## 📦 Overview

The Multi-Unit Inventory System allows supervisors to receive stock in different units (cartons, boxes, packs) and automatically converts them to the base unit (pieces). This eliminates manual calculation errors and speeds up inventory receiving.

## 🎯 Key Features

### Backend Features

1. **Product Unit Configuration**
   - Base unit (e.g., "piece", "item", "unit")
   - Secondary unit (e.g., "box", "pack") with conversion factor
   - Tertiary unit (e.g., "carton", "case") with conversion factor

2. **Automatic Conversion**
   - Receives quantities in any configured unit
   - Automatically converts to base units for storage
   - Records original unit and conversion in batch notes

3. **Flexible Configuration**
   - Supports up to 3 unit levels (base, secondary, tertiary)
   - Decimal conversion factors for precision
   - Per-product unit configuration

### Mobile Features

1. **Unit Selector Widget**
   - Visual chip-based unit selection
   - Real-time conversion info display
   - Automatic unit switching

2. **Conversion Calculator**
   - Live quantity conversion preview
   - Quick reference for all unit conversions
   - Shows final base unit quantity

3. **Enhanced Batch Receive Screen**
   - Multi-batch entry in one session
   - Unit selection per batch
   - Inline conversion preview
   - Collapsible optional fields

## 📝 How to Use

### Step 1: Configure Product Units (Backend)

```sql
-- Example: Configure a product with multi-unit support
UPDATE products SET
  unit = 'piece',
  secondary_unit = 'box',
  secondary_unit_qty = 12.0,  -- 1 box = 12 pieces
  tertiary_unit = 'carton',
  tertiary_unit_qty = 144.0   -- 1 carton = 144 pieces (12 boxes)
WHERE sku = 'PROD-001';
```

Or via API:

```typescript
await prisma.product.update({
  where: { id: productId },
  data: {
    unit: 'piece',
    secondaryUnit: 'box',
    secondaryUnitQty: 12.0,
    tertiaryUnit: 'carton',
    tertiaryUnitQty: 144.0,
  },
});
```

### Step 2: Receive Stock (Mobile App)

1. Navigate to **Inventory > Receive Stock**
2. Select the product
3. For each batch:
   - Enter batch number
   - Enter quantity
   - **Select unit** (piece, box, or carton)
   - The app shows the conversion automatically
   - Add expiry date
   - (Optional) Add manufacture date, cost price, supplier ref, notes
4. Add more batches if needed
5. Tap **Receive Batches**

### Step 3: View Conversion (Backend API)

```bash
POST /api/v1/inventory/batches/receive
{
  "branchId": "branch-id",
  "productId": "product-id",
  "batches": [
    {
      "batchNumber": "BTH-2024-001",
      "quantity": 5,
      "unit": "carton",
      "unitsPerQuantity": 144,  // Optional, auto-detected from product config
      "expiryDate": "2025-12-31"
    }
  ]
}
```

**Result:**
- System receives: 5 cartons
- Converts to: 720 pieces (5 × 144)
- Stores in batch notes: "Received 5 carton = 720 piece"
- Updates stock: +720 pieces

## 🔧 API Endpoints

### Receive Batches with Unit Conversion

```
POST /api/v1/inventory/batches/receive
```

**Request:**
```json
{
  "branchId": "branch-123",
  "productId": "product-456",
  "batches": [
    {
      "batchNumber": "BTH-001",
      "quantity": 10,
      "unit": "box",
      "expiryDate": "2025-06-30",
      "costPrice": 5.50,
      "supplierRef": "INV-2024-001",
      "notes": "First shipment"
    }
  ],
  "reference": "PO-2024-001"
}
```

**Response:**
```json
{
  "success": true,
  "stockId": "stock-789",
  "batchesReceived": 1,
  "totalQuantity": 120,  // 10 boxes × 12 pieces
  "batches": [
    {
      "id": "batch-101",
      "batchNumber": "BTH-001",
      "quantity": "120",
      "notes": "Received 10 box = 120 piece. First shipment"
    }
  ]
}
```

## 📊 Database Schema

### Product Model Extensions

```prisma
model Product {
  // ... existing fields ...
  
  unit            String   @default("piece")     // Base unit
  secondaryUnit   String?                        // e.g., "box"
  secondaryUnitQty Decimal? @db.Decimal(10, 3)   // How many pieces per box
  tertiaryUnit    String?                        // e.g., "carton"
  tertiaryUnitQty Decimal? @db.Decimal(10, 3)    // How many pieces per carton
}
```

### BatchDto Extensions

```typescript
export class BatchDto {
  batchNumber: string;
  quantity: number;
  unit?: string;                // Selected unit (piece/box/carton)
  unitsPerQuantity?: number;    // Conversion factor (auto-filled)
  expiryDate?: string;
  manufactureDate?: string;
  costPrice?: number;
  supplierRef?: string;
  notes?: string;
}
```

## 💡 Example Scenarios

### Scenario 1: Beverage Distributor

**Product:** Coca-Cola 500ml
- Base: piece (individual bottle)
- Secondary: pack (6 bottles)
- Tertiary: case (24 bottles = 4 packs)

**Receiving:**
- Supervisor receives: 50 cases
- System converts: 50 × 24 = 1,200 bottles
- Stock updated: +1,200 pieces

### Scenario 2: Pharmaceutical Wholesale

**Product:** Paracetamol 500mg
- Base: tablet
- Secondary: blister (10 tablets)
- Tertiary: box (100 tablets = 10 blisters)

**Receiving:**
- Supervisor receives: 20 boxes
- System converts: 20 × 100 = 2,000 tablets
- Stock updated: +2,000 tablets

### Scenario 3: Grocery Store

**Product:** Rice
- Base: kg
- Secondary: bag (5 kg)
- Tertiary: sack (50 kg = 10 bags)

**Receiving:**
- Supervisor receives: 10 sacks
- System converts: 10 × 50 = 500 kg
- Stock updated: +500 kg

## 🚀 Benefits

1. **Speed**: Receive stock 10x faster by counting cartons instead of individual pieces
2. **Accuracy**: Eliminate manual calculation errors
3. **Flexibility**: Support any product with any unit hierarchy
4. **Transparency**: All conversions are logged in batch notes
5. **Audit Trail**: Complete history of what was received and how

## ⚙️ Configuration Tips

1. **Set realistic conversion factors**: Measure actual product packaging
2. **Use consistent naming**: "box", "pack", "carton" (not "bx", "pk", "ctn")
3. **Don't skip levels**: If you have tertiary, you must have secondary
4. **Document exceptions**: Some products may have non-standard packaging

## 🔄 Migration Script (for existing products)

```sql
-- Add unit configurations for common products
UPDATE products SET
  secondary_unit = 'box',
  secondary_unit_qty = 6.0
WHERE category_id IN (SELECT id FROM categories WHERE name = 'Beverages');

UPDATE products SET
  secondary_unit = 'blister',
  secondary_unit_qty = 10.0,
  tertiary_unit = 'box',
  tertiary_unit_qty = 100.0
WHERE category_id IN (SELECT id FROM categories WHERE name = 'Pharmaceuticals');
```

## 📱 Mobile App Usage

1. **Quick Entry Flow:**
   - Select product → Enter quantity in cartons → See instant conversion → Submit

2. **Multi-Batch Entry:**
   - Receive different batch numbers with different units in one session
   - Example: Batch 1 (5 cartons) + Batch 2 (10 boxes) = 820 pieces total

3. **Visual Feedback:**
   - Green conversion box shows: "5 cartons = 720 pieces"
   - No confusion, no calculator needed

## 🎓 Training Notes

**For Supervisors:**
- "Count the cartons, not the bottles. The app does the math."
- "Each unit selector shows you the conversion automatically."
- "You can mix units - one batch in cartons, another in boxes."

**For Cashiers:**
- "You still sell in pieces. The supervisor receives in cartons."
- "Your POS shows pieces, not cartons."

**For Managers:**
- "All stock is stored in base units for consistency."
- "Reports show pieces, not cartons."
- "Batch notes include original receiving units for reference."

---

**Need Help?** The system auto-detects units from product configuration. If a unit is not configured, the API will return a helpful error message with instructions.
