import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/api_client.dart';
import 'data/repository.dart';
import 'state/session.dart';

Future<String> _deviceLabel() async {
  try {
    if (Platform.isAndroid) {
      final a = await DeviceInfoPlugin().androidInfo;
      return '${a.manufacturer} ${a.model} (Android ${a.version.release})';
    }
  } catch (_) {}
  return 'Unknown device';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (releaseBuildPointsAtWrongServer) {
    runApp(const WrongServerApp());
    return;
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  final api = AcaApi(
    store: TokenStore(),
    deviceLabel: await _deviceLabel(),
    appVersion: '${info.version}+${info.buildNumber}',
  );
  final repo = AcaRepository(api);
  final session = SessionController(api: api, repo: repo, prefs: prefs);

  runApp(AcaApp(api: api, repo: repo, session: session));
  session.boot();
}
