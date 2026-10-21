import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';

enum AuthStatus { booting, signedOut, signedIn }

/// Owns "who is signed in": tokens, profile, permissions, the app lock and the
/// screenshot-privacy switch. UI reads it with `context.watch<SessionController>()`.
class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController({required this.api, required this.repo, required SharedPreferences prefs}) : _prefs = prefs {
    api.onSessionExpired = _handleSessionExpired;
    WidgetsBinding.instance.addObserver(this);
  }

  final AcaApi api;
  final AcaRepository repo;
  final SharedPreferences _prefs;
  final LocalAuthentication _auth = LocalAuthentication();
  static const MethodChannel _privacy = MethodChannel('aca/privacy');

  static const _kLock = 'aca.lock.enabled';
  static const _kHide = 'aca.privacy.hide';
  static const _lockAfter = Duration(seconds: 20);

  AuthStatus status = AuthStatus.booting;
  StaffProfile? me;

  /// Shown once on the sign-in screen (e.g. "Your session ended").
  String? notice;

  /// Set when boot could not reach the server while a session exists.
  String? bootError;

  bool _deviceCanLock = false;
  bool locked = false;
  DateTime? _backgroundedAt;

  bool get deviceCanLock => _deviceCanLock;

  /// Defaults ON for the real app, OFF for QA builds so automated checks aren't blocked.
  bool get lockEnabled => _prefs.getBool(_kLock) ?? AcaConfig.isProduction;
  bool get hideContent => _prefs.getBool(_kHide) ?? AcaConfig.isProduction;

  bool get mustChangePassword => me?.mustChangePassword ?? false;
  bool can(String permission) => me?.can(permission) ?? false;

  // --------------------------------------------------------------------- boot

  Future<void> boot() async {
    bootError = null;
    status = AuthStatus.booting;
    notifyListeners();

    try {
      _deviceCanLock = await _auth.isDeviceSupported();
    } catch (_) {
      _deviceCanLock = false;
    }
    await _applyPrivacy();

    final tokens = await api.loadTokens();
    if (tokens == null) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    try {
      await _loadProfile();
      locked = lockEnabled && _deviceCanLock;
      status = AuthStatus.signedIn;
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.isForbidden && !e.isPasswordChangeRequired) {
        await api.clearTokens();
        status = AuthStatus.signedOut;
      } else if (e.isPasswordChangeRequired) {
        // /auth/me is exempt from the gate, so this is unexpected; fall back to signing in again.
        await api.clearTokens();
        status = AuthStatus.signedOut;
      } else {
        // Offline / server asleep: keep the session, let the user retry.
        bootError = e.message;
        status = AuthStatus.booting;
      }
    }
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    final j = await api.getMap('/auth/me');
    me = StaffProfile.fromJson(j);
  }

  /// Re-reads the profile (after a 2FA change, role change, password change...).
  Future<void> reloadProfile() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _loadProfile();
        notifyListeners();
        return;
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          _handleSessionExpired();
          return;
        }
        // Transient (offline / server waking): try once more before giving up.
        if (attempt == 0) await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  // ------------------------------------------------------------------ sign in

  /// Returns true when the account needs an authenticator code ([otp] was missing).
  /// Throws [ApiException] for bad credentials, lockouts, network errors.
  Future<bool> signIn(String email, String password, {String? otp}) async {
    final j = await api.postMap_('/auth/login', {
      'email': email.trim(),
      'password': password,
      if (otp != null && otp.trim().isNotEmpty) 'otp': otp.trim(),
    });
    if (j['requiresTwoFactor'] == true) return true;

    await api.setTokens(AuthTokens(
      access: J.s(j['accessToken']),
      refresh: J.s(j['refreshToken']),
      accessExpiresAt: J.d(j['accessTokenExpiresAt']),
    ));
    me = StaffProfile.fromJson(J.map(j['admin']));
    notice = null;
    locked = false;
    status = AuthStatus.signedIn;
    notifyListeners();
    return false;
  }

  Future<void> signOut({bool remote = true}) async {
    if (remote && api.hasSession) {
      try {
        await api.post('/auth/logout');
      } catch (_) {
        // Offline sign-out still clears this device; the server session expires on its own.
      }
    }
    await api.clearTokens();
    me = null;
    locked = false;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  void _handleSessionExpired() {
    me = null;
    locked = false;
    notice = 'Your session ended. Please sign in again.';
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  // ----------------------------------------------------------------- app lock

  Future<bool> unlock() async {
    if (!locked) return true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock ACA',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        locked = false;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> setLockEnabled(bool on) async {
    if (on && !_deviceCanLock) return;
    if (on) {
      // Prove the device can actually authenticate before turning the lock on.
      try {
        final ok = await _auth.authenticate(
          localizedReason: 'Confirm to turn on the ACA app lock',
          biometricOnly: false,
        );
        if (!ok) return;
      } catch (_) {
        return;
      }
    }
    await _prefs.setBool(_kLock, on);
    notifyListeners();
  }

  Future<void> setHideContent(bool on) async {
    await _prefs.setBool(_kHide, on);
    await _applyPrivacy();
    notifyListeners();
  }

  Future<void> _applyPrivacy() async {
    try {
      await _privacy.invokeMethod('setSecure', {'on': hideContent});
    } catch (_) {
      // Non-Android test hosts have no channel.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (status == AuthStatus.signedIn &&
          lockEnabled &&
          _deviceCanLock &&
          since != null &&
          DateTime.now().difference(since) > _lockAfter) {
        locked = true;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// `postMap` that doesn't send (or refresh) an access token — used for login.
extension on AcaApi {
  Future<Map<String, dynamic>> postMap_(String path, Map<String, dynamic> body) async {
    final r = await post(path, body: body, auth: false);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }
}
