import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/features/settings/domain/linked_computer.dart';
import 'package:axon_pos/features/settings/presentation/screens/linked_computers_screen.dart';

/// Stands in for the online service's linked-computer endpoints.
class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  List<Map<String, dynamic>> computers = [];
  bool failListing = false;
  bool failRevoking = false;
  final revoked = <String>[];
  int revokedAll = 0;

  @override
  Future<List<Map<String, dynamic>>> getLinkedComputers() async {
    if (failListing) throw DioException(requestOptions: RequestOptions());
    return computers;
  }

  @override
  Future<void> revokeLinkedComputer(String id) async {
    if (failRevoking) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      );
    }
    revoked.add(id);
  }

  @override
  Future<void> revokeAllLinkedComputers() async {
    revokedAll++;
  }
}

class _FakeAuth implements AuthService {
  _FakeAuth({this.local = false});
  final bool local;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');

  @override
  bool get isLocalWorkspace => local;
}

Map<String, dynamic> _row(
  String id,
  String name, {
  String platform = 'windows',
  String? place = 'Nairobi, KE',
  bool isThisDevice = false,
  DateTime? lastActive,
}) =>
    {
      'id': id,
      'name': name,
      'platform': platform,
      'place': place,
      'linkedAt': DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
      'lastActiveAt':
          (lastActive ?? DateTime.now().subtract(const Duration(hours: 3)))
              .toIso8601String(),
      'isThisDevice': isThisDevice,
    };

void main() {
  late _FakeApi api;

  setUp(() {
    getIt.pushNewScope();
    api = _FakeApi();
    getIt.registerSingleton<ApiClient>(api);
    getIt.registerSingleton<AuthService>(_FakeAuth());
  });
  tearDown(() async => getIt.popScope());

  Future<void> pump(WidgetTester tester, {Size size = const Size(400, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LinkedComputersScreen()));
    await tester.pumpAndSettle();
  }

  group('model', () {
    test('reads the API row and labels the platform', () {
      final c = LinkedComputer.fromJson(_row('c1', 'FRONT-DESK', platform: 'macos'));
      expect(c.name, 'FRONT-DESK');
      expect(c.platformLabel, 'Mac');
      expect(c.place, 'Nairobi, KE');
      expect(c.activeNow(), isFalse);
    });

    test('active now means seen in the last five minutes', () {
      final c = LinkedComputer.fromJson(
          _row('c1', 'PC', lastActive: DateTime.now().subtract(const Duration(minutes: 1))));
      expect(c.activeNow(), isTrue);
    });
  });

  testWidgets('lists each linked computer with where it signed in from',
      (tester) async {
    api.computers = [
      _row('c1', 'FRONT-DESK', isThisDevice: true),
      _row('c2', 'BACK-OFFICE', platform: 'macos', place: null),
    ];
    await pump(tester);

    expect(find.text('FRONT-DESK'), findsOneWidget);
    expect(find.text('Windows · Nairobi, KE'), findsOneWidget);
    expect(find.text('This computer'), findsOneWidget);
    expect(find.text('BACK-OFFICE'), findsOneWidget);
    expect(find.text('Mac'), findsOneWidget);
    expect(find.textContaining('Active 3 h ago'), findsNWidgets(2));
    expect(find.text('Sign out all computers'), findsOneWidget);
  });

  testWidgets('signing one out asks first, then removes it and says so',
      (tester) async {
    api.computers = [_row('c1', 'FRONT-DESK'), _row('c2', 'BACK-OFFICE')];
    await pump(tester);

    await tester.tap(find.text('Sign out').first);
    await tester.pumpAndSettle();
    expect(find.text('Sign out FRONT-DESK?'), findsOneWidget);
    expect(api.revoked, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(api.revoked, ['c1']);
    expect(find.text('FRONT-DESK'), findsNothing);
    expect(find.text('BACK-OFFICE'), findsOneWidget);
    expect(find.text('FRONT-DESK was signed out'), findsOneWidget);
  });

  testWidgets('cancelling the question leaves the computer signed in',
      (tester) async {
    api.computers = [_row('c1', 'FRONT-DESK')];
    await pump(tester);

    await tester.tap(find.text('Sign out').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(api.revoked, isEmpty);
    expect(find.text('FRONT-DESK'), findsOneWidget);
  });

  testWidgets('signing out the computer in use warns that it will leave',
      (tester) async {
    api.computers = [_row('c1', 'FRONT-DESK', isThisDevice: true)];
    await pump(tester);

    await tester.tap(find.text('Sign out').first);
    await tester.pumpAndSettle();

    expect(find.text('Sign out this computer?'), findsOneWidget);
    expect(find.textContaining('sign-in screen'), findsOneWidget);
  });

  testWidgets('a failed sign-out keeps the computer and explains', (tester) async {
    api.computers = [_row('c1', 'FRONT-DESK')];
    api.failRevoking = true;
    await pump(tester);

    await tester.tap(find.text('Sign out').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('FRONT-DESK'), findsOneWidget);
    expect(find.textContaining('reach the server'), findsOneWidget);
  });

  testWidgets('sign out all clears the list and shows the empty state',
      (tester) async {
    api.computers = [_row('c1', 'FRONT-DESK'), _row('c2', 'BACK-OFFICE')];
    await pump(tester);

    await tester.tap(find.text('Sign out all computers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('All 2 computers'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out all'));
    await tester.pumpAndSettle();

    expect(api.revokedAll, 1);
    expect(find.text('No computers signed in'), findsOneWidget);
    expect(find.text('All computers were signed out'), findsOneWidget);
  });

  testWidgets('no computers yet points to signing one in', (tester) async {
    await pump(tester);

    expect(find.text('No computers signed in'), findsOneWidget);
    expect(find.text('Sign in a computer'), findsOneWidget);
  });

  testWidgets('a list that cannot load offers to try again', (tester) async {
    api.failListing = true;
    await pump(tester);

    expect(find.text('Could not load your computers'), findsOneWidget);

    api.failListing = false;
    api.computers = [_row('c1', 'FRONT-DESK')];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('FRONT-DESK'), findsOneWidget);
  });

  testWidgets('a shop kept on the phone has no computers to list', (tester) async {
    getIt.unregister<AuthService>();
    getIt.registerSingleton<AuthService>(_FakeAuth(local: true));
    await pump(tester);

    expect(find.text('Kept on this phone only'), findsOneWidget);
  });

  testWidgets('cards sit in one column on a phone and two on a wide window',
      (tester) async {
    api.computers = [_row('c1', 'FRONT-DESK'), _row('c2', 'BACK-OFFICE')];

    await pump(tester, size: const Size(400, 900));
    final phoneA = tester.getTopLeft(find.text('FRONT-DESK'));
    final phoneB = tester.getTopLeft(find.text('BACK-OFFICE'));
    expect(phoneB.dy, greaterThan(phoneA.dy));

    // An unfolded foldable or a tablet.
    await pump(tester, size: const Size(900, 900));
    final wideA = tester.getTopLeft(find.text('FRONT-DESK'));
    final wideB = tester.getTopLeft(find.text('BACK-OFFICE'));
    expect(wideB.dy, wideA.dy);
    expect(wideB.dx, greaterThan(wideA.dx));
  });

  testWidgets('a narrow cover screen shows no overflow', (tester) async {
    api.computers = [
      _row('c1', 'A-VERY-LONG-COMPUTER-NAME-FOR-THE-FRONT-DESK', isThisDevice: true),
    ];
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;

    await pump(tester, size: const Size(280, 650));

    FlutterError.onError = previous;
    final text =
        reported.map((d) => d.toDiagnosticsNode().toStringDeep()).join('\n');
    expect(text, isEmpty);
  });
}
