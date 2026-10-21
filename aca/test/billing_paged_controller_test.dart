import 'dart:async';

import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/features/billing/paged_list.dart';
import 'package:flutter_test/flutter_test.dart';

Paged<int> page(List<int> items, {required int page, required int totalPages, int? total}) => Paged<int>(
      items: items,
      total: total ?? items.length,
      page: page,
      pageSize: items.length,
      totalPages: totalPages,
    );

void main() {
  test('refresh loads page 1 and reports the total', () async {
    final c = PagedController<int>(fetch: (p) async => page([1, 2], page: p, totalPages: 2, total: 4));
    expect(c.isInitialLoading, isTrue);
    await c.refresh();
    expect(c.items, [1, 2]);
    expect(c.total, 4);
    expect(c.hasMore, isTrue);
    expect(c.loadedOnce, isTrue);
    expect(c.isInitialLoading, isFalse);
  });

  test('loadMore appends pages until the last one', () async {
    final pages = {
      1: page([1, 2], page: 1, totalPages: 3, total: 5),
      2: page([3, 4], page: 2, totalPages: 3, total: 5),
      3: page([5], page: 3, totalPages: 3, total: 5),
    };
    final requested = <int>[];
    final c = PagedController<int>(fetch: (p) async {
      requested.add(p);
      return pages[p]!;
    });
    await c.refresh();
    await c.loadMore();
    await c.loadMore();
    expect(c.items, [1, 2, 3, 4, 5]);
    expect(c.hasMore, isFalse);

    await c.loadMore(); // nothing left: no request
    expect(requested, [1, 2, 3]);
  });

  test('an empty page stops paging even if the server claims more', () async {
    var calls = 0;
    final c = PagedController<int>(fetch: (p) async {
      calls++;
      return p == 1 ? page([1], page: 1, totalPages: 9) : page([], page: p, totalPages: 9);
    });
    await c.refresh();
    await c.loadMore();
    expect(c.hasMore, isFalse);
    await c.loadMore();
    expect(calls, 2);
  });

  test('idOf drops rows that are already on screen', () async {
    final c = PagedController<int>(
      idOf: (i) => i,
      fetch: (p) async => p == 1 ? page([1, 2, 3], page: 1, totalPages: 2) : page([3, 4], page: 2, totalPages: 2),
    );
    await c.refresh();
    await c.loadMore();
    expect(c.items, [1, 2, 3, 4]);
  });

  test('a failed first load keeps nothing and exposes the error', () async {
    final c = PagedController<int>(fetch: (p) async => throw ApiException(500, 'boom'));
    await c.refresh();
    expect(c.items, isEmpty);
    expect(c.error, isA<ApiException>());
    expect(c.isInitialLoading, isFalse);
  });

  test('a failed refresh keeps the rows that were already loaded', () async {
    var fail = false;
    final c = PagedController<int>(fetch: (p) async {
      if (fail) throw ApiException(500, 'boom');
      return page([1, 2], page: 1, totalPages: 1);
    });
    await c.refresh();
    fail = true;
    await c.refresh();
    expect(c.items, [1, 2]);
    expect(c.error, isNotNull);
  });

  test('a failed loadMore is remembered, not retried automatically, and retryMore recovers', () async {
    var fail = true;
    var calls = 0;
    final c = PagedController<int>(fetch: (p) async {
      calls++;
      if (p == 2 && fail) throw ApiException(500, 'boom');
      return p == 1 ? page([1], page: 1, totalPages: 2) : page([2], page: 2, totalPages: 2);
    });
    await c.refresh();
    await c.loadMore();
    expect(c.moreError, isNotNull);
    expect(c.items, [1]);

    await c.loadMore(); // blocked while the error stands
    expect(calls, 2);

    fail = false;
    await c.retryMore();
    expect(c.moreError, isNull);
    expect(c.items, [1, 2]);
  });

  test('a response for an old filter never overwrites the new one', () async {
    final first = Completer<Paged<int>>();
    final second = Completer<Paged<int>>();
    final queue = [first, second];
    final c = PagedController<int>(fetch: (p) => queue.removeAt(0).future);

    final a = c.refresh(clear: true); // old filter
    final b = c.refresh(clear: true); // new filter, started later
    second.complete(page([20], page: 1, totalPages: 1));
    await b;
    first.complete(page([10], page: 1, totalPages: 1)); // arrives late
    await a;

    expect(c.items, [20]);
  });

  test('refresh(clear: true) empties the list while loading', () async {
    final gate = Completer<Paged<int>>();
    var first = true;
    final c = PagedController<int>(fetch: (p) {
      if (first) {
        first = false;
        return Future.value(page([1, 2], page: 1, totalPages: 1));
      }
      return gate.future;
    });
    await c.refresh();
    final reload = c.refresh(clear: true);
    expect(c.items, isEmpty);
    expect(c.isInitialLoading, isTrue);
    gate.complete(page([9], page: 1, totalPages: 1));
    await reload;
    expect(c.items, [9]);
  });

  test('disposing mid-request does not throw', () async {
    final gate = Completer<Paged<int>>();
    final c = PagedController<int>(fetch: (p) => gate.future);
    final f = c.refresh();
    c.dispose();
    gate.complete(page([1], page: 1, totalPages: 1));
    await f;
  });
}
