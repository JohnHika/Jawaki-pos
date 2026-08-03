import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  String? _lastScannedBarcode;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    if (_isProcessing || barcode == _lastScannedBarcode) return;

    _isProcessing = true;
    _lastScannedBarcode = barcode;

    // Haptic feedback
    getIt<HapticService>().success();

    // Show processing dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(dialogContext).brightness == Brightness.dark
              ? DesignColors.darkSurface
              : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: DesignColors.brand),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Searching...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: DesignColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Barcode: $barcode',
                        style: const TextStyle(
                            fontSize: 12, color: DesignColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    try {
      final db = getIt<AppDatabase>();

      // Look up product by exact SKU match
      final results = await (db.select(db.products)
            ..where((p) => p.sku.equals(barcode)))
          .get();

      if (!mounted) return;

      // Close the processing dialog
      Navigator.pop(context);

      if (results.isNotEmpty) {
        final product = results.first;
        // Navigate to product detail screen
        context.pop();
        context.push('/products/${product.id}');
      } else {
        // Product not found - show error and let user scan again
        _lastScannedBarcode = null;
        getIt<HapticService>().error();

        showGlassSnackBar(
          context,
          'No product found with barcode: $barcode',
          icon: Icons.search_off_rounded,
          color: DesignColors.error,
        );
      }
    } catch (e) {
      if (!mounted) return;

      // Close the processing dialog
      Navigator.pop(context);

      _lastScannedBarcode = null;
      getIt<HapticService>().error();

      showGlassSnackBar(
        context,
        "Couldn't look up that product. Try again.",
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Scan Barcode',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller!,
            builder: (context, state, child) {
              if (state.torchState == TorchState.on) {
                return IconButton(
                  icon: const Icon(Icons.flash_on_rounded, color: Colors.amber),
                  onPressed: () => _controller?.toggleTorch(),
                );
              }
              return IconButton(
                icon: const Icon(Icons.flash_off_rounded, color: Colors.grey),
                onPressed: () => _controller?.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera feed
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _handleBarcodeScan(barcode.rawValue!);
                  break;
                }
              }
            },
          ),

          // Overlay with scan area
          CustomPaint(
            painter: ScannerOverlayPainter(),
            size: Size.infinite,
          ),

          // Instructions at bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: const Text(
                    'Align barcode within the frame to scan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.qr_code_scanner_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Auto-detect',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for scanner overlay
class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final scanAreaSize = size.width * 0.7;
    final scanAreaOffset = Offset(
      (size.width - scanAreaSize) / 2,
      (size.height - scanAreaSize) / 2 - 50,
    );

    // Draw dark overlay
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Cut out scan area
    final scanArea = Rect.fromLTWH(
      scanAreaOffset.dx,
      scanAreaOffset.dy,
      scanAreaSize,
      scanAreaSize,
    );

    // Create cutout path
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(scanArea);

    canvas.drawPath(
      path..fillType = PathFillType.evenOdd,
      Paint()
        ..color = Colors.transparent
        ..blendMode = BlendMode.clear,
    );

    // Draw scan area border
    final borderPaint = Paint()
      ..color = DesignColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Draw corners
    const cornerLength = 30.0;
    canvas.drawLine(
      Offset(scanAreaOffset.dx, scanAreaOffset.dy + cornerLength),
      Offset(scanAreaOffset.dx, scanAreaOffset.dy),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scanAreaOffset.dx, scanAreaOffset.dy),
      Offset(scanAreaOffset.dx + cornerLength, scanAreaOffset.dy),
      borderPaint,
    );

    canvas.drawLine(
      Offset(
          scanAreaOffset.dx + scanAreaSize - cornerLength, scanAreaOffset.dy),
      Offset(scanAreaOffset.dx + scanAreaSize, scanAreaOffset.dy),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scanAreaOffset.dx + scanAreaSize, scanAreaOffset.dy),
      Offset(
          scanAreaOffset.dx + scanAreaSize, scanAreaOffset.dy + cornerLength),
      borderPaint,
    );

    canvas.drawLine(
      Offset(scanAreaOffset.dx + scanAreaSize,
          scanAreaOffset.dy + scanAreaSize - cornerLength),
      Offset(
          scanAreaOffset.dx + scanAreaSize, scanAreaOffset.dy + scanAreaSize),
      borderPaint,
    );
    canvas.drawLine(
      Offset(
          scanAreaOffset.dx + scanAreaSize, scanAreaOffset.dy + scanAreaSize),
      Offset(scanAreaOffset.dx + scanAreaSize - cornerLength,
          scanAreaOffset.dy + scanAreaSize),
      borderPaint,
    );

    canvas.drawLine(
      Offset(
          scanAreaOffset.dx + cornerLength, scanAreaOffset.dy + scanAreaSize),
      Offset(scanAreaOffset.dx, scanAreaOffset.dy + scanAreaSize),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scanAreaOffset.dx, scanAreaOffset.dy + scanAreaSize),
      Offset(
          scanAreaOffset.dx, scanAreaOffset.dy + scanAreaSize - cornerLength),
      borderPaint,
    );

    // Draw scanning line animation
    final linePaint = Paint()
      ..color = DesignColors.brand.withValues(alpha: 0.5)
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(scanAreaOffset.dx + 10, scanAreaOffset.dy + scanAreaSize / 2),
      Offset(scanAreaOffset.dx + scanAreaSize - 10,
          scanAreaOffset.dy + scanAreaSize / 2),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
