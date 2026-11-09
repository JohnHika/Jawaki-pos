import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/device_features.dart';

/// Opens the camera, reads one barcode and returns its text. Nothing is saved
/// or sent anywhere: the caller decides what to do with the number.
///
/// On a computer there is no camera scanner. A USB barcode scanner types the
/// code and presses Enter, so the same screen takes it from a text box.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key, this.title = 'Scan a barcode'});

  final String title;

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final MobileScannerController? _controller = DeviceFeatures.cameraScanner
      ? MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates)
      : null;
  bool _done = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim() ?? '';
      if (value.isEmpty) continue;
      _done = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _TypedCodeScreen(title: widget.title);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // The app's title style carries its own dark ink, which beats
        // foregroundColor and left the title invisible on black.
        titleTextStyle: Theme.of(context)
            .appBarTheme
            .titleTextStyle
            ?.copyWith(color: Colors.white),
        title: Text(widget.title),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined,
                        color: Colors.white70, size: 40),
                    const SizedBox(height: 14),
                    const Text(
                      'The camera is not available',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Allow camera access for Counterbase in your phone settings, or type the number instead.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        minimumSize: const Size(0, 46),
                      ),
                      child: const Text('Type it instead'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Point the camera at the barcode',
                    style: TextStyle(
                        color: DesignColors.accent,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The computer's version: a box the USB scanner types into.
class _TypedCodeScreen extends StatefulWidget {
  const _TypedCodeScreen({required this.title});

  final String title;

  @override
  State<_TypedCodeScreen> createState() => _TypedCodeScreenState();
}

class _TypedCodeScreenState extends State<_TypedCodeScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _use() {
    final value = _code.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.qr_code_scanner_rounded,
                    size: 44, color: DesignColors.accent),
                const SizedBox(height: DesignSpacing.md),
                Text(
                  'Scan it with the barcode scanner',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Or type the number under the barcode and press Enter.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: DesignSpacing.lg),
                TextField(
                  controller: _code,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _use(),
                  decoration: const InputDecoration(
                    labelText: 'Barcode or code',
                    prefixIcon: Icon(Icons.qr_code_2_rounded),
                  ),
                ),
                const SizedBox(height: DesignSpacing.md),
                FilledButton(
                  onPressed: _use,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Use this code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
