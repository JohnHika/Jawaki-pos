import '../di/injection.dart';
import '../services/storage_service.dart';

/// The signed-in company's display name, for messages and documents the shop
/// sends to its customers.
String currentShopName() {
  final user = getIt<StorageService>().getUser() ?? {};
  final tenant = user['tenant'];
  final name = tenant is Map ? tenant['name'] : null;
  final text = (name ?? user['companyName'])?.toString().trim();
  return (text == null || text.isEmpty) ? 'our shop' : text;
}
