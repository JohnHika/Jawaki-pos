import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// SharedPreferences keys for printer settings — shared between
/// settings_screen.dart (where they're set) and receipt_screen.dart
/// (where they're read to print), so the two never drift apart.
class PrinterSettingsKeys {
  static const autoPrint = 'setting_auto_print_receipt';
  static const printerName = 'setting_printer_name';
  static const printerMacAddress = 'setting_printer_mac_address';
  static const paperWidth = 'setting_paper_width';
}

/// One paired Bluetooth device, surfaced to the printer settings UI for
/// the user to pick from — the OS pairing dialog handles the actual
/// Bluetooth pairing step; this only lists devices already paired.
class PairedPrinter {
  final String name;
  final String macAddress;

  const PairedPrinter({required this.name, required this.macAddress});
}

class PrinterUnavailableException implements Exception {
  final String message;
  const PrinterUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Thin wrapper around print_bluetooth_thermal (Bluetooth Classic
/// transport) + esc_pos_utils (ESC/POS command generation) — the printer
/// settings UI previously saved a printer name/paper width to
/// SharedPreferences but nothing ever used them to actually print.
class ReceiptPrinterService {
  Future<bool> get isBluetoothEnabled => PrintBluetoothThermal.bluetoothEnabled;

  /// Checks only — never prompts (print_bluetooth_thermal has no request
  /// path of its own). Use [requestPermission] to actually prompt.
  Future<bool> get hasPermission => PrintBluetoothThermal.isPermissionBluetoothGranted;

  /// Prompts for the Bluetooth runtime permissions Android 12+ requires
  /// (BLUETOOTH_CONNECT/BLUETOOTH_SCAN). Returns true once granted.
  Future<bool> requestPermission() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// Already-paired Bluetooth devices — pairing itself happens in the
  /// phone's Bluetooth settings, same as any other Bluetooth accessory.
  Future<List<PairedPrinter>> getPairedPrinters() async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices
        .map((d) => PairedPrinter(name: d.name, macAddress: d.macAdress))
        .toList();
  }

  Future<bool> connect(String macAddress) {
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }

  /// Builds and sends a formatted receipt to the currently connected
  /// printer. Throws [PrinterUnavailableException] if nothing is
  /// connected or the write fails — callers decide how to surface that
  /// (e.g. fall back to share/on-screen receipt) rather than this service
  /// silently swallowing a failed print.
  Future<void> printReceipt({
    required Map<String, dynamic> receipt,
    required String saleId,
    required String paperWidth,
    bool showTax = true,
  }) async {
    final connected = await isConnected;
    if (!connected) {
      throw const PrinterUnavailableException(
          'No printer connected. Connect a printer in Settings first.');
    }

    final profile = await CapabilityProfile.load();
    final paper = paperWidth == '80mm' ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paper, profile);

    final bytes = <int>[];
    bytes.addAll(generator.reset());

    final branchName = receipt['branchName'] as String? ?? 'POS Store';
    bytes.addAll(generator.text(
      branchName,
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
    ));

    final branchAddress = receipt['branchAddress'] as String?;
    if (branchAddress != null && branchAddress.isNotEmpty) {
      bytes.addAll(generator.text(branchAddress,
          styles: const PosStyles(align: PosAlign.center)));
    }

    bytes.addAll(generator.hr());

    final receiptNumber = receipt['receiptNumber'] as String? ??
        saleId.substring(0, 8).toUpperCase();
    bytes.addAll(generator.text('Receipt #$receiptNumber'));
    final createdAt = receipt['createdAt'];
    if (createdAt != null) {
      bytes.addAll(generator.text(_formatDateTime(createdAt)));
    }
    bytes.addAll(generator.hr());

    final items = (receipt['items'] as List?) ?? [];
    for (final item in items) {
      final name = (item['productName'] ?? '').toString();
      final qty = item['quantity'];
      final total = ((item['total'] as num?) ?? 0).toStringAsFixed(2);
      bytes.addAll(generator.row([
        PosColumn(text: '$qty x $name', width: 8),
        PosColumn(
            text: total, width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]));
    }

    bytes.addAll(generator.hr());

    final subtotal = ((receipt['subtotal'] as num?) ?? 0).toStringAsFixed(2);
    bytes.addAll(_row(generator, 'Subtotal', subtotal));

    final discount = (receipt['discount'] as num?) ?? 0;
    if (discount > 0) {
      bytes.addAll(_row(generator, 'Discount', '-${discount.toStringAsFixed(2)}'));
    }

    final tax = (receipt['tax'] as num?) ?? 0;
    if (showTax && tax > 0) {
      bytes.addAll(_row(generator, 'Tax', tax.toStringAsFixed(2)));
    }

    final total = ((receipt['total'] as num?) ?? 0).toStringAsFixed(2);
    bytes.addAll(generator.row([
      PosColumn(
          text: 'Total',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(
          text: total,
          width: 6,
          styles: const PosStyles(
              align: PosAlign.right, bold: true, height: PosTextSize.size2)),
    ]));

    final paymentMethod = receipt['paymentMethod'] as String? ?? 'CASH';
    bytes.addAll(generator.text('Payment: $paymentMethod'));

    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.text('Thank you for your purchase!',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    final success = await PrintBluetoothThermal.writeBytes(bytes);
    if (!success) {
      throw const PrinterUnavailableException(
          'Printer did not accept the print job. Check it is powered on and in range.');
    }
  }

  List<int> _row(Generator generator, String label, String value) {
    return generator.row([
      PosColumn(text: label, width: 8),
      PosColumn(text: value, width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
  }

  String _formatDateTime(dynamic value) {
    DateTime? dt;
    if (value is String) {
      dt = DateTime.tryParse(value);
    } else if (value is DateTime) {
      dt = value;
    }
    if (dt == null) return '';
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}
