import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart' show AppDatabase, Product;
import '../../../../core/desktop/adaptive_overlays.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/utils/api_message.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    as catalog_cache;
import '../screens/product_detail_screen.dart' show CorrectCountSheet;

/// "Correct count" as a dialog, for the desktop inspector and the row menu.
Future<void> showCorrectCountDialog(
  BuildContext context, {
  required Product product,
  required double current,
}) async {
  final saved = await showAdaptiveSheet<bool>(
    context: context,
    builder: (sheet) => CorrectCountSheet(
      product: product,
      current: current,
      showHandle: false,
    ),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Count corrected. It is in the history.')),
    );
  }
}

/// Asks, then removes the product from the catalogue (or brings a removed one
/// back). Returns an error sentence to show, or null when it worked or the
/// person changed their mind.
Future<String?> confirmAndToggleRemoved(
  BuildContext context,
  WidgetRef ref,
  Product product,
) async {
  final isLocal = getIt<AuthService>().isLocalWorkspace;
  final bringBack = isLocal && !product.isActive;
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        bringBack ? 'Bring back ${product.name}?' : 'Remove ${product.name}?',
      ),
      content: Text(
        bringBack
            ? 'It shows on Sell and in the list again.'
            : isLocal
                ? 'It stops showing on Sell and in the list. Past sales and receipts keep its name. You can bring it back with the Removed filter.'
                : 'This removes it from the catalog.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(bringBack ? 'Cancel' : 'Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: bringBack
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC0392B),
                  foregroundColor: Colors.white,
                ),
          child: Text(bringBack ? 'Bring it back' : 'Remove product'),
        ),
      ],
    ),
  );
  if (go != true) return null;
  try {
    if (isLocal) {
      await getIt<AppDatabase>()
          .setLocalProductActive(product.id, isActive: bringBack);
    } else {
      await getIt<ApiClient>().deleteProduct(product.id);
      await catalog_cache.deleteProductFromCache(product.id);
    }
    ref.invalidate(catalog_cache.filteredProductsProvider);
    ref.invalidate(catalog_cache.favoriteProductsProvider);
    ref.invalidate(catalog_cache.categoriesProvider);
    return null;
  } catch (e) {
    return 'Could not update the product. ${apiErrorMessage(e)}';
  }
}
