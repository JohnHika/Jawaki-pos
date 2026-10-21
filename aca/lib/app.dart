import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/api_client.dart';
import 'data/repository.dart';
import 'features/auth/force_password_change_screen.dart';
import 'features/auth/lock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/home_shell.dart';
import 'state/session.dart';

class AcaApp extends StatelessWidget {
  const AcaApp({super.key, required this.api, required this.repo, required this.session});

  final AcaApi api;
  final AcaRepository repo;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AcaApi>.value(value: api),
        Provider<AcaRepository>.value(value: repo),
        ChangeNotifierProvider<SessionController>.value(value: session),
      ],
      child: MaterialApp(
        title: AcaConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AcaTheme.lightTheme,
        darkTheme: AcaTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const _RootGate(),
        builder: (context, child) {
          final p = context.aca;
          final icons = p.isDark ? Brightness.light : Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: icons,
              statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: p.bg,
              systemNavigationBarIconBrightness: icons,
              systemNavigationBarContrastEnforced: false,
            ),
            // Android 15+ draws apps edge-to-edge; keep content clear of the gesture/nav bar.
            child: ColoredBox(
              color: p.bg,
              child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox.shrink()),
            ),
          );
        },
      ),
    );
  }
}

/// Decides what the user sees from the session state alone.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();

    Widget screen;
    switch (s.status) {
      case AuthStatus.booting:
        screen = BootScreen(error: s.bootError, onRetry: s.boot);
      case AuthStatus.signedOut:
        screen = const LoginScreen();
      case AuthStatus.signedIn:
        screen = s.mustChangePassword ? const ForcePasswordChangeScreen() : const HomeShell();
    }

    // While locked, the app content is not even in the tree.
    if (s.status == AuthStatus.signedIn && s.locked) return const LockScreen();
    return screen;
  }
}

/// A release build must never talk to anything but production.
class WrongServerApp extends StatelessWidget {
  const WrongServerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AcaTheme.darkTheme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'This build is not pointed at the live Counterbase server and has been blocked.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}

bool get releaseBuildPointsAtWrongServer => kReleaseMode && !AcaConfig.isProduction;
