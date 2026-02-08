import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../widgets/unit_selector_widget.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/api_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';

/// Enhanced Batch Receive Screen with Multi-Unit Support
/// Supervisors can receive stock in cartons/boxes and auto-convert to pieces
class BatchReceiveScreen extends ConsumerStatefulWidget {
  final String productId;
  final String productName;
  final String branchId;

  const BatchReceiveScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.branchId,
  });

  @override
  ConsumerState<BatchReceiveScreen> createState() => _BatchReceiveScreenState();
}

class _BatchReceiveScreenState extends ConsumerState<BatchReceiveScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<BatchEntry> _batches = [];
  bool _isLoading = false;
  bool _isLoadingConfig = true;

  // Product unit configuration - loaded from API
  UnitConfig? _unitConfig;

  @override
  void initState() {
    super.initState();
    _loadProductConfig();
    // Start with one empty batch
    _addBatch();
  }

  Future<void> _loadProductConfig() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final product = await apiClient.getProduct(widget.productId);
      
      if (mounted) {
        setState(() {
          _unitConfig = UnitConfig(
            baseUnit: product['unit'] ?? 'piece',
            secondaryUnit: product['secondaryUnit'],
            secondaryUnitQty: product['secondaryUnitQty']?.toDouble(),
            tertiaryUnit: product['tertiaryUnit'],
            tertiaryUnitQty: product['tertiaryUnitQty']?.toDouble(),
          );
          _isLoadingConfig = false;
        });
      }
    } catch (e) {
      // Fallback to basic unit config if API fails
      if (mounted) {
        setState(() {
          _unitConfig = UnitConfig(
            baseUnit: 'piece',
            secondaryUnit: null,
            secondaryUnitQty: null,
            tertiaryUnit: null,
            tertiaryUnitQty: null,
          );
          _isLoadingConfig = false;
        });
      }
      debugPrint('Error loading product config: $e');
    }
  }

  void _addBatch() {
    if (_unitConfig == null) return; // Don't add batch until config is loaded
    
    setState(() {
      _batches.add(BatchEntry(
        batchNumberController: TextEditingController(),
        quantityController: TextEditingController(),
        costPriceController: TextEditingController(),
        notesController: TextEditingController(),
        supplierRefController: TextEditingController(),
        selectedUnit: _unitConfig!.baseUnit,
      ));
    });
  }

  void _removeBatch(int index) {
    if (_batches.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one batch is required')),
      );
      return;
    }

    setState(() {
      _batches[index].dispose();
      _batches.removeAt(index);
    });
  }

  Future<void> _submitBatches() async {
    if (!_formKey.currentState!.validate()) return;

    if (_batches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one batch')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Prepare batches for API
      final batchesData = _batches.map((batch) {
        final quantity = double.parse(batch.quantityController.text);
        final unitOption = _unitConfig!.availableUnits.firstWhere(
          (u) => u.name == batch.selectedUnit,
          orElse: () => UnitOption(name: batch.selectedUnit, conversionFactor: 1.0),
        );

        return {
          'batchNumber': batch.batchNumberController.text,
          'quantity': quantity,
          'unit': batch.selectedUnit,
          'unitsPerQuantity': unitOption.conversionFactor,
          'expiryDate': batch.expiryDate?.toIso8601String(),
          'manufactureDate': batch.manufactureDate?.toIso8601String(),
          'costPrice': batch.costPriceController.text.isEmpty
              ? null
              : double.parse(batch.costPriceController.text),
          'supplierRef': batch.supplierRefController.text.isEmpty
              ? null
              : batch.supplierRefController.text,
          'notes': batch.notesController.text.isEmpty
              ? null
              : batch.notesController.text,
        };
      }).toList();

      // Call API to receive batches
      final apiClient = ref.read(apiClientProvider);
      await apiClient.receiveBatches({
        'branchId': widget.branchId,
        'productId': widget.productId,
        'batches': batchesData,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Batches received successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error receiving batches: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    for (var batch in _batches) {
      batch.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConfig || _unitConfig == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Receive Stock'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add another batch',
            onPressed: _addBatch,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Product Info Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.productName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Base Unit: ${_unitConfig.baseUnit}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (_unitConfig.availableUnits.length > 1) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _unitConfig.availableUnits
                          .where((u) => u.conversionFactor != 1.0)
                          .map((unit) => Chip(
                                label: Text(
                                  '1 ${unit.name} = ${unit.conversionFactor} ${_unitConfig.baseUnit}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),

            // Batch List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _batches.length,
                itemBuilder: (context, index) {
                  return _buildBatchCard(index);
                },
              ),
            ),

            // Submit Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Summary
                    if (_batches.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Batches:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '${_batches.length}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Submit Button
                    FilledButton(
                      onPressed: _isLoading ? null : _submitBatches,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Receive Batches'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchCard(int index) {
    final batch = _batches[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with batch number and delete button
            Row(
              children: [
                Text(
                  'Batch ${index + 1}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_batches.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeBatch(index),
                    tooltip: 'Remove batch',
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Batch Number
            TextFormField(
              controller: batch.batchNumberController,
              decoration: const InputDecoration(
                labelText: 'Batch Number *',
                hintText: 'e.g., BTH-2024-001',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Batch number is required';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Quantity with Unit Selector
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: batch.quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Invalid';
                      }
                      if (double.parse(value) <= 0) {
                        return 'Must be > 0';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: batch.selectedUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: _unitConfig.availableUnits.map((unit) {
                      return DropdownMenuItem(
                        value: unit.name,
                        child: Text(unit.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => batch.selectedUnit = value);
                      }
                    },
                  ),
                ),
              ],
            ),

            // Conversion Preview
            if (batch.quantityController.text.isNotEmpty &&
                batch.selectedUnit != _unitConfig.baseUnit) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calculate,
                      size: 18,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getConversionText(batch),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Expiry Date
            InkWell(
              onTap: () => _selectDate(context, batch, isExpiry: true),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Expiry Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  batch.expiryDate == null
                      ? 'Select date'
                      : DateFormat('MMM d, yyyy').format(batch.expiryDate!),
                  style: TextStyle(
                    color: batch.expiryDate == null
                        ? Theme.of(context).hintColor
                        : null,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Collapsible Additional Details
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text('Additional Details (Optional)'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                children: [
                  // Manufacture Date
                  InkWell(
                    onTap: () => _selectDate(context, batch, isExpiry: false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Manufacture Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        batch.manufactureDate == null
                            ? 'Select date'
                            : DateFormat('MMM d, yyyy').format(batch.manufactureDate!),
                        style: TextStyle(
                          color: batch.manufactureDate == null
                              ? Theme.of(context).hintColor
                              : null,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Cost Price
                  TextFormField(
                    controller: batch.costPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Cost Price per ${_unitConfig.baseUnit}',
                      border: OutlineInputBorder(),
                      prefixText: '\$',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),

                  const SizedBox(height: 16),

                  // Supplier Reference
                  TextFormField(
                    controller: batch.supplierRefController,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Reference / Invoice #',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notes
                  TextFormField(
                    controller: batch.notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      hintText: 'Any additional notes...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getConversionText(BatchEntry batch) {
    if (_unitConfig == null) return '';
    
    final qty = double.tryParse(batch.quantityController.text);
    if (qty == null) return '';

    final unitOption = _unitConfig!.availableUnits.firstWhere(
      (u) => u.name == batch.selectedUnit,
      orElse: () => UnitOption(name: batch.selectedUnit, conversionFactor: 1.0),
    );

    final baseQty = qty * unitOption.conversionFactor;
    return '= ${baseQty.toStringAsFixed(baseQty % 1 == 0 ? 0 : 2)} ${_unitConfig!.baseUnit}';
  }

  Future<void> _selectDate(BuildContext context, BatchEntry batch, {required bool isExpiry}) async {
    final initialDate = isExpiry ? batch.expiryDate : batch.manufactureDate;
    
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: isExpiry ? DateTime.now() : DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (date != null) {
      setState(() {
        if (isExpiry) {
          batch.expiryDate = date;
        } else {
          batch.manufactureDate = date;
        }
      });
    }
  }
}

/// Batch Entry Data Model
class BatchEntry {
  final TextEditingController batchNumberController;
  final TextEditingController quantityController;
  final TextEditingController costPriceController;
  final TextEditingController notesController;
  final TextEditingController supplierRefController;
  String selectedUnit;
  DateTime? expiryDate;
  DateTime? manufactureDate;

  BatchEntry({
    required this.batchNumberController,
    required this.quantityController,
    required this.costPriceController,
    required this.notesController,
    required this.supplierRefController,
    required this.selectedUnit,
    this.expiryDate,
    this.manufactureDate,
  });

  void dispose() {
    batchNumberController.dispose();
    quantityController.dispose();
    costPriceController.dispose();
    notesController.dispose();
    supplierRefController.dispose();
  }
}
