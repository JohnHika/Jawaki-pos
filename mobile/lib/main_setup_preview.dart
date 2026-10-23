import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/auth/presentation/screens/company_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() => runApp(const ProviderScope(child: _Preview()));

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: const CompanySetupScreen(),
      );
}
