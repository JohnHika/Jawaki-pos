import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'receipt_printer_service.dart';
import '../di/injection.dart';
import '../network/api_client.dart';

/// Coordinates receipt printing when several devices share one Bluetooth
/// thermal printer. Bluetooth Classic only supports a single active
/// connection, so two phones printing straight to the printer at once
/// garbles or drops output — see `PrintJob` on the backend for the full
/// hand-off contract this wraps.
///
/// Every device calls [requestPrint] the same way, regardless of whether
/// it's the one physically holding the Bluetooth connection:
/// - If this device IS the designated printer holder (set in Settings →
///   Receipt Printer → "This device is the printer"), it prints directly
///   via [ReceiptPrinterService], exactly as before.
/// - Otherwise, the receipt is enqueued on the backend and this method
///   returns immediately; the printer-holder device picks it up on its
///   next poll (started via [startDraining], normally once at app launch
///   if this device is the holder) and prints it there.
class PrintQueueService {
  final ApiClient _apiClient;
  final ReceiptPrinterService _printerService;
  Timer? _drainTimer;
  bool _draining = false;

  PrintQueueService({
    required ApiClient apiClient,
    required ReceiptPrinterService printerService,
  })  : _apiClient = apiClient,
        _printerService = printerService;

  String? get _deviceId => getIt<AuthService>().deviceId;

  /// True once this device has been designated (via Settings) as the one
  /// holding the Bluetooth connection to the branch's shared printer.
  Future<bool> isDesignatedPrinter() async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) return false;
    try {
      final printerDeviceId = await _apiClient.getPrinterDevice();
      return printerDeviceId == deviceId;
    } catch (_) {
      return false;
    }
  }

  Future<void> setThisDeviceAsPrinter(bool isDesignated) async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    await _apiClient.setPrinterDevice(isDesignated ? deviceId : null);
    if (isDesignated) {
      startDraining();
    } else {
      stopDraining();
    }
  }

  /// Sends a receipt to print. If this device holds the printer connection,
  /// prints immediately and throws [PrinterUnavailableException] on
  /// failure exactly like [ReceiptPrinterService.printReceipt] always did
  /// (existing call sites' error handling keeps working unchanged). If not,
  /// enqueues the job on the backend and returns normally — the caller
  /// should show "Queued for printing" rather than "Receipt sent to
  /// printer", since it hasn't actually printed yet.
  ///
  /// Returns true if it printed directly on this device, false if it was
  /// only queued for the printer-holder device to pick up.
  Future<bool> requestPrint({
    required Map<String, dynamic> receipt,
    required String saleId,
    required String paperWidth,
    bool showTax = true,
  }) async {
    final deviceId = _deviceId ?? '';
    final designated = deviceId.isNotEmpty && await isDesignatedPrinter();

    if (designated) {
      await _printerService.printReceipt(
        receipt: receipt,
        saleId: saleId,
        paperWidth: paperWidth,
        showTax: showTax,
      );
      return true;
    }

    await _apiClient.enqueuePrintJob(
      deviceId: deviceId,
      payload: {
        'receipt': receipt,
        'saleId': saleId,
        'paperWidth': paperWidth,
        'showTax': showTax,
      },
    );
    return false;
  }

  /// Starts this device polling the backend for jobs to print — call once
  /// this device is confirmed as the printer holder (app startup if already
  /// designated, or right after designating it in Settings). Safe to call
  /// repeatedly; only one timer ever runs.
  void startDraining() {
    _drainTimer?.cancel();
    _drainTimer = Timer.periodic(const Duration(seconds: 4), (_) => _drainOnce());
    _drainOnce();
  }

  void stopDraining() {
    _drainTimer?.cancel();
    _drainTimer = null;
  }

  Future<void> _drainOnce() async {
    if (_draining) return;
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) return;

    _draining = true;
    try {
      final jobs = await _apiClient.claimPrintJobs(deviceId: deviceId);
      for (final job in jobs) {
        await _printClaimedJob(job, deviceId);
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[PrintQueue] Drain error: $e');
    } finally {
      _draining = false;
    }
  }

  /// Jobs print strictly one at a time, in order — never concurrently,
  /// since the Bluetooth connection can only serve one write at a time
  /// anyway. A job that fails is reported as failed and the loop moves on
  /// to the next rather than blocking the whole queue behind one bad job.
  Future<void> _printClaimedJob(Map<String, dynamic> job, String deviceId) async {
    final jobId = job['id'] as String;
    final payload = job['payload'] as Map<String, dynamic>;
    try {
      final receipt = payload['receipt'] as Map<String, dynamic>;
      final saleId = payload['saleId'] as String? ?? '';
      final paperWidth = payload['paperWidth'] as String? ?? '58mm';
      final showTax = payload['showTax'] as bool? ?? true;

      await _printerService.printReceipt(
        receipt: receipt,
        saleId: saleId,
        paperWidth: paperWidth,
        showTax: showTax,
      );
      await _apiClient.completePrintJob(jobId: jobId, deviceId: deviceId, status: 'printed');
    } catch (e) {
      try {
        await _apiClient.completePrintJob(
          jobId: jobId,
          deviceId: deviceId,
          status: 'failed',
          errorMessage: e.toString(),
        );
      } catch (_) {
        // Reporting the failure itself failed (offline, etc.) — the job
        // stays "claimed" and goes stale server-side, becoming reclaimable
        // again automatically rather than stuck forever.
      }
    }
  }
}
