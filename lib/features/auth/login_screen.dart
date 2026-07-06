import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets/loading_button.dart';
import '../../models/store.dart';
import '../home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePin = true;
  String? _selectedStoreId;
  String? _error;

  final List<Store> _stores = Store.mockStores();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStoreId == null) {
      setState(() => _error = 'Please select a store');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Simulate authentication delay
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      // In production, validate PIN against backend
      final store = _stores.firstWhere(
        (s) => s.id == _selectedStoreId,
        orElse: () => _stores.first,
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(store: store),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo / Branding
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: JawakiTheme.primaryDeepBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.store,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Jawaki Admin',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: JawakiTheme.primaryDeepBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Store Management System',
                    style: TextStyle(
                      fontSize: 14,
                      color: JawakiTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Store selection
                  DropdownButtonFormField<String>(
                    value: _selectedStoreId,
                    decoration: const InputDecoration(
                      labelText: 'Select Store',
                      prefixIcon: Icon(Icons.store),
                    ),
                    items: _stores.map((store) {
                      return DropdownMenuItem(
                        value: store.id,
                        child: Text(
                          store.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedStoreId = value;
                        _error = null;
                      });
                    },
                    validator: (value) {
                      if (value == null) return 'Please select a store';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // PIN input
                  TextFormField(
                    controller: _pinController,
                    obscureText: _obscurePin,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Store PIN',
                      hintText: 'Enter 4-digit PIN',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePin
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _obscurePin = !_obscurePin);
                        },
                      ),
                      counterText: '',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter PIN';
                      }
                      if (value.length != 4) {
                        return 'PIN must be 4 digits';
                      }
                      if (!RegExp(r'^\d{4}$').hasMatch(value)) {
                        return 'PIN must be numeric';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Error
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: JawakiTheme.accentRed,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  // Login button
                  LoadingButton(
                    label: 'Login',
                    icon: Icons.login,
                    isLoading: _isLoading,
                    onPressed: _login,
                  ),

                  const SizedBox(height: 24),

                  // Hint
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: JawakiTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: JawakiTheme.primaryDeepBlue, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Use any 4-digit PIN to login (demo mode)',
                            style: TextStyle(
                              fontSize: 12,
                              color: JawakiTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
