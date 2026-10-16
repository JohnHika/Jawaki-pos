import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/design_system.dart';

/// Small building blocks shared by the data-entry screens (add customer,
/// receive stock, request stock) so they look and behave the same way.

/// A filled, rounded field whose label always sits above the text, so the
/// hint ("e.g. 24") stays visible instead of being hidden by a large label.
InputDecoration kitFieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  String? prefixText,
  String? suffixText,
  IconData? prefixIcon,
  String? helper,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final secondary =
      isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
  final tertiary =
      isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
  final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
  final fill = isDark
      ? DesignColors.darkSurfaceElevated
      : DesignColors.surfaceBorder.withValues(alpha: 0.15);

  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 2,
    errorMaxLines: 2,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    labelStyle: TextStyle(color: secondary, fontWeight: FontWeight.w600),
    hintStyle: TextStyle(color: tertiary),
    helperStyle: TextStyle(color: tertiary, fontSize: 12),
    prefixText: prefixText,
    prefixStyle: TextStyle(color: secondary, fontWeight: FontWeight.w700),
    suffixText: suffixText,
    suffixStyle:
        const TextStyle(color: DesignColors.brand, fontWeight: FontWeight.w700),
    prefixIcon:
        prefixIcon == null ? null : Icon(prefixIcon, color: tertiary, size: 20),
    filled: true,
    fillColor: fill,
    border: outline(border),
    enabledBorder: outline(border),
    focusedBorder: outline(DesignColors.brand, 1.6),
    errorBorder: outline(DesignColors.error),
    focusedErrorBorder: outline(DesignColors.error, 1.6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

/// Trims "24.0" to "24" so a quantity reads like something a person typed.
String kitNumber(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

/// "1 piece", "24 pieces": a count with its unit, pluralised the simple way.
String kitCount(num value, String unit) {
  final plural = value == 1 || unit.endsWith('s') ? unit : '${unit}s';
  return '${kitNumber(value)} $plural';
}

/// A row of "+5 +10 +20" pills that add to a number field, so a shopkeeper can
/// reach a typical amount with a tap instead of the keyboard.
class QuickAddChips extends StatelessWidget {
  const QuickAddChips({
    super.key,
    required this.amounts,
    required this.onAdd,
    this.prefix = '+',
  });

  final List<int> amounts;
  final ValueChanged<int> onAdd;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final amount in amounts)
          _Pill(
            key: ValueKey('quick-$amount'),
            label: '$prefix$amount',
            onTap: () {
              HapticFeedback.selectionClick();
              onAdd(amount);
            },
          ),
      ],
    );
  }
}

/// Adds [amount] to whatever number is in [controller] (blank counts as 0).
void kitAddToField(TextEditingController controller, int amount) {
  final current = double.tryParse(controller.text.trim()) ?? 0;
  final next = current + amount;
  final text = kitNumber(next);
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      child: Material(
        color: DesignColors.accent.withValues(alpha: 0.1),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 56),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: DesignColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice shown as a pill that fills when selected, for short fixed lists
/// (priority, quick reasons, due dates) where a dropdown hides the options.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = DesignColors.accent,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleText =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final idleBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      child: Material(
        color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? color : idleBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: selected ? color : idleText),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? color : idleText,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14,
                      ),
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

/// A short label above a group of fields.
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          children: [
            if (trailing != null)
              TextSpan(
                text: '  $trailing',
                style: TextStyle(
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The action bar pinned under a form: it stays visible above the keyboard,
/// so the main button is never scrolled out of reach.
class PinnedActionBar extends StatelessWidget {
  const PinnedActionBar({super.key, required this.child, this.summary});

  final Widget child;

  /// A line of context above the button, such as "Adding 24 pieces".
  final Widget? summary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary != null) ...[summary!, const SizedBox(height: 10)],
          child,
        ],
      ),
    );
  }
}
