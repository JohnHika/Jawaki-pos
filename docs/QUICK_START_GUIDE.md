# Quick Start Guide - New Features

## 🚀 How to Use Stock Requests & Multi-Unit Inventory

### Prerequisites

1. **Backend Setup** (One-time)
```bash
cd backend
npx prisma migrate dev --name add_stock_requests_and_units
npx prisma generate
npm run start:dev
```

2. **Mobile Setup** (One-time)
```bash
cd mobile
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

3. **Run the App**
```bash
# Connect device
flutter devices

# Run on device
flutter run
```

---

## 📦 Feature 1: Stock Request System

### For Cashiers/Sellers

**When to Use**: You notice a product is running low and need to request more stock.

**Steps**:
1. Open the app and log in
2. Navigate to **Inventory**
3. Tap **"Request Stock"** button (will be added to UI)
4. Select the product you need
5. Enter quantity needed
6. Choose priority:
   - 🟢 **Low** - Can wait a few days
   - 🟡 **Normal** - Regular restock (default)
   - 🟠 **High** - Need soon
   - 🔴 **Urgent** - Critical, need ASAP
7. (Optional) Add a reason explaining why you need it
8. Tap **Submit Request**
9. ✅ Done! Manager will be notified

**Example**:
```
Product: Coca-Cola 500ml
Quantity: 100 pieces
Priority: High
Reason: Weekend rush expected, current stock only 20 pieces
```

### For Managers/Supervisors

**When to Use**: Review and approve stock requests from cashiers.

**Steps**:
1. Open the app and log in
2. Navigate to **Inventory** → **Stock Requests**
3. You'll see 4 tabs:
   - **Pending** - New requests waiting for approval
   - **Approved** - Requests you've approved
   - **Fulfilled** - Requests that have been completed
   - **All** - Everything
4. Tap on any request to see details:
   - Who requested it
   - Current stock level
   - Quantity needed
   - Priority level
   - Reason (if provided)
5. Take action:
   - ✅ **Approve** - If you agree with the request
   - ❌ **Reject** - If denied (add reason)
   - 📦 **Fulfill** - Mark as completed after receiving stock

**Smart Features**:
- 🔴 Red badge = Urgent priority
- 🟡 Yellow = Low stock warning
- Pull down to refresh
- Filter by branch (multi-branch setups)

---

## 📊 Feature 2: Multi-Unit Inventory

### For Supervisors (Receiving Stock)

**When to Use**: Receiving shipment in cartons/boxes instead of counting individual pieces.

**Problem Solved**: 
- Before: "I received 50 cartons, each has 144 pieces... that's 7,200 pieces" 🧮
- Now: "I received 50 cartons" → System auto-calculates 7,200 pieces ✨

**Steps**:
1. Navigate to **Inventory** → **Receive Batch**
2. Select the product
3. System shows available units (e.g., piece, box, carton)
4. For each batch:
   - Enter batch number (e.g., "BTH-2024-001")
   - Enter quantity (e.g., 50)
   - **Select unit** (piece/box/carton)
   - See instant conversion: **"= 7,200 pieces"**
   - Add expiry date (required)
   - (Optional) Add manufacture date, cost price, supplier ref, notes
5. Need more batches? Tap **+ Add Another Batch**
6. Review summary at bottom
7. Tap **Receive Batches**
8. ✅ Stock automatically updated in pieces!

**Example Scenario**:

```
Product: Coca-Cola 500ml
Unit Configuration:
  - Base: piece (individual bottle)
  - Box: 12 pieces
  - Carton: 144 pieces (12 boxes)

Receiving:
  Batch 1:
    - Batch Number: BTH-2024-001
    - Quantity: 10
    - Unit: Carton ← Select from dropdown
    - Live Preview: "= 1,440 pieces" ✨
    - Expiry: 2025-12-31
    
  Batch 2:
    - Batch Number: BTH-2024-002
    - Quantity: 5
    - Unit: Box
    - Live Preview: "= 60 pieces"
    - Expiry: 2025-11-30

Total Received: 1,500 pieces (10 cartons + 5 boxes)
```

**Benefits**:
- ⚡ **10x Faster**: Count cartons, not pieces
- ✅ **Zero Math Errors**: System calculates automatically
- 📝 **Audit Trail**: Notes show "Received 10 carton = 1,440 piece"
- 🎯 **Accurate**: No more miscounts

### For Admins (Configuring Product Units)

**When to Use**: Setting up conversion factors for a product.

**Steps** (UI to be built):
1. Go to **Products**
2. Select a product → **Edit**
3. Scroll to **Unit Configuration** section
4. Fill in:
   - Base Unit: `piece` (required)
   - Secondary Unit: `box` (optional)
   - Secondary Qty: `12` (how many pieces per box)
   - Tertiary Unit: `carton` (optional)
   - Tertiary Qty: `144` (how many pieces per carton)
5. Save
6. ✅ Now supervisors can receive in boxes/cartons!

**Common Examples**:

**Beverages**:
```
Base: bottle
Secondary: pack (6 bottles)
Tertiary: crate (24 bottles)
```

**Pharmaceuticals**:
```
Base: tablet
Secondary: blister (10 tablets)
Tertiary: box (100 tablets)
```

**Groceries**:
```
Base: kg
Secondary: bag (5 kg)
Tertiary: sack (50 kg)
```

**Electronics**:
```
Base: piece
Secondary: box (1 piece + accessories)
Tertiary: carton (10 boxes)
```

---

## 🎓 Training Tips

### For Cashiers
- "If stock is low, request it immediately"
- "Use HIGH priority for fast-moving items"
- "Add a reason to help manager understand urgency"
- "Check pending tab to see your request status"

### For Supervisors
- "Count the cartons, not the bottles - the app does the math"
- "Always double-check the unit dropdown before submitting"
- "Use the conversion preview to verify quantities"
- "Add supplier reference for tracking"

### For Managers
- "Check pending requests twice daily"
- "Approve urgent requests first (red badge)"
- "Add resolution notes when rejecting"
- "Use stats to identify request patterns"

---

## ❓ FAQs

**Q: Can I edit a request after submitting?**
A: Yes, but only while it's PENDING. Once approved/rejected, no edits allowed.

**Q: What if I don't know the conversion factor?**
A: Check the product packaging or ask your supplier. Common: 1 carton = 12 boxes = 144 pieces.

**Q: Can I receive in different units for the same product?**
A: Yes! Batch 1 in cartons, Batch 2 in boxes - all converted to pieces automatically.

**Q: What happens to old stock receiving?**
A: Still works! Just use "piece" as the unit and enter total pieces.

**Q: Do I need internet connection?**
A: For submitting requests: Yes (syncs to server)
For receiving stock: Yes (fetches conversion config)
Local stock viewing: No (works offline)

---

## 🐛 Troubleshooting

**Problem**: "No branch ID found"
**Solution**: Log out and log in again

**Problem**: Unit dropdown is empty
**Solution**: Product not configured with secondary/tertiary units. Use "piece" only.

**Problem**: Request not appearing in list
**Solution**: Pull down to refresh, or check the "All" tab

**Problem**: "Error receiving batches"
**Solution**: Check internet connection, verify all required fields filled

---

## 📞 Support

Need help? Contact your system administrator or refer to:
- Full documentation: `docs/MULTI_UNIT_INVENTORY_GUIDE.md`
- Technical details: `docs/API_INTEGRATION_SUMMARY.md`

---

**Last Updated**: February 8, 2026  
**Version**: 1.0.0
