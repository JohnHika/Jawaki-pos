import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/design_system.dart';

/// Quick action chips for common AI queries
class AiQuickActions extends StatelessWidget {
  final Function(String prompt) onTap;

  const AiQuickActions({super.key, required this.onTap});

  static const _actions = [
    _QuickAction(
      icon: Icons.trending_up,
      label: 'Sales Today',
      prompt: 'How were my sales today? Give me a summary with key numbers.',
    ),
    _QuickAction(
      icon: Icons.inventory,
      label: 'Low Stock',
      prompt: 'Which products are running low on stock and need reordering?',
    ),
    _QuickAction(
      icon: Icons.people,
      label: 'Top Customers',
      prompt: 'Who are my best customers and what do they buy most?',
    ),
    _QuickAction(
      icon: Icons.attach_money,
      label: 'Profit Analysis',
      prompt: 'Analyze my profit margins. Which products are most profitable?',
    ),
    _QuickAction(
      icon: Icons.receipt_long,
      label: 'Daily Summary',
      prompt: 'Give me a complete summary of today\'s business activity.',
    ),
    _QuickAction(
      icon: Icons.lightbulb,
      label: 'Business Tips',
      prompt: 'Give me tips to increase my store\'s revenue and reduce waste.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _actions.map((action) {
        return ActionChip(
          avatar: Icon(action.icon, size: 16, color: DesignColors.brand),
          label: Text(action.label),
          onPressed: () => onTap(action.prompt),
          backgroundColor: DesignColors.brand.withValues(alpha: 0.1),
          side: BorderSide(color: DesignColors.brand.withValues(alpha: 0.3)),
        );
      }).toList(),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final String prompt;
  const _QuickAction({required this.icon, required this.label, required this.prompt});
}
