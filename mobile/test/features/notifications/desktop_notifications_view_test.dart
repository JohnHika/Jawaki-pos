import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/notifications/domain/app_notification.dart';
import 'package:axon_pos/features/notifications/presentation/desktop/desktop_notifications_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

DateTime _ago({int minutes = 0, int hours = 0, int days = 0}) => DateTime.now()
    .subtract(Duration(minutes: minutes, hours: hours, days: days));

AppNotification _n(
  String id,
  String type,
  String title,
  String body,
  DateTime at, {
  bool unread = true,
  Map<String, dynamic> data = const {},
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      data: data,
      createdAt: at,
      readAt: unread ? null : at,
    );

List<AppNotification> _sample() => [
      _n('1', 'partner_request', 'Wanjiku Cereals Ltd wants to connect',
          'They supply maize flour and rice to shops in Kiambu and would like to supply you too.',
          _ago(minutes: 12), data: {'partnershipId': 'p5'}),
      _n('2', 'partner_message', 'Kamau Wholesalers',
          'We can deliver the 50 bags of sugar on Thursday morning.',
          _ago(hours: 1), data: {'partnershipId': 'p1'}),
      _n('3', 'partner_message', 'Mama Njeri Fresh Produce',
          'Thank you, payment received.', _ago(hours: 30),
          unread: false, data: {'partnershipId': 'p2'}),
      _n('4', 'low_stock_alert', '3 products are running low',
          'Cooking oil 1L, Maize flour 2kg and Fresh milk 500ml are at or below their reorder level.',
          _ago(hours: 2)),
      _n('5', 'restock_suggestion', 'Restock list ready',
          'Based on the last 14 days, order 6 items to stay stocked for the week. Estimated cost KES 18,400.',
          _ago(hours: 5)),
      _n('6', 'stock_request_resolved', 'Stock request approved',
          'Your request for 24 x Sugar 2kg from the Westlands branch was approved.',
          _ago(days: 2), unread: false),
      _n('7', 'accountability_alert', 'Sale below cost',
          'Brian sold Blue Band 500g for KES 180. Cost is KES 205.',
          _ago(hours: 3)),
      _n('8', 'eod_reminder', 'Time to close the day',
          'Count the till and record end of day for today.', _ago(hours: 4),
          unread: false),
      _n('9', 'business_news', 'Fuel prices go up from midnight',
          'EPRA has raised pump prices by KES 4.20 a litre.', _ago(days: 1)),
      _n('10', 'desktop_link_request', 'A computer wants to link',
          'Counterbase on DESKTOP-4F2K asked to sign in to this shop.',
          _ago(days: 3)),
    ];

class _Harness extends StatefulWidget {
  const _Harness({
    required this.items,
    this.loadedOnce = true,
    this.error,
    this.initialSelected,
    this.log,
  });

  final List<AppNotification> items;
  final bool loadedOnce;
  final String? error;
  final String? initialSelected;
  final List<String>? log;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<AppNotification> _items = widget.items;
  late String? _selected = widget.initialSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesktopNotificationsView(
        items: _items,
        unreadCount: _items.where((n) => n.isUnread).length,
        loadedOnce: widget.loadedOnce,
        error: widget.error,
        selectedId: _selected,
        onSelect: (n) => setState(() {
          _selected = n?.id;
          if (n != null) {
            _items = [
              for (final i in _items) if (i.id == n.id) i.markedRead() else i,
            ];
          }
        }),
        onOpen: (n) => widget.log?.add('open ${n.id}'),
        onMarkAllRead: () => setState(() {
          _items = [for (final i in _items) i.markedRead()];
        }),
        onRetry: () => widget.log?.add('retry'),
        canAct: (n) => n.type == 'partner_request',
        onAccept: (n) => widget.log?.add('accept ${n.id}'),
        onDecline: (n) => widget.log?.add('decline ${n.id}'),
      ),
    );
  }
}

Widget _app(Widget home, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DesktopTheme.of(base),
    home: boundary == null ? home : ShotFrame(boundaryKey: boundary, child: home),
  );
}

const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
  '1920': Size(1688, 1012),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('inbox $theme ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(
          _Harness(items: _sample(), initialSelected: '1'),
          dark: dark,
          boundary: key,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/inbox-notifications-$theme-${entry.key}.png');
      });
    }
  }

  testWidgets('groups the list by what the notification is about',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(items: _sample())));
    await tester.pumpAndSettle();
    for (final label in ['Partners', 'Stock', 'Shop alerts']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.scrollUntilVisible(find.text('Devices'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Select a notification'), findsOneWidget);
  });

  testWidgets('a partner request is accepted in place, in the row or the detail',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(_app(_Harness(items: _sample(), log: log)));
    await tester.pumpAndSettle();
    // The row has its own buttons before anything is opened.
    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(log, ['accept 1']);

    await tester.tap(find.text('Wanjiku Cereals Ltd wants to connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline').last);
    expect(log, ['accept 1', 'decline 1']);
  });

  testWidgets('selecting marks it read; the action button opens the screen',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(_app(_Harness(items: _sample(), log: log)));
    await tester.pumpAndSettle();
    expect(find.text('7 unread'), findsOneWidget);

    await tester.tap(find.text('Restock list ready'));
    await tester.pumpAndSettle();
    expect(find.text('6 unread'), findsOneWidget);
    await tester.tap(find.text('Open stock'));
    expect(log, ['open 5']);
  });

  testWidgets('Mark all read clears the badge; Unread filter narrows the list',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(items: _sample())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unread').first);
    await tester.pumpAndSettle();
    expect(find.text('Time to close the day'), findsNothing);
    expect(find.text('Sale below cost'), findsOneWidget);

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(find.text('You are all caught up'), findsOneWidget);
    expect(find.text('Nothing unread.'), findsOneWidget);
  });

  testWidgets('arrow keys move through the list', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(items: _sample(), initialSelected: '1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kamau Wholesalers'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // Partners group is newest first: request, Kamau, Mama Njeri.
    expect(find.text('Open conversation'), findsOneWidget);
  });

  testWidgets('empty, loading and error states', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(items: [])));
    await tester.pumpAndSettle();
    expect(find.text("You're all caught up"), findsOneWidget);

    final key = GlobalKey();
    await tester.pumpWidget(_app(
      const _Harness(items: [], error: 'Could not refresh notifications.'),
      boundary: key,
    ));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load notifications"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/inbox-notifications-error-light-1366.png');

    await tester.pumpWidget(_app(const _Harness(items: [], loadedOnce: false)));
    await tester.pump();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
