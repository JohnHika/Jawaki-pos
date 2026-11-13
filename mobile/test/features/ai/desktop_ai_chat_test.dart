import 'package:axon_pos/core/desktop/desktop_chat_composer.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/providers/tenant_provider.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/ai/presentation/desktop/desktop_ai_chat.dart';
import 'package:axon_pos/features/ai/presentation/screens/ai_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

const _reply = '''Here is how the shop is doing today.

**Sales so far: KES 48,250** across 63 receipts. That is about 12% up on last Tuesday.

- M-Pesa took 31,400 and cash took 16,850
- Best seller: Sugar 2kg (41 sold)
- 3 products are at or below their reorder level: Cooking oil 1L, Maize flour 2kg, Fresh milk 500ml

Maize flour 2kg will run out tomorrow at this pace. Do you want a reorder list within a KES 20,000 budget?''';

const _longQuestion =
    'Which of my debtors have gone more than 30 days without paying, and how much do they owe me in total, so I can decide who to call first on Monday morning?';

/// A page shaped like the routed screen builds it: same widgets, sample data.
class _Harness extends StatefulWidget {
  const _Harness({
    this.messages = const [],
    this.busy = false,
    this.onSend,
    this.onChip,
  });

  final List<(bool, String)> messages;
  final bool busy;
  final ValueChanged<String>? onSend;
  final ValueChanged<String>? onChip;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.messages.isEmpty
        ? DesktopAiWelcome(
            greeting: 'Good afternoon, Wanjiru',
            icon: const Icon(Icons.auto_awesome_rounded, size: 22),
            actions: [
              for (final a in const [
                (Icons.wb_sunny_outlined, "Today's brief", 'How the shop is doing'),
                (Icons.inventory_2_outlined, 'What to restock', 'Reorder list within budget'),
                (Icons.payments_outlined, 'Who owes me', 'Debts to collect first'),
                (Icons.star_outline_rounded, 'Best sellers', "What's moving right now"),
                (Icons.document_scanner_rounded, 'Scan a receipt', 'Reads supplier invoices'),
                (Icons.photo_camera_rounded, 'Add a photo', 'Product, shelf or receipt'),
              ])
                DesktopAiAction(
                  icon: a.$1,
                  title: a.$2,
                  subtitle: a.$3,
                  badge: a.$2.contains('receipt') || a.$2.contains('photo')
                      ? 'Photo'
                      : null,
                  onTap: () => widget.onChip?.call(a.$2),
                ),
            ],
          )
        : ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              for (final m in widget.messages)
                AiChatBubble(
                  message: m.$2,
                  isUser: m.$1,
                  desktop: true,
                  onCopy: m.$1 ? null : () {},
                  onEdit: m.$1 ? () {} : null,
                  onRewind: () {},
                ),
            ],
          );

    return Scaffold(
      body: DesktopAiPage(
        title: 'Axon AI',
        subtitle:
            'Chats go to Axon Gateway, with read-only shop details when needed.',
        onMemory: () {},
        onExport: widget.messages.isEmpty ? null : () {},
        onNewConversation: widget.messages.isEmpty ? null : () {},
        conversation: conversation,
        chipsEnabled: !widget.busy,
        chips: [
          for (final c in const [
            (Icons.trending_up_rounded, 'Profit check'),
            (Icons.calendar_view_week_outlined, 'Weekly review'),
            (Icons.point_of_sale_outlined, 'Cash up'),
            (Icons.groups_outlined, 'Top customers'),
            (Icons.receipt_long_outlined, 'Expenses'),
          ])
            DesktopAiChip(
              icon: c.$1,
              label: c.$2,
              onTap: () => widget.onChip?.call(c.$2),
            ),
        ],
        composer: DesktopChatComposer(
          controller: _controller,
          hint: 'Message Axon AI',
          busy: widget.busy,
          enabled: !widget.busy,
          footnote: 'Enter to send, Shift+Enter for a new line, / for skills',
          leading: [
            IconButton(
              tooltip: 'Add a photo or file',
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
          onSend: () {
            widget.onSend?.call(_controller.text);
            _controller.clear();
          },
        ),
      ),
    );
  }
}

Widget _app(Widget home, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return ProviderScope(
    overrides: [
      tenantIdentityProvider.overrideWithValue(TenantIdentity.empty),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: DesktopTheme.of(base),
      home: DesktopScope(
        sidebarCollapsed: false,
        child:
            boundary == null ? home : ShotFrame(boundaryKey: boundary, child: home),
      ),
    ),
  );
}

/// Page area inside the shell: sidebar 232 at 1366, rail 56 at 1093.
const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
  '1920': Size(1688, 1012),
};

void main() {
  setUpAll(loadShotFonts);

  final conversation = <(bool, String)>[
    (true, 'How is the shop doing today?'),
    (false, _reply),
    (true, _longQuestion),
    (false, 'Four customers are past 30 days. Together they owe KES 61,300. Start with Mama Njeri (KES 24,000, 52 days).'),
  ];

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('welcome $theme ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(const _Harness(), dark: dark, boundary: key));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/ai-welcome-$theme-${entry.key}.png');
      });

      testWidgets('conversation $theme ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(
          _app(_Harness(messages: conversation), dark: dark, boundary: key),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/ai-chat-$theme-${entry.key}.png');
      });
    }
  }

  testWidgets('the conversation column never grows past 760px', (tester) async {
    useWindow(tester, _sizes['1920']!);
    await tester.pumpWidget(_app(_Harness(messages: conversation)));
    await tester.pumpAndSettle();
    final composer = tester.getSize(find.byType(DesktopChatComposer));
    expect(composer.width, lessThanOrEqualTo(760));
    // A reply and the person's long question both stay inside the column.
    final bubbles = find.byType(AiChatBubble);
    for (var i = 0; i < 4; i++) {
      expect(tester.getSize(bubbles.at(i)).width, lessThanOrEqualTo(760));
    }
  });

  testWidgets('Enter sends, Shift+Enter makes a new line, empty Enter does nothing',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final sent = <String>[];
    await tester.pumpWidget(_app(_Harness(onSend: sent.add)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, isEmpty);

    await tester.enterText(find.byType(TextField), 'Who owes me money?');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sent, isEmpty, reason: 'Shift+Enter must not send');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, ['Who owes me money?']);
  });

  testWidgets('Enter does nothing while a reply is being written', (tester) async {
    useWindow(tester, _sizes['1366']!);
    final sent = <String>[];
    await tester.pumpWidget(_app(_Harness(onSend: sent.add, busy: true)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('quick questions and the list rows report what was picked',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final picked = <String>[];
    await tester.pumpWidget(_app(_Harness(onChip: picked.add)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profit check'));
    await tester.tap(find.text('Who owes me'));
    expect(picked, ['Profit check', 'Who owes me']);
    expect(find.text('Good afternoon, Wanjiru'), findsOneWidget);
  });

  testWidgets('the setup screen says what to do and offers the key settings',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    var opened = false;
    await tester.pumpWidget(_app(
      Scaffold(
        body: DesktopAiSetupNeeded(
          title: 'Axon AI',
          checking: false,
          canManage: true,
          onOpenSettings: () => opened = true,
          onOpenMemory: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Connect Axon AI on this computer'), findsOneWidget);
    await tester.tap(find.text('Open key settings'));
    expect(opened, isTrue);
  });
}
