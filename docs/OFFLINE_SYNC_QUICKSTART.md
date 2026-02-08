# 🚀 Quick Start: Offline Sync Queue

## 🔧 Installation (5 Minutes)

### Backend

```bash
cd backend
npx prisma db push
npx prisma generate
```

### Mobile

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

---

## 📝 Initialize in main.dart

```dart
import 'package:workmanager/workmanager.dart';
import 'core/services/background_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSyncService.initialize();
  runApp(MyApp());
}
```

---

## ✅ Usage Example

```dart
// Queue a sale for sync
await syncService.queueSyncItem(
  tableName: 'sales',
  recordId: sale.id,
  action: SyncAction.create,
  data: sale.toJson(),
  deviceId: deviceId,
  userId: userId,
);

// Check sync stats
final stats = await syncService.getSyncStats();
print('Pending: ${stats['pending']}, Failed: ${stats['failed']}');

// Retry failures
await syncService.retryFailedItems();
```

---

## 🎯 What You Get

✅ Background sync every 15 minutes  
✅ Up to 3 automatic retries  
✅ Smart conflict resolution  
✅ Zero data loss  
✅ Complete audit trail  

---

**Need Help?** See [OFFLINE_SYNC_QUEUE_GUIDE.md](OFFLINE_SYNC_QUEUE_GUIDE.md) for full documentation.
