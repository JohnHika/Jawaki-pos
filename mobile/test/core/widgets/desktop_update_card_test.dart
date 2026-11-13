import 'dart:async';
import 'dart:io';

import 'package:axon_pos/core/services/desktop_update_service.dart';
import 'package:axon_pos/core/widgets/desktop_update/desktop_update_card.dart';
import 'package:axon_pos/core/widgets/desktop_update/desktop_update_host.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notes = '''
Adds a "Check for updates" window that installs the new version for you.
Fixes the computer sign-in code freezing on "New code in 0s".
Improves how quickly the shop opens after a restart.
''';

DesktopUpdateInfo _info({String notes = _notes}) => DesktopUpdateInfo(
      version: '1.0.181',
      build: 2224,
      tag: 'v1.0.181-2224',
      installerUrl: Uri.parse(
          'https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.181-2224/Counterbase-Setup.exe'),
      notes: notes,
      sizeBytes: 19777895,
    );

class _Harness {
  _Harness({
    DesktopReleaseLoader? loader,
    DesktopInstallerDownloader? downloader,
  }) {
    service = DesktopUpdateService(
      supported: true,
      releaseLoader: loader ?? () async => _info(),
      downloader: downloader,
      launchInstaller: (path, args) async {},
      exitApp: () async {},
      workDirectory: () async => work,
      restartPause: Duration.zero,
    );
  }
  late final DesktopUpdateService service;

  /// Each test installs into its own folder, so one test's finished
  /// download is never reused by the next.
  final Directory work = Directory.systemTemp.createTempSync('cb-card-test');
}

Future<void> _pumpCard(WidgetTester tester, DesktopUpdateService service,
    {Brightness brightness = Brightness.dark, VoidCallback? onClose}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: Center(
        child: DesktopUpdateCard(
          service: service,
          onClose: onClose ?? () {},
          now: () => DateTime(2026, 11, 9, 12, 0),
        ),
      ),
    ),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Counterbase',
      packageName: 'com.archeaxon.axonpos',
      version: '1.0.180',
      buildNumber: '2223',
      buildSignature: '',
    );
  });

  group('change list', () {
    test('groups notes under New, Fixed and Improved', () {
      final groups = groupUpdateNotes(_notes);
      expect(groups.map((g) => g.label), ['New', 'Fixed', 'Improved']);
      expect(groups.first.items.single, startsWith('Adds a'));
    });

    test('plain notes get one heading', () {
      final groups = groupUpdateNotes('Checkout is quicker.');
      expect(groups.single.label, 'What’s new');
    });

    test('release notes with only build details still say something', () {
      final groups = groupUpdateNotes(
          '## Download\n- [GitHub Release](https://github.com/x)\n\n**Release:** Counterbase 1.0.181');
      expect(groups.single.label, 'Improved');
      expect(groups.single.items.single, contains('improvements'));
    });
  });

  group('small helpers', () {
    test('sizes read like Windows shows them', () {
      expect(formatUpdateBytes(19777895), '18.9 MB');
      expect(formatUpdateBytes(2048), '2 KB');
    });

    test('last checked reads naturally', () {
      final now = DateTime(2026, 11, 9, 12);
      expect(updateRelativeTime(null, now), 'never');
      expect(updateRelativeTime(now, now), 'just now');
      expect(updateRelativeTime(now.subtract(const Duration(minutes: 5)), now),
          '5 min ago');
      expect(updateRelativeTime(now.subtract(const Duration(hours: 1)), now),
          '1 hour ago');
      expect(updateRelativeTime(now.subtract(const Duration(hours: 3)), now),
          '3 hours ago');
      expect(updateRelativeTime(now.subtract(const Duration(days: 2)), now),
          '2 days ago');
    });
  });

  group('the card', () {
    testWidgets('looks for updates while nothing is known', (tester) async {
      final gate = Completer<void>();
      final h = _Harness(loader: () async {
        await gate.future;
        return _info();
      });
      unawaited(h.service.checkForUpdates());
      await _pumpCard(tester, h.service);
      await tester.pump();
      expect(find.text('Looking for updates…'), findsOneWidget);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Looking for updates…'), findsNothing);
    });

    testWidgets('offers the update with what changed', (tester) async {
      final h = _Harness();
      await tester.runAsync(h.service.checkForUpdates);
      await _pumpCard(tester, h.service);
      await tester.pump();

      expect(find.text('New update available'), findsOneWidget);
      expect(find.textContaining('Counterbase will close, update and reopen'),
          findsOneWidget);
      expect(find.text('Version 1.0.180 → 1.0.181  ·  18.9 MB'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Fixed'), findsOneWidget);
      expect(find.text('Improved'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Maybe later closes the card and quiets the notice',
        (tester) async {
      final h = _Harness();
      await tester.runAsync(h.service.checkForUpdates);
      var closed = false;
      await _pumpCard(tester, h.service, onClose: () => closed = true);
      await tester.pump();

      await tester.ensureVisible(find.text('Maybe later'));
      await tester.tap(find.text('Maybe later'));
      await tester.pump();
      expect(closed, isTrue);
      expect(h.service.notice, isNull);
    });

    testWidgets('Update now starts the install and shows the stage',
        (tester) async {
      final gate = Completer<void>();
      final h = _Harness(
        downloader: (url, path, token, progress) async => gate.future,
      );
      await tester.runAsync(h.service.checkForUpdates);
      await _pumpCard(tester, h.service);
      await tester.pump();

      await tester.ensureVisible(find.text('Update now'));
      await tester.tap(find.text('Update now'));
      await tester.pump();

      expect(find.text('Downloading…'), findsOneWidget);
      expect(find.textContaining('Counterbase closes while the update installs'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // No way out of the window while it is installing.
      expect(find.bySemanticsLabel('Close'), findsNothing);

      // Leave it downloading; the test ends with the window.
      expect(h.service.applying, isTrue);
      gate.complete();
    });

    testWidgets('shows how much has downloaded', (tester) async {
      final gate = Completer<void>();
      final h = _Harness(
        downloader: (url, path, token, progress) async {
          progress(5 * 1024 * 1024, 19777895);
          await gate.future;
        },
      );
      await tester.runAsync(() async {
        await h.service.checkForUpdates();
        unawaited(h.service.startUpdate());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _pumpCard(tester, h.service);
      await tester.pump();

      expect(find.text('Downloading…'), findsOneWidget);
      expect(find.text('5.0 MB of 18.9 MB'), findsOneWidget);

      h.service.cancelDownload();
      gate.completeError(DioException(
          requestOptions: RequestOptions(path: '/'), type: DioExceptionType.cancel));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    });

    testWidgets('a failure says nothing was lost and offers Try again',
        (tester) async {
      final h = _Harness(
        downloader: (url, path, token, progress) async => throw DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );
      await tester.runAsync(() async {
        await h.service.checkForUpdates();
        await h.service.startUpdate();
      });
      await _pumpCard(tester, h.service);
      await tester.pump();

      expect(find.text('Update didn’t finish'), findsOneWidget);
      expect(find.textContaining('couldn’t reach the update server'),
          findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('up to date shows the version and the Check now card',
        (tester) async {
      final h = _Harness(loader: () async => null);
      await tester.runAsync(h.service.checkForUpdates);
      await _pumpCard(tester, h.service);
      await tester.pump();

      expect(find.text('Counterbase'), findsOneWidget);
      expect(find.text('Version 1.0.180'), findsOneWidget);
      expect(find.text('You’re running the latest version.'), findsOneWidget);
      expect(find.textContaining('Last checked'), findsOneWidget);
      expect(find.text('Check now'), findsOneWidget);
    });

    testWidgets('an unreachable server shows in the status card',
        (tester) async {
      final h = _Harness(
          loader: () async => throw StateError('offline'));
      await tester.runAsync(h.service.checkForUpdates);
      await _pumpCard(tester, h.service);
      await tester.pump();

      expect(find.text('Couldn’t reach the update server'), findsOneWidget);
      expect(find.text('Check now'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('lays out without overflow in $brightness', (tester) async {
        final h = _Harness();
        await tester.runAsync(h.service.checkForUpdates);
        await _pumpCard(tester, h.service, brightness: brightness);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the host', () {
    Future<void> pumpHost(WidgetTester tester, DesktopUpdateService s) async {
      tester.view.physicalSize = const Size(1366, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const SizedBox.shrink(),
        builder: (context, child) => DesktopUpdateHost(
          service: s,
          child: const Scaffold(body: Center(child: Text('Dashboard'))),
        ),
      ));
    }

    testWidgets('announces a new update in the corner, then opens the card',
        (tester) async {
      final h = _Harness();
      await pumpHost(tester, h.service);
      await tester.runAsync(h.service.checkForUpdates);
      await tester.pump();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('New update available'), findsOneWidget);
      expect(find.text('Counterbase 1.0.181 is ready to install.'),
          findsOneWidget);

      await tester.tap(find.text('See what’s new'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(h.service.overlayOpen, isTrue);
      expect(find.text('Update now'), findsOneWidget);
      // The corner notice steps aside for the window.
      expect(find.text('Counterbase 1.0.181 is ready to install.'),
          findsNothing);
    });

    testWidgets('Escape and the backdrop close the window', (tester) async {
      final h = _Harness();
      await pumpHost(tester, h.service);
      await tester.runAsync(h.service.checkForUpdates);
      h.service.openOverlay();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Update now'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(h.service.overlayOpen, isFalse);

      h.service.openOverlay();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(40, 40));
      await tester.pump();
      expect(h.service.overlayOpen, isFalse);
    });

    testWidgets('the corner notice goes away by itself', (tester) async {
      final h = _Harness();
      await pumpHost(tester, h.service);
      await h.service.checkForUpdates();
      await tester.pump();
      expect(find.text('New update available'), findsOneWidget);

      await tester.pump(const Duration(seconds: 21));
      expect(find.text('New update available'), findsNothing);
      expect(h.service.updateAvailable, isTrue);
    });

    testWidgets('Later silences the notice for a day', (tester) async {
      final h = _Harness();
      await pumpHost(tester, h.service);
      await tester.runAsync(h.service.checkForUpdates);
      await tester.pump();

      await tester.tap(find.text('Later'));
      await tester.pump();
      expect(find.text('New update available'), findsNothing);
    });

    testWidgets('on a phone it leaves the app alone', (tester) async {
      final service = DesktopUpdateService(supported: false);
      await pumpHost(tester, service);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byType(UpdateBrandMark), findsNothing);
    });
  });
}
