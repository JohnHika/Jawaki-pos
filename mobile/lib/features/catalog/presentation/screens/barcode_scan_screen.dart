import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/design_system.dart';

/// Opens the camera, reads one barcode and returns its text. Nothing is saved
/// or sent anywhere: the caller decides what to do with the number.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key, this.title = 'Scan a barcode'});

  final String title;

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
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
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
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
