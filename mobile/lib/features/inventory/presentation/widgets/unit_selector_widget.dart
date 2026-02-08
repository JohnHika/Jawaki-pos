import 'package:flutter/material.dart';

/// Unit configuration model
class UnitConfig {
  final String baseUnit;
  final String? secondaryUnit;
  final double? secondaryUnitQty;
  final String? tertiaryUnit;
  final double? tertiaryUnitQty;

  UnitConfig({
    required this.baseUnit,
    this.secondaryUnit,
    this.secondaryUnitQty,
    this.tertiaryUnit,
    this.tertiaryUnitQty,
  });

  List<UnitOption> get availableUnits {
    final units = <UnitOption>[
      UnitOption(name: baseUnit, conversionFactor: 1.0),
    ];

    if (secondaryUnit != null && secondaryUnitQty != null) {
      units.add(UnitOption(
        name: secondaryUnit!,
        conversionFactor: secondaryUnitQty!,
      ));
    }

    if (tertiaryUnit != null && tertiaryUnitQty != null) {
      units.add(UnitOption(
        name: tertiaryUnit!,
        conversionFactor: tertiaryUnitQty!,
      ));
    }

    return units;
  }
}

/// Individual unit option with conversion factor
class UnitOption {
  final String name;
  final double conversionFactor;

  UnitOption({
    required this.name,
    required this.conversionFactor,
  });
}

/// Unit Selector Widget - Allows selecting from available units
class UnitSelectorWidget extends StatelessWidget {
  final UnitConfig unitConfig;
  final String selectedUnit;
  final ValueChanged<String> onUnitChanged;
  final bool showConversionInfo;

  const UnitSelectorWidget({
    super.key,
    required this.unitConfig,
    required this.selectedUnit,
    required this.onUnitChanged,
    this.showConversionInfo = true,
  });

  @override
  Widget build(BuildContext context) {
    final units = unitConfig.availableUnits;

    if (units.length == 1) {
      // Only base unit available, show as text
      return Text(
        unitConfig.baseUnit,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).hintColor,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Unit selector chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: units.map((unit) {
            final isSelected = selectedUnit == unit.name;

            return ChoiceChip(
              label: Text(unit.name),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  onUnitChanged(unit.name);
                }
              },
            );
          }).toList(),
        ),

        // Conversion info
        if (showConversionInfo && selectedUnit != unitConfig.baseUnit) ...[
          const SizedBox(height: 8),
          _buildConversionInfo(context),
        ],
      ],
    );
  }

  Widget _buildConversionInfo(BuildContext context) {
    final selectedUnitOption = unitConfig.availableUnits.firstWhere(
      (unit) => unit.name == selectedUnit,
      orElse: () => UnitOption(name: selectedUnit, conversionFactor: 1.0),
    );

    if (selectedUnitOption.conversionFactor == 1.0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '1 $selectedUnit = ${selectedUnitOption.conversionFactor} ${unitConfig.baseUnit}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unit Conversion Calculator Widget
class UnitConversionCalculator extends StatefulWidget {
  final UnitConfig unitConfig;
  final Function(double baseQuantity, String unit, double inputQuantity) onCalculated;

  const UnitConversionCalculator({
    super.key,
    required this.unitConfig,
    required this.onCalculated,
  });

  @override
  State<UnitConversionCalculator> createState() => _UnitConversionCalculatorState();
}

class _UnitConversionCalculatorState extends State<UnitConversionCalculator> {
  late String _selectedUnit;
  final _quantityController = TextEditingController();
  double? _convertedQuantity;

  @override
  void initState() {
    super.initState();
    _selectedUnit = widget.unitConfig.baseUnit;
    _quantityController.addListener(_calculateConversion);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _calculateConversion() {
    final input = double.tryParse(_quantityController.text);
    if (input == null || input <= 0) {
      setState(() => _convertedQuantity = null);
      return;
    }

    final unitOption = widget.unitConfig.availableUnits.firstWhere(
      (unit) => unit.name == _selectedUnit,
      orElse: () => UnitOption(name: _selectedUnit, conversionFactor: 1.0),
    );

    final baseQty = input * unitOption.conversionFactor;
    setState(() => _convertedQuantity = baseQty);

    // Notify parent
    widget.onCalculated(baseQty, _selectedUnit, input);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calculate, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Unit Conversion',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quantity Input
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),

                // Unit Selector Dropdown
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: widget.unitConfig.availableUnits.map((unit) {
                      return DropdownMenuItem(
                        value: unit.name,
                        child: Text(unit.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedUnit = value);
                        _calculateConversion();
                      }
                    },
                  ),
                ),
              ],
            ),

            // Conversion Result
            if (_convertedQuantity != null && _selectedUnit != widget.unitConfig.baseUnit) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor.withOpacity(0.1),
                      Theme.of(context).primaryColor.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Converts to',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_convertedQuantity!.toStringAsFixed(_convertedQuantity! % 1 == 0 ? 0 : 2)} ${widget.unitConfig.baseUnit}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Example conversions
            if (widget.unitConfig.availableUnits.length > 1) ...[
              const SizedBox(height: 16),
              Text(
                'Quick Reference:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.unitConfig.availableUnits
                  .where((u) => u.conversionFactor != 1.0)
                  .map((unit) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.arrow_right,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '1 ${unit.name} = ${unit.conversionFactor} ${widget.unitConfig.baseUnit}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      )),
            ],
          ],
        ),
      ),
    );
  }
}
