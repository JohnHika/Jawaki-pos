import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  static const int _pinLength = 4;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  void _onNumberPressed(String number) {
    if (_pin.length < _pinLength) {
      setState(() {
        _pin += number;
      });

      if (_pin.length == _pinLength) {
        _handlePinLogin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  void _onClearPressed() {
    setState(() {
      _pin = '';
    });
  }

  Future<void> _handlePinLogin() async {
    final result = await ref.read(authControllerProvider.notifier).loginWithPin(_pin);

    if (result && mounted) {
      context.go('/');
    } else {
      setState(() {
        _pin = '';
      });
    }
  }

  Future<void> _handleBiometricLogin() async {
    final result = await ref.read(authControllerProvider.notifier).loginWithBiometrics();
    if (result && mounted) {
      context.go('/');
    }
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6366F1),
              Color(0xFF4F46E5),
              Color(0xFF3730A3),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Material(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => context.pop(),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'PIN Login',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        SizedBox(height: isSmallScreen ? 20 : 40),

                        // Logo
                        Container(
                          width: isSmallScreen ? 70 : 80,
                          height: isSmallScreen ? 70 : 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.lock_rounded,
                              size: 40,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ),

                        SizedBox(height: isSmallScreen ? 16 : 20),

                        // Title
                        const Text(
                          'Enter PIN',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your 4-digit PIN to continue',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),

                        SizedBox(height: isSmallScreen ? 24 : 32),

                        // PIN Dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_pinLength, (index) {
                            final isFilled = index < _pin.length;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              width: isFilled ? 20 : 16,
                              height: isFilled ? 20 : 16,
                              decoration: BoxDecoration(
                                color: isFilled ? Colors.white : Colors.transparent,
                                border: Border.all(
                                  color: isFilled ? Colors.white : Colors.white.withOpacity(0.5),
                                  width: 2.5,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isFilled
                                    ? [
                                        BoxShadow(
                                          color: Colors.white.withOpacity(0.3),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: isFilled
                                  ? Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    )
                                  : null,
                            );
                          }),
                        ),

                        // Error Message
                        if (authState.error != null) ...[
                          SizedBox(height: isSmallScreen ? 16 : 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  authState.error!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Loading indicator
                        if (authState.isLoading) ...[
                          SizedBox(height: isSmallScreen ? 16 : 20),
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ],

                        SizedBox(height: isSmallScreen ? 24 : 32),

                        // Dev hint
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amber.withOpacity(0.4),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lightbulb_outline_rounded, size: 16, color: Colors.amber),
                              SizedBox(width: 8),
                              Text(
                                'Demo PIN: 0000',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: isSmallScreen ? 32 : 48),

                        // Number Pad
                        _buildNumberPad(isSmallScreen),

                        SizedBox(height: isSmallScreen ? 16 : 24),

                        // Switch to email login
                        TextButton(
                          onPressed: () => context.pop(),
                          child: Text(
                            'Use email instead',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        // Biometric login button
                        FutureBuilder<bool>(
                          future: ref.read(authControllerProvider.notifier).isBiometricAvailable(),
                          builder: (context, snapshot) {
                            if (snapshot.data != true) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(30),
                                child: InkWell(
                                  onTap: authState.isLoading ? null : _handleBiometricLogin,
                                  borderRadius: BorderRadius.circular(30),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.fingerprint_rounded,
                                      size: 44,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        SizedBox(height: isSmallScreen ? 16 : 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad(bool isSmallScreen) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padHorizontal = screenWidth < 380 ? 16.0 : 32.0;
    final btnSize = isSmallScreen ? 64.0 : 76.0;
    final fontSize = isSmallScreen ? 26.0 : 30.0;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padHorizontal),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNumberButton('1', btnSize, fontSize),
                _buildNumberButton('2', btnSize, fontSize),
                _buildNumberButton('3', btnSize, fontSize),
              ],
            ),
            SizedBox(height: isSmallScreen ? 14 : 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNumberButton('4', btnSize, fontSize),
                _buildNumberButton('5', btnSize, fontSize),
                _buildNumberButton('6', btnSize, fontSize),
              ],
            ),
            SizedBox(height: isSmallScreen ? 14 : 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNumberButton('7', btnSize, fontSize),
                _buildNumberButton('8', btnSize, fontSize),
                _buildNumberButton('9', btnSize, fontSize),
              ],
            ),
            SizedBox(height: isSmallScreen ? 14 : 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(Icons.clear_rounded, _onClearPressed, btnSize),
                _buildNumberButton('0', btnSize, fontSize),
                _buildActionButton(Icons.backspace_outlined, _onBackspacePressed, btnSize),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberButton(String number, double btnSize, double fontSize) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Material(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(btnSize / 2),
      child: InkWell(
        onTap: isLoading ? null : () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(btnSize / 2),
        onTapDown: (_) => _animationController.forward(),
        onTapUp: (_) => _animationController.reverse(),
        onTapCancel: () => _animationController.reverse(),
        child: Container(
          width: btnSize,
          height: btnSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(btnSize / 2),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onPressed, double btnSize) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(btnSize / 2),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(btnSize / 2),
        child: Container(
          width: btnSize,
          height: btnSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(btnSize / 2),
          ),
          child: Icon(
            icon,
            size: btnSize * 0.4,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ),
    );
  }
}
