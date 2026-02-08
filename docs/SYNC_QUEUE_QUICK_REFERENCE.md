# 🎯 Offline Sync Queue - Quick Reference Card

## 📱 Mobile (Flutter) - Quick Commands

### Queue a Sync Item
```dart
await syncService.queueSyncItem(
  tableName: 'sales',
  recordId: sale.id,
  action: SyncAction.create,
  data: sale.toJson(),
  deviceId: deviceId,
  userId: userId,
);
```

### Check Sync Status
```dart
final stats = await syncService.getSyncStats();
// Returns: { 'pending': 5, 'synced': 120, 'failed': 2, 'total': 127 }
```

### Retry Failed Items
```dart
await syncService.retryFailedItems();
```

### Trigger Immediate Sync
```dart
await BackgroundSyncService.triggerImmediateSync();
```

---

## 🖥️ Backend (NestJS) - Quick Commands

### Query Conflict Logs
```sql
-- Recent conflicts
SELECT * FROM conflict_logs ORDER BY created_at DESC LIMIT 20;

-- Manual resolution needed
SELECT * FROM conflict_logs WHERE resolution = 'MANUAL';

-- Conflicts by type
SELECT conflict_type, COUNT(*) 
FROM conflict_logs 
GROUP BY conflict_type;
```

### Monitor Sync Events
```sql
-- Failed sync events
SELECT * FROM sync_events 
WHERE status = 'FAILED' 
ORDER BY created_at DESC;

-- Retry count distribution
SELECT retry_count, COUNT(*) 
FROM sync_events 
GROUP BY retry_count;
```

---

## 🔧 Deployment Commands

### Backend
```bash
cd backend
npx prisma db push
npx prisma generate
npm run start:dev
```

### Mobile
```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --release
```

---

## 🚨 Troubleshooting

### Sync Not Running?
```dart
// Check if workmanager initialized
await BackgroundSyncService.initialize();
```

### Database Migration Issues?
```bash
# Mobile: Reset database (DEV ONLY)
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Backend: Reset migrations (DEV ONLY)
npx prisma migrate reset
npx prisma db push
```

### Check Pending Items
```dart
final pending = await database.getPendingSyncQueue();
print('${pending.length} items waiting to sync');
```

---

## 📊 Sync States

| Status | Meaning | Action |
|--------|---------|--------|
| `pending` | Waiting to sync | Automatic (every 15 min) |
| `synced` | Successfully synced | None (cleanup after 30 days) |
| `failed` | Max retries exceeded | Manual: "Retry Failed" button |

---

## 🎯 Conflict Resolutions

| Resolution | When | Result |
|------------|------|--------|
| SERVER_WINS | Deleted on server, pricing changes | Server data used |
| CLIENT_WINS | Newer timestamp, no conflicts | Client data used |
| MERGE | Non-conflicting field changes | Smart merge |
| MANUAL | Conflicting changes | User resolves |

---

## ⚙️ Configuration

### Sync Frequency
```dart
// mobile/lib/core/services/background_sync_service.dart
static const Duration syncInterval = Duration(minutes: 15); // Adjust here
```

### Max Retries
```dart
// mobile/lib/core/database/app_database.dart
maxRetries: const Value(3), // Change default here
```

### Retry Delays
```dart
// mobile/lib/core/services/background_sync_service.dart
static const List<int> retryDelays = [5, 15, 60]; // [5s, 15s, 1min]
```

---

## 📱 User Notifications

### Show Sync Status
```dart
final stats = await syncService.getSyncStats();
showSnackBar('${stats['pending']} items pending sync');
```

### Alert on Failures
```dart
if (stats['failed']! > 0) {
  showDialog(
    title: 'Sync Failed',
    message: '${stats['failed']} items failed. Tap to retry.',
    onRetry: () => syncService.retryFailedItems(),
  );
}
```

---

## 🔐 Permissions (Android)

### AndroidManifest.xml
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

---

## 📦 Dependencies

### pubspec.yaml
```yaml
dependencies:
  drift: ^2.14.1
  workmanager: ^0.5.2
  uuid: ^4.2.2
  connectivity_plus: ^5.0.2
```

---

## 🎓 Training Scripts

### For Cashiers
> "When you make a sale offline, it's saved on this device. Every 15 minutes, we automatically send it to the main server. If the internet is down, we keep trying. You'll get a notification if we can't sync after 3 tries - just tap 'Retry' and we'll try again."

### For Managers
> "Check the Sync Status dashboard to see pending syncs. If you see 'Failed' items, review them in the Conflicts section. Most conflicts auto-resolve, but some need your decision - choose which version to keep."

---

## 🚀 Performance Tips

1. **Cleanup regularly**: `cleanupSyncQueue(olderThanDays: 30)`
2. **Monitor failures**: Alert if >10% fail rate
3. **Batch operations**: Sync in batches of 100 items
4. **Compress payloads**: Use gzip for large data
5. **Index queries**: Ensure indexes on status, tableName

---

## 📞 Emergency Contacts

| Issue | Action |
|-------|--------|
| All syncs failing | Check backend logs, restart server |
| Conflicts piling up | Review merge rules, contact IT support |
| Database locked | Close other sessions, restart app |
| Battery drain | Check workmanager frequency, reduce to 30 min |

---

**Keep this card handy for daily operations! 📌**

*Last Updated: 2024*
