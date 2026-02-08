# Batch & Expiry Tracking - Quick Reference

## For Stock Keepers

### Receiving New Medicine Stock

1. **Login** with SUPERVISOR credentials
2. **Navigate** to Inventory → Receive Batch
3. **Select Product** (e.g., Panadol 500mg)
4. **Enter Batch Information**:
   - Batch Number: (from package label)
   - Quantity: (units received)
   - Expiry Date: (from package)
   - Manufacture Date: (optional)
   - Cost Price: (per unit)
   - Supplier Reference: (invoice number)
   - Notes: (any special observations)
5. **Save** - System will automatically update stock

### Important Rules
- ✅ Always enter expiry date for medicines
- ✅ Use exact batch number from supplier
- ✅ Double-check expiry date (critical!)
- ❌ Don't receive items already expired

---

## For Cashiers (POS)

### Making Sales

The system **automatically**:
- ✅ Allocates stock from batches expiring soonest (FEFO)
- ✅ Blocks expired batches from sale
- ✅ Shows error if only expired stock available

### What You'll See

**Normal Sale:**
```
✓ Panadol 500mg added to cart
  Allocated from Batch: BATCH-2026-001
  Expires: Dec 31, 2026
```

**Blocked Sale (Expired):**
```
✗ Cannot sell Panadol 500mg
  Reason: All available batches are expired
  Action: Contact supervisor
```

### If Sale is Blocked
1. **DO NOT override** - expired medicine is dangerous
2. **Notify supervisor** immediately
3. **Remove item** from customer order
4. **Suggest alternative** product if available

---

## For Store Managers

### Daily Expiry Dashboard Review

**Access:** Dashboard → Expiry Management

### Color Zones

| Zone | Meaning | Action |
|------|---------|--------|
| 🔴 **RED** | Expired | Block from sale, arrange disposal |
| 🟠 **ORANGE** (30 days) | Critical | Clearance sale 20-30% off |
| 🟡 **YELLOW** (60 days) | Warning | Promote, bundle deals |
| 🟢 **GREEN** (90 days) | Caution | Monitor, plan promotions |

### Weekly Tasks

**Monday Morning:**
1. Check expiry dashboard
2. Review expiring items (30-day zone)
3. Plan clearance promotions
4. Update POS with promotional pricing

**Friday Afternoon:**
5. Review week's expiry movements
6. Block any expired batches
7. Submit disposal request for expired items
8. Update inventory reports

### Monthly Audit

- [ ] Physical count vs system batches
- [ ] Verify expiry dates match labels
- [ ] Review blocked batches
- [ ] Generate compliance report
- [ ] Train new staff on procedures

---

## For System Administrators

### Daily Cron Job

**Schedule:** Run at 00:30 (12:30 AM) daily

```bash
# Auto-block expired batches
curl -X POST https://api.jawaki.com/v1/inventory/batches/block-expired \
  -H "Authorization: Bearer ${ADMIN_TOKEN}"
```

### Weekly Maintenance

**Database Cleanup:**
```sql
-- Archive old stock movements (older than 2 years)
INSERT INTO stock_movements_archive 
SELECT * FROM stock_movements 
WHERE createdAt < NOW() - INTERVAL '2 years';

DELETE FROM stock_movements 
WHERE createdAt < NOW() - INTERVAL '2 years';
```

### Alerts Configuration

**Email Alerts:**
- Expired batches detected → managers@jawaki.com
- Items expiring in 7 days → inventory@jawaki.com
- Failed batch allocation → tech@jawaki.com

### Monitoring Queries

**Check System Health:**
```sql
-- Count expired batches
SELECT COUNT(*) as expired_count
FROM stock_batches
WHERE expiryDate < NOW() AND isBlocked = false;

-- Total value at risk (expiring in 30 days)
SELECT SUM(quantity * costPrice) as value_at_risk
FROM stock_batches
WHERE expiryDate BETWEEN NOW() AND NOW() + INTERVAL '30 days';

-- Products without batches (should be 0)
SELECT COUNT(*) as unbatched_products
FROM stock s
LEFT JOIN stock_batches sb ON s.id = sb.stockId
WHERE s.quantity > 0 AND sb.id IS NULL;
```

---

## API Quick Reference

### Receive Batch
```http
POST /v1/inventory/batches/receive
{
  "branchId": "xxx",
  "productId": "xxx",
  "batches": [{
    "batchNumber": "BATCH-001",
    "quantity": 100,
    "expiryDate": "2026-12-31"
  }]
}
```

### View Stock with Batches
```http
GET /v1/inventory/batches/{branchId}/{productId}
```

### Expiry Dashboard
```http
GET /v1/inventory/expiry-dashboard?branchId=xxx&zone=30days
```

### Block Expired Batches
```http
POST /v1/inventory/batches/block-expired
```

---

## Keyboard Shortcuts (Future)

| Action | Shortcut |
|--------|----------|
| Receive Batch | `Alt + R` |
| View Batches | `Alt + B` |
| Expiry Dashboard | `Alt + E` |
| Block Batch | `Alt + X` |

---

## Emergency Procedures

### If System Blocks All Sales

**Cause:** All batches expired or blocked

**Solution:**
1. Check expiry dashboard
2. Verify physical stock expiry dates
3. If dates are valid in database, unblock batch:
   ```http
   PUT /v1/inventory/batches/{batchId}
   { "isBlocked": false }
   ```
4. If physically expired → DO NOT unblock, contact manager

### If Wrong Batch Sold

**Within 24 hours:**
1. Note sale ID and batch number
2. Contact admin immediately
3. Admin can trace via audit log:
   ```sql
   SELECT * FROM sale_item_batches
   WHERE saleId = 'xxx';
   ```
4. If product recalled, contact all affected customers

---

## Compliance & Regulations

### Kenya Pharmacy and Poisons Board Requirements

✅ **Track batch numbers** - Implemented  
✅ **Record expiry dates** - Implemented  
✅ **Prevent expired sales** - Automated  
✅ **Maintain audit trail** - Full traceability  
✅ **Traceability** - Batch → Sale linking  

### Audit Reports

**Generate Compliance Report:**
```http
GET /v1/reports/batch-compliance?startDate=2024-01-01&endDate=2024-12-31
```

---

## Support Contacts

- **Technical Issues**: tech@jawaki.com
- **System Admin**: admin@jawaki.com
- **Store Manager**: manager@jawaki.com
- **Emergency**: +254-XXX-XXXX

---

**Last Updated:** February 8, 2026  
**Version:** 1.0.0  
**Document Owner:** IT Department
