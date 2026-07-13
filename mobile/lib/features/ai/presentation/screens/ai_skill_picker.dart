import 'package:flutter/material.dart';

import '../../../../core/theme/design_system.dart';

/// One entry in the slash-skill catalog: a fast, explicit way to trigger one
/// of the gateway's named skill playbooks (axon/pos/skills/*/SKILL.md on the
/// backend) instead of relying on the model to infer intent from free text.
/// [prompt] is plain natural language naming the skill by its trigger
/// phrases — the gateway's skills_loader activation is description-driven,
/// so no backend/gateway protocol change is needed to "pin" a skill; sending
/// its own trigger phrase verbatim is enough to make the match unambiguous.
class AiSkillCommand {
  final String command;
  final String label;
  final String description;
  final IconData icon;
  final String prompt;

  const AiSkillCommand({
    required this.command,
    required this.label,
    required this.description,
    required this.icon,
    required this.prompt,
  });
}

/// Mirrors axon/pos/skills/*/SKILL.md on the gateway (24 skills). Keep in
/// sync if a skill is added/renamed there — this list only decides which
/// slash shortcuts exist in the mobile UI, it doesn't change what the model
/// can already do from plain text.
const List<AiSkillCommand> aiSkillCommands = [
  AiSkillCommand(
    command: 'brief',
    label: 'Daily brief',
    description: "Today's snapshot and the one thing to focus on",
    icon: Icons.wb_sunny_outlined,
    prompt: "Give me my morning brief — how are we doing today.",
  ),
  AiSkillCommand(
    command: 'cashup',
    label: 'Cash up',
    description: "Reconcile today's takings by payment type",
    icon: Icons.point_of_sale_outlined,
    prompt: 'Cash up — reconcile takings for today.',
  ),
  AiSkillCommand(
    command: 'weekly',
    label: 'Weekly review',
    description: 'Full review across sales, profit, stock, debts',
    icon: Icons.calendar_view_week_outlined,
    prompt: 'Give me the weekly review — sum up the week.',
  ),
  AiSkillCommand(
    command: 'profit',
    label: 'Profit check',
    description: 'Are we actually making money after cost',
    icon: Icons.trending_up_rounded,
    prompt: 'Profit check — are we actually making money, not just moving stock.',
  ),
  AiSkillCommand(
    command: 'trend',
    label: 'Sales trend',
    description: 'Growing, flat, or sliding — and by how much',
    icon: Icons.show_chart_rounded,
    prompt: "How's the sales trend — are we growing or sliding.",
  ),
  AiSkillCommand(
    command: 'bestsellers',
    label: 'Best sellers',
    description: "What's moving — top products right now",
    icon: Icons.star_outline_rounded,
    prompt: "What's selling best right now — my top products.",
  ),
  AiSkillCommand(
    command: 'worst',
    label: 'Worst performers',
    description: "What's dragging profit down",
    icon: Icons.trending_down_rounded,
    prompt: "What's dragging me down — worst performers, low margin items.",
  ),
  AiSkillCommand(
    command: 'slowmovers',
    label: 'Slow-mover clearance',
    description: 'Dead stock tying up cash + a clearance plan',
    icon: Icons.inventory_2_outlined,
    prompt: "What's not selling — dead stock, give me a clearance plan.",
  ),
  AiSkillCommand(
    command: 'reorder',
    label: 'Reorder analysis',
    description: 'What to restock now, within budget',
    icon: Icons.local_shipping_outlined,
    prompt: 'What should I reorder — give me a restock list.',
  ),
  AiSkillCommand(
    command: 'stockout',
    label: 'Stockout prevention',
    description: 'Protect fast-moving products from running out',
    icon: Icons.warning_amber_rounded,
    prompt: 'Am I about to run out of anything — protect my best sellers.',
  ),
  AiSkillCommand(
    command: 'inventory',
    label: 'Inventory health',
    description: 'Stock value, out-of-stock gaps, overstock risk',
    icon: Icons.inventory_outlined,
    prompt: "How's my stock — inventory health check.",
  ),
  AiSkillCommand(
    command: 'category',
    label: 'Category performance',
    description: 'Which parts of the shop drive sales and profit',
    icon: Icons.category_outlined,
    prompt: 'Which category sells best — category performance.',
  ),
  AiSkillCommand(
    command: 'margin',
    label: 'Margin improvement',
    description: 'Lift profit without just slashing prices',
    icon: Icons.percent_rounded,
    prompt: 'How do I improve margins without cutting prices.',
  ),
  AiSkillCommand(
    command: 'promo',
    label: 'Promotion planner',
    description: 'Plan a promo grounded in real sales data',
    icon: Icons.campaign_outlined,
    prompt: 'Plan a promotion — what should I promote and when.',
  ),
  AiSkillCommand(
    command: 'peakhours',
    label: 'Peak hours',
    description: 'Busiest and quietest trading times',
    icon: Icons.schedule_rounded,
    prompt: 'When are we busiest — peak hours and quiet times.',
  ),
  AiSkillCommand(
    command: 'payments',
    label: 'Payment mix',
    description: 'Cash vs M-Pesa vs credit split',
    icon: Icons.payments_outlined,
    prompt: "How are people paying — cash vs mpesa vs credit split.",
  ),
  AiSkillCommand(
    command: 'cashflow',
    label: 'Cashflow snapshot',
    description: "Money in vs out, what's tied up",
    icon: Icons.account_balance_wallet_outlined,
    prompt: "How's my cash flow — money in vs out, what's tied up.",
  ),
  AiSkillCommand(
    command: 'expenses',
    label: 'Expense review',
    description: "Where the shop's money is going",
    icon: Icons.receipt_long_outlined,
    prompt: "Where's my money going — review my expenses.",
  ),
  AiSkillCommand(
    command: 'debtors',
    label: 'Debt collection',
    description: 'Who owes money, prioritised by biggest/oldest',
    icon: Icons.request_quote_outlined,
    prompt: 'Who owes me money — prioritise debt collection.',
  ),
  AiSkillCommand(
    command: 'creditrisk',
    label: 'Credit risk review',
    description: 'How exposed the shop is on credit',
    icon: Icons.shield_outlined,
    prompt: 'How much is out on credit — is my credit risk safe.',
  ),
  AiSkillCommand(
    command: 'topcustomers',
    label: 'Top customers',
    description: 'Best customers and loyalty ideas',
    icon: Icons.people_outline_rounded,
    prompt: 'Who are my best customers — my top regulars.',
  ),
  AiSkillCommand(
    command: 'winback',
    label: 'Win back lapsed',
    description: 'Customers who stopped coming',
    icon: Icons.person_off_outlined,
    prompt: 'Who stopped coming — help me win back lapsed customers.',
  ),
  AiSkillCommand(
    command: 'staff',
    label: 'Staff performance',
    description: 'Compare cashiers, spot who needs coaching',
    icon: Icons.badge_outlined,
    prompt: "How are my staff doing — compare my team's performance.",
  ),
  AiSkillCommand(
    command: 'branches',
    label: 'Branch comparison',
    description: 'Which branch is winning and why',
    icon: Icons.store_outlined,
    prompt: 'Compare my branches — which is performing best.',
  ),
];

/// Filters [aiSkillCommands] by a partial command/label match, e.g. typing
/// "/cash" matches both "cashup" and "cashflow". Empty query returns all.
List<AiSkillCommand> filterAiSkillCommands(String query) {
  final q = query.toLowerCase();
  if (q.isEmpty) return aiSkillCommands;
  return aiSkillCommands
      .where((c) =>
          c.command.toLowerCase().contains(q) ||
          c.label.toLowerCase().contains(q))
      .toList();
}

/// Inline suggestion list shown above the input bar while composing a slash
/// command — tapping an entry hands its [AiSkillCommand] back to the caller.
class AiSkillSuggestionList extends StatelessWidget {
  final List<AiSkillCommand> commands;
  final ValueChanged<AiSkillCommand> onSelect;

  const AiSkillSuggestionList({
    super.key,
    required this.commands,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final bodyColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    if (commands.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Text(
          'No matching skill',
          style: TextStyle(color: bodyColor, fontSize: 13),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: commands.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: border),
        itemBuilder: (context, index) {
          final cmd = commands[index];
          return ListTile(
            dense: true,
            leading: Icon(cmd.icon, size: 20, color: DesignColors.accent),
            title: Text(
              '/${cmd.command}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: titleColor,
              ),
            ),
            subtitle: Text(
              cmd.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: bodyColor),
            ),
            onTap: () => onSelect(cmd),
          );
        },
      ),
    );
  }
}
