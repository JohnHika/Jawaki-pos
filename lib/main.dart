import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'services/api_service.dart';
import 'services/sms_service.dart';
import 'features/auth/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JawakiAdminApp());
}

class JawakiAdminApp extends StatelessWidget {
  const JawakiAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        Provider<SmsService>(create: (_) => SmsService(useMock: true)),
      ],
      child: MaterialApp(
        title: 'Jawaki Admin',
        debugShowCheckedModeBanner: false,
        theme: JawakiTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );
  }
}
