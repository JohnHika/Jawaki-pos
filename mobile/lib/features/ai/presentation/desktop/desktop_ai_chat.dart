import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// One "do this" row on the empty Axon AI page.
class DesktopAiAction {
  const DesktopAiAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// A small tag such as "Photo" for the rows that open the camera.
  final String? badge;
}

/// A quick question shown as a chip above the message box.
class DesktopAiChip {
  const DesktopAiChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Widest the conversation column grows. A line of chat text stays readable
/// and a reply never stretches across the window.
const double desktopAiColumnWidth = 760;

/// The Axon AI page on a computer: a header, then one centred column with the
/// conversation scrolling above and the message box docked at the bottom.
///
/// It only lays things out. The routed screen owns the conversation, the
/// service and every action and hands in the pieces.
class DesktopAiPage extends StatelessWidget {
  const DesktopAiPage({
    super.key,
    required this.title,
    required this.conversation,
    required this.composer,
    this.subtitle,
    this.chips = const [],
    this.chipsEnabled = true,
    this.todos,
    this.slashSuggestions,
    this.onMemory,
    this.onExport,
    this.onNewConversation,
    this.isGenerating = false,
    this.onStop,
  });

  final String title;
  final String? subtitle;

  /// The welcome list or the message list. Takes the leftover height.
  final Widget conversation;

  /// The docked message box.
  final Widget composer;
  final List<DesktopAiChip> chips;

  /// False while a reply is being written, so a second question cannot start.
  final bool chipsEnabled;

  /// The assistant's task checklist, when it is tracking a multi-step job.
  final Widget? todos;

  /// The "/" skill list, shown instead of the chips while the person types "/".
  final Widget? slashSuggestions;
  final VoidCallback? onMemory;
  final VoidCallback? onExport;
  final VoidCallback? onNewConversation;
  final bool isGenerating;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle: subtitle,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
          actions: [
            if (onExport != null)
              IconButton(
                tooltip: 'Export conversation',
                onPressed: onExport,
                icon: const Icon(Icons.ios_share_rounded, size: 19),
              ),
            if (onMemory != null)
              OutlinedButton.icon(
                style: desktopSecondaryButton(context),
                onPressed: onMemory,
                icon: const Icon(Icons.psychology_alt_outlined, size: 17),
                label: const Text('Workspace memory'),
              ),
            if (onNewConversation != null)
              OutlinedButton.icon(
                style: desktopSecondaryButton(context),
                onPressed: onNewConversation,
                icon: const Icon(Icons.add_comment_outlined, size: 17),
                label: const Text('New conversation'),
              ),
          ],
        ),
        Divider(height: 1, color: context.desktop.border),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: desktopAiColumnWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (todos != null) todos!,
                    Expanded(child: conversation),
                    if (slashSuggestions != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: slashSuggestions!,
                      )
                    else if (chips.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ChipRow(chips: chips, enabled: chipsEnabled),
                      ),
                    if (isGenerating && onStop != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Tooltip(
                            message: 'Stop generation',
                            child: OutlinedButton.icon(
                              key: const ValueKey('desktop-ai-stop-generation'),
                              style: desktopSecondaryButton(context),
                              onPressed: onStop,
                              icon: const Icon(Icons.stop_rounded, size: 17),
                              label: const Text('Stop generating'),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: composer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips, required this.enabled});

  final List<DesktopAiChip> chips;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final chip in chips)
            Material(
              color: Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: p.border)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                hoverColor: p.hover,
                onTap: enabled ? chip.onTap : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(chip.icon, size: 15, color: p.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        chip.label,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the Axon AI page shows before the first question: a short greeting and
/// a list of things the assistant can do for the shop right now. Left aligned
/// and compact, not a hero.
class DesktopAiWelcome extends StatelessWidget {
  const DesktopAiWelcome({
    super.key,
    required this.greeting,
    required this.actions,
    this.icon,
  });

  final String greeting;
  final List<DesktopAiAction> actions;

  /// The assistant's avatar, drawn at 36px.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final pairs = <List<DesktopAiAction>>[
      for (var i = 0; i < actions.length; i += 2)
        actions.sublist(i, i + 2 > actions.length ? actions.length : i + 2),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.selected,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: icon,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ask about sales, stock, debts or prices, or start from one of these.',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DesktopPanel(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              children: [
                for (var r = 0; r < pairs.length; r++) ...[
                  if (r > 0) Divider(height: 1, color: p.border),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _ActionRow(action: pairs[r][0])),
                        VerticalDivider(width: 1, color: p.border),
                        Expanded(
                          child: pairs[r].length > 1
                              ? _ActionRow(action: pairs[r][1])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Type / in the message box to see every skill. The assistant cannot see customer records or change anything.',
            style: GoogleFonts.plusJakartaSans(
              color: p.textFaint,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final DesktopAiAction action;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return InkWell(
      onTap: action.onTap,
      hoverColor: p.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(action.icon, size: 19, color: p.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          action.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (action.badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: p.selected,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            action.badge!,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.text,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    action.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown instead of the conversation when the gateway key is missing (or being
/// checked): says what happened and what to do, with the page header above.
class DesktopAiSetupNeeded extends StatelessWidget {
  const DesktopAiSetupNeeded({
    super.key,
    required this.title,
    required this.checking,
    required this.canManage,
    required this.onOpenSettings,
    required this.onOpenMemory,
  });

  final String title;
  final bool checking;
  final bool canManage;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMemory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
        ),
        Divider(height: 1, color: context.desktop.border),
        Expanded(
          child: DesktopEmptyState(
            icon: Icons.hub_rounded,
            title: checking
                ? 'Checking Axon AI setup'
                : 'Connect Axon AI on this computer',
            message: checking
                ? 'Looking at this computer’s secure settings. Nothing is being sent.'
                : canManage
                    ? 'Add the owner-issued key in settings to use AI. Nothing is sent until a key is saved, and read-only shop details go out only when needed to answer a question.'
                    : 'Ask the shop owner to add the Axon AI key on this computer. No question or shop data has been sent.',
            action: checking
                ? null
                : Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canManage)
                        FilledButton.icon(
                          style: desktopPrimaryButton(context),
                          onPressed: onOpenSettings,
                          icon: const Icon(Icons.key_rounded, size: 17),
                          label: const Text('Open key settings'),
                        ),
                      OutlinedButton.icon(
                        style: desktopSecondaryButton(context),
                        onPressed: onOpenMemory,
                        icon:
                            const Icon(Icons.psychology_alt_outlined, size: 17),
                        label: const Text('Workspace memory'),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
