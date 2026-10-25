import 'dart:async';

import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('products can reach the cache while category refresh is still pending',
      () async {
    final categories = Completer<void>();
    var productsCached = false;
    var syncCompleted = false;

    final sync = syncCatalogSources(
      syncCategories: () => categories.future,
      syncProducts: () async {
        productsCached = true;
      },
    ).then((_) => syncCompleted = true);

    await Future<void>.delayed(Duration.zero);
    expect(productsCached, isTrue);
    expect(syncCompleted, isFalse);

    categories.complete();
    await sync;
    expect(syncCompleted, isTrue);
  });

  test('category refresh failure does not discard successfully cached products',
      () async {
    var productsCached = false;

    await syncCatalogSources(
      syncCategories: () async => throw StateError('category service offline'),
      syncProducts: () async {
        productsCached = true;
      },
    );

    expect(productsCached, isTrue);
  });

  test('product refresh failure remains visible to the retry state', () async {
    await expectLater(
      syncCatalogSources(
        syncCategories: () async {},
        syncProducts: () async => throw StateError('product service offline'),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
