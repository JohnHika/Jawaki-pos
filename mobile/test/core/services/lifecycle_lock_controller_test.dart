import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:axon_pos/core/services/lifecycle_lock_controller.dart';
import 'package:axon_pos/core/services/storage_service.dart';

/// A minimal mock that implements [LifecycleLockAuth] without any platform
/// dependencies (local_auth, secure storage, etc.).
class MockAuthService implements LifecycleLockAuth {
  @override
  bool isAuthenticated = false;

  @override
  bool isLocked = false;

  bool lockSessionCalled = false;

  @override
  Future<void> lockSession() async {
    lockSessionCalled = true;
    isLocked = true;
  }
}

void main() {
  late StorageService storage;
  late MockAuthService mockAuth;
  late LifecycleLockController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialize();

    mockAuth = MockAuthService();
    controller = LifecycleLockController(
      authService: mockAuth,
      storageService: storage,
    );
  });

  group('LifecycleLockController', () {
    group('onAppBackgrounded', () {
      test('records the background timestamp', () {
        expect(controller.backgroundedAt, isNull);

        controller.onAppBackgrounded();

        expect(controller.backgroundedAt, isNotNull);
      });

      test('overwrites previous timestamp on successive backgrounds', () async {
        controller.onAppBackgrounded();
        final firstTimestamp = controller.backgroundedAt;

        // Small delay ensures a distinct timestamp
        await Future.delayed(const Duration(milliseconds: 2));
        controller.onAppBackgrounded();
        final secondTimestamp = controller.backgroundedAt;

        expect(secondTimestamp!.isAfter(firstTimestamp!), isTrue);
      });
    });

    group('onAppResumed — not authenticated', () {
      test('does not lock when user is not authenticated', () async {
        mockAuth.isAuthenticated = false;
        controller.onAppBackgrounded();

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isFalse);
        expect(controller.backgroundedAt, isNull);
      });
    });

    group('onAppResumed — requireUnlockOnResume', () {
      test('locks immediately when requireUnlockOnResume is true', () async {
        mockAuth.isAuthenticated = true;
        await storage.setRequireUnlockOnResume(true);
        controller.onAppBackgrounded();

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isTrue);
        expect(controller.backgroundedAt, isNull);
      });

      test('locks even when autoLockMinutes is 0 and requireUnlock is true',
          () async {
        mockAuth.isAuthenticated = true;
        await storage.setRequireUnlockOnResume(true);
        await storage.setAutoLockMinutes(0);
        controller.onAppBackgrounded();

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isTrue);
      });

      test('locks even when never backgrounded if requireUnlock is true',
          () async {
        mockAuth.isAuthenticated = true;
        await storage.setRequireUnlockOnResume(true);

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isTrue);
      });
    });

    group('onAppResumed — autoLockMinutes timer', () {
      test('does not lock when autoLockMinutes is 0', () async {
        mockAuth.isAuthenticated = true;
        await storage.setAutoLockMinutes(0);
        controller.onAppBackgrounded();

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isFalse);
      });

      test('does not lock when elapsed time is under the threshold', () async {
        mockAuth.isAuthenticated = true;
        await storage.setAutoLockMinutes(5);
        controller.onAppBackgrounded();

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isFalse);
      });

      test('does not lock when never backgrounded and timer is set', () async {
        mockAuth.isAuthenticated = true;
        await storage.setAutoLockMinutes(5);

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isFalse);
      });
    });

    group('onAppResumed — both requireUnlock and autoLockMinutes', () {
      test('requireUnlockOnResume takes priority over timer', () async {
        mockAuth.isAuthenticated = true;
        await storage.setRequireUnlockOnResume(true);
        await storage.setAutoLockMinutes(10);
        controller.onAppBackgrounded();

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isTrue);
      });
    });

    group('didChangeAppLifecycleState', () {
      test('calls onAppBackgrounded on paused', () {
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);

        expect(controller.backgroundedAt, isNotNull);
      });

      test('calls onAppBackgrounded on detached', () {
        controller.didChangeAppLifecycleState(AppLifecycleState.detached);

        expect(controller.backgroundedAt, isNotNull);
      });

      test('does not record timestamp on inactive', () {
        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);

        expect(controller.backgroundedAt, isNull);
      });

      test('calls onAppResumed on resumed', () async {
        mockAuth.isAuthenticated = true;
        await storage.setRequireUnlockOnResume(true);
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);

        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

        await Future<void>.delayed(Duration.zero);
        expect(mockAuth.lockSessionCalled, isTrue);
      });
    });

    group('edge cases', () {
      test('does not lock when not authenticated even with requireUnlock',
          () async {
        mockAuth.isAuthenticated = false;
        await storage.setRequireUnlockOnResume(true);
        controller.onAppBackgrounded();

        await controller.onAppResumed();

        expect(mockAuth.lockSessionCalled, isFalse);
      });

      test('clears background timestamp after resume', () async {
        mockAuth.isAuthenticated = true;
        controller.onAppBackgrounded();
        expect(controller.backgroundedAt, isNotNull);

        await controller.onAppResumed();

        expect(controller.backgroundedAt, isNull);
      });
    });
  });
}
