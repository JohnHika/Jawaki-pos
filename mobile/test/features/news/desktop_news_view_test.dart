import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/news/domain/news_models.dart';
import 'package:axon_pos/features/news/presentation/desktop/desktop_news_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

DateTime _ago({int hours = 0, int days = 0}) =>
    DateTime.now().subtract(Duration(hours: hours, days: days));

NewsItem _news(
  String id,
  String title,
  String category,
  String source,
  DateTime at, {
  String impact = 'LOW',
  String? summary,
}) =>
    NewsItem(
      id: id,
      source: source,
      title: title,
      url: 'https://example.co.ke/$id',
      publishedAt: at,
      category: category,
      impact: impact,
      summary: summary,
    );

final _urgent = [
  _news('u1', 'KRA moves to monthly turnover tax returns for small traders',
      'CUSTOMS_TAX', 'Business Daily', _ago(hours: 6),
      impact: 'HIGH',
      summary:
          'Traders below the VAT threshold will file turnover tax every month instead of quarterly from January. Late filing attracts a 5% penalty.'),
];

final _items = [
  _news('n1', 'Pump prices go up by KES 4.20 a litre from midnight', 'LOGISTICS',
      'The Star', _ago(hours: 3),
      summary: 'EPRA announced new maximum retail prices for Nairobi: super petrol KES 189.40, diesel KES 171.20.'),
  _news('n2', 'Shilling steady against the dollar as importers cover year-end orders',
      'MONEY_FX', 'Nation', _ago(hours: 9),
      summary: 'The shilling traded at 129.3 to the dollar, supported by diaspora inflows.'),
  _news('n3', 'Nairobi county to relocate Gikomba second-hand clothes traders', 'COUNTY_LICENSING',
      'Capital FM', _ago(days: 1)),
  _news('n4', 'Sugar import duty waiver extended by 60 days', 'TRADE_IMPORT',
      'Business Daily', _ago(days: 1, hours: 5),
      summary: 'The waiver covers up to 100,000 tonnes and should ease wholesale prices in December.'),
  _news('n5', 'Maize flour prices drop as new harvest reaches millers', 'MARKET',
      'Citizen Digital', _ago(days: 2),
      summary: 'A 2kg packet now sells for between KES 118 and KES 130 at wholesale.'),
  _news('n6', 'Why a very long headline from a regional paper should still stay on one line in the table row at a small laptop width',
      'MARKET', 'Taifa Leo', _ago(days: 3)),
];

const _rates = RateBoard(
  rates: {'USD': 129.3, 'CNY': 17.9, 'AED': 35.2, 'EUR': 140.8},
  disclaimer: 'Indicative mid-market rates, not what a bank will pay you.',
);

const _links = [
  OfficialLink(
    name: 'KRA',
    url: 'https://www.kra.go.ke',
    about: 'Tax rules, returns and payment',
  ),
  OfficialLink(
    name: 'EPRA',
    url: 'https://www.epra.go.ke',
    about: 'Fuel pump prices',
  ),
];

class _Harness extends StatefulWidget {
  const _Harness({
    this.items,
    this.urgent,
    this.error,
    this.initialSelected,
    this.log,
  });

  final List<NewsItem>? items;
  final List<NewsItem>? urgent;
  final String? error;
  final String? initialSelected;
  final List<String>? log;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String? _category;
  late String? _selected = widget.initialSelected;

  @override
  Widget build(BuildContext context) {
    final all = widget.items ?? _items;
    final items = _category == null
        ? all
        : all.where((n) => n.category == _category).toList();
    return Scaffold(
      body: DesktopNewsView(
        title: 'Business news',
        items: items,
        urgent: _category == null ? (widget.urgent ?? _urgent) : const [],
        loading: false,
        error: widget.error,
        onRetry: () => widget.log?.add('retry'),
        rates: _rates,
        links: _links,
        category: _category,
        onCategory: (c) => setState(() {
          _category = c;
          _selected = null;
        }),
        selectedId: _selected,
        onSelect: (n) => setState(() => _selected = n?.id),
        onOpenArticle: (n) => widget.log?.add('open ${n.id}'),
        onRefresh: () => widget.log?.add('refresh'),
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
      testWidgets('news $theme ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(
          const _Harness(initialSelected: 'u1'),
          dark: dark,
          boundary: key,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/inbox-news-$theme-${entry.key}.png');
      });
    }
  }

  testWidgets('urgent headlines are pinned first and flagged', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness()));
    await tester.pumpAndSettle();
    expect(find.text('Urgent'), findsOneWidget);
    final urgentY = tester.getTopLeft(find.text('KRA moves to monthly turnover tax returns for small traders')).dy;
    final firstY = tester.getTopLeft(find.text('Pump prices go up by KES 4.20 a litre from midnight')).dy;
    expect(urgentY, lessThan(firstY));
  });

  testWidgets('a topic chip narrows the table; a row opens the inspector',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(_app(_Harness(log: log)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money & rates').first);
    await tester.pumpAndSettle();
    expect(find.text('Pump prices go up by KES 4.20 a litre from midnight'), findsNothing);
    await tester.tap(find.textContaining('Shilling steady'));
    await tester.pumpAndSettle();
    expect(find.text('Read the original article'), findsOneWidget);
    await tester.tap(find.text('Read the original article'));
    expect(log, ['open n2']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Read the original article'), findsNothing);
  });

  testWidgets('an official source opens in the inspector as a website',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KRA'));
    await tester.pumpAndSettle();
    expect(find.text('Open the website'), findsOneWidget);
    expect(find.text('Tax rules, returns and payment'), findsOneWidget);
  });

  testWidgets('no headlines yet says what shows up here', (tester) async {
    useWindow(tester, _sizes['1093']!);
    await tester.pumpWidget(_app(const _Harness(items: [], urgent: [])));
    await tester.pumpAndSettle();
    expect(find.text('No news here yet'), findsOneWidget);
  });

  testWidgets('a failed load keeps the page and offers Try again',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(
      const _Harness(items: [], urgent: [], error: 'No connection. Check the internet and try again.'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
  });
}
