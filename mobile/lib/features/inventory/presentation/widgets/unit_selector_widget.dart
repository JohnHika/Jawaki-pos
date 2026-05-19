import 'package:flutter/material.dart';
import '../../../../core/theme/design_system.dart';

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

/// Unit Selector Widget - Premium toggle/tab design
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
      // Only base unit available, show as premium badge
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              DesignColors.brand.withValues(alpha:0.1),
              DesignColors.brand.withValues(alpha:0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: DesignColors.brand.withValues(alpha:0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.straighten_rounded,
                size: 16, color: DesignColors.brand),
            const SizedBox(width: 6),
            Text(
              unitConfig.baseUnit,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DesignColors.brand,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Premium segmented control style unit selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: DesignColors.surfaceBorder.withValues(alpha:0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: units.map((unit) {
              final isSelected = selectedUnit == unit.name;
              return Expanded(
                child: AnimatedContainer(
                  duration: DesignAnimation.fast,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [
                              DesignColors.brand,
                              DesignColors.brandDark,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: GestureDetector(
                    onTap: () => onUnitChanged(unit.name),
                    child: Text(
                      unit.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : DesignColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Conversion info
        if (showConversionInfo &&
            selectedUnit != unitConfig.baseUnit) ...[
          const SizedBox(height: 10),
          _buildConversionInfo(),
        ],
      ],
    );
  }

  Widget _buildConversionInfo() {
    final selectedUnitOption = unitConfig.availableUnits.firstWhere(
      (unit) => unit.name == selectedUnit,
      orElse: () =>
          UnitOption(name: selectedUnit, conversionFactor: 1.0),
    );

    if (selectedUnitOption.conversionFactor == 1.0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DesignColors.brand.withValues(alpha:0.08),
            DesignColors.brand.withValues(alpha:0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DesignColors.brand.withValues(alpha:0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: DesignColors.brand,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '1 $selectedUnit = ${selectedUnitOption.conversionFactor} ${unitConfig.baseUnit}',
              style: const TextStyle(
                fontSize: 13,
                color: DesignColors.brand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unit Conversion Calculator Widget - Premium
class UnitConversionCalculator extends StatefulWidget {
  final UnitConfig unitConfig;
  final Function(
      double baseQuantity, String unit, double inputQuantity) onCalculated;

  const UnitConversionCalculator({
    super.key,
    required this.unitConfig,
    required this.onCalculated,
  });

  @override
  State<UnitConversionCalculator> createState() =>
      _UnitConversionCalculatorState();
}

class _UnitConversionCalculatorState
    extends State<UnitConversionCalculator> {
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
      orElse: () =>
          UnitOption(name: _selectedUnit, conversionFactor: 1.0),
    );

    final baseQty = input * unitOption.conversionFactor;
    setState(() => _convertedQuantity = baseQty);

    // Notify parent
    widget.onCalculated(baseQty, _selectedUnit, input);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 14,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calculate_rounded,
                    size: 18, color: DesignColors.brand),
              ),
              const SizedBox(width: 10),
              const Text(
                'Unit Conversion',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DesignColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quantity Input with premium unit selector
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    hintStyle:
                        TextStyle(color: DesignColors.textTertiary),
                    labelStyle: const TextStyle(
                      color: DesignColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    floatingLabelBehavior:
                        FloatingLabelBehavior.auto,
                    filled: true,
                    fillColor:
                        DesignColors.surfaceBorder.withValues(alpha:0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: DesignColors.brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color:
                        DesignColors.surfaceBorder.withValues(alpha:0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedUnit,
                      isExpanded: true,
                      dropdownColor: Theme.of(context).brightness ==
                              Brightness.dark
                          ? DesignColors.darkSurface
                          : Colors.white,
                      style: const TextStyle(
                        color: DesignColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      items: widget.unitConfig.availableUnits
                          .map((unit) {
                        return DropdownMenuItem(
                          value: unit.name,
                          child: Text(unit.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(
                              () => _selectedUnit = value);
                          _calculateConversion();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Conversion Result
          if (_convertedQuantity != null &&
              _selectedUnit != widget.unitConfig.baseUnit) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.brand.withValues(alpha:0.08),
                    DesignColors.brand.withValues(alpha:0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: DesignColors.brand.withValues(alpha:0.2),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.arrow_downward_rounded,
                        color: DesignColors.brand,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Converts to',
                        style: TextStyle(
                          fontSize: 12,
                          color: DesignColors.brand,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_convertedQuantity!.toStringAsFixed(_convertedQuantity! % 1 == 0 ? 0 : 2)} ${widget.unitConfig.baseUnit}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: DesignColors.brand,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Quick reference
          if (widget.unitConfig.availableUnits.length > 1) ...[
            const SizedBox(height: 16),
            const Text(
              'Quick Reference',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DesignColors.textTertiary,
                letterSpacing: 0.5,
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
                            Icons.arrow_right_rounded,
                            size: 18,
                            color: DesignColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '1 ${unit.name} = ${unit.conversionFactor} ${widget.unitConfig.baseUnit}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: DesignColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )),
          ],
        ],
      ),
    );
  }
}
