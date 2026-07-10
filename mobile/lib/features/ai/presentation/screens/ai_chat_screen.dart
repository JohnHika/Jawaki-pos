import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gpt_markdown_lite/gpt_markdown_lite.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/providers/tenant_provider.dart';
import 'ai_chat_service.dart';
import 'ai_add_to_chat_sheet.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiChatService _aiService = AiChatService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pull the shop's shared conversation so every staff member on this
    // shop sees and continues the same thread.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _aiService.loadSharedHistory();
      if (mounted) setState(() {});
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: 300.ms,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    final message = text.trim();
    _controller.clear();

    setState(() => _isLoading = true);
    _scrollToBottom();

    try {
      await _aiService.sendMessage(content: message);
    } on AiSubscriptionRequiredException {
      if (mounted) {
        context.push('/ai/trial', extra: _aiService.branchId);
      }
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  Future<void> _newConversation() async {
    await _aiService.startNewSharedConversation();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    showGlassSnackBar(
      context,
      'Copied to clipboard',
      icon: Icons.check_circle_outline_rounded,
      color: DesignColors.success,
    );
  }

  /// Edit & resubmit: put the message back in the input, drop it and
  /// everything after it from history, so the user can rephrase and send
  /// again from that point.
  void _editMessage(int index, String content) {
    if (_isLoading) return;
    _aiService.truncateFrom(index);
    _controller.text = content;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {});
  }

  Future<void> _openAddToChat() async {
    if (_isLoading) return;
    await showAddToChatSheet(
      context,
      onAttachmentText: (label, extractedText) {
        // Attaching a photo/file surfaces its extracted text into the
        // input so it becomes part of the next question to the AI.
        final existing = _controller.text.trim();
        final block = '[$label]\n$extractedText';
        _controller.text = existing.isEmpty ? block : '$existing\n\n$block';
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _aiService.messages;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Axon AI',
        showBackButton: false,
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'New conversation',
              onPressed: _newConversation,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: messages.isEmpty
                ? _buildWelcomeScreen()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length) {
                        return _buildTypingIndicator();
                      }
                      final msg = messages[index];
                      final isUser = msg['role'] == 'user';
                      final content = msg['content']!;
                      return _ChatBubble(
                        message: content,
                        isUser: isUser,
                        onCopy: isUser ? null : () => _copyMessage(content),
                        onEdit: isUser ? () => _editMessage(index, content) : null,
                      ).animate().fadeIn(duration: 300.ms).slideX(
                            begin: isUser ? 20 : -20,
                            end: 0,
                            duration: 300.ms,
                          );
                    },
                  ),
          ),
          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: AxonAiIcon(
                  tenantLogoUrl: ref.watch(tenantIdentityProvider).logoUrl,
                  size: 44,
                ),
              ),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 20),
            Text(
              'Axon AI Assistant',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 8),
            Text(
              'Your intelligent business companion.\nAsk me anything about your sales, inventory, and customers.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryColor, fontSize: 14),
            ).animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _TypingIndicator(),
      ),
    );
  }

  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted;
    final hintColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final iconColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final hasText = _controller.text.trim().isNotEmpty;

    return Padding(
      // Scaffold's default resizeToAvoidBottomInset already shrinks the
      // body when the keyboard opens, so only the safe-area inset needs
      // adding here — adding viewInsets.bottom too would double-count it
      // and push the bar needlessly high above the keyboard.
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      // A floating rounded pill with no top shadow/divider line — it reads
      // as a compact input control sitting over the content, not a full
      // width toolbar boxed off from the rest of the screen.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(Icons.add_rounded, color: iconColor),
              onPressed: _isLoading ? null : _openAddToChat,
              tooltip: 'Add to chat',
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isLoading,
                minLines: 1,
                maxLines: 6,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: isDark
                      ? DesignColors.darkTextPrimary
                      : DesignColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Message Axon AI...',
                  hintStyle: TextStyle(color: hintColor),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.all(4),
              child: _isLoading
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : GestureDetector(
                      onTap: hasText
                          ? () => _sendMessage(_controller.text)
                          : null,
                      child: AnimatedContainer(
                        duration: 150.ms,
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasText
                              ? DesignColors.accent
                              : (isDark
                                  ? DesignColors.darkBorder
                                  : DesignColors.surfaceBorder),
                        ),
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 18,
                          color: hasText ? Colors.black : hintColor,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends ConsumerWidget {
  final String message;
  final bool isUser;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;

  const _ChatBubble({
    required this.message,
    required this.isUser,
    this.onCopy,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final actionColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: DesignColors.accent.withValues(alpha: 0.15),
              child: AxonAiIcon(
                tenantLogoUrl: ref.watch(tenantIdentityProvider).logoUrl,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  // AI replies get a wider ceiling than user bubbles — a
                  // markdown table needs real horizontal room to render as an
                  // actual table instead of squeezing cells onto separate
                  // wrapped lines.
                  constraints: BoxConstraints(
                    maxWidth: isUser
                        ? MediaQuery.of(context).size.width * 0.78
                        : MediaQuery.of(context).size.width * 0.92,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? DesignColors.accent.withValues(alpha: 0.1)
                          : (isDark
                              ? DesignColors.darkSurfaceElevated
                              : DesignColors.surfaceMuted),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    child: _buildMessageContent(textColor),
                  ),
                ),
                // Per-message actions: copy on AI replies, edit on the
                // user's own messages (standard chat UX).
                _buildActions(context, actionColor),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, Color color) {
    final children = <Widget>[];
    if (!isUser && onCopy != null) {
      children.add(_actionButton(Icons.copy_rounded, 'Copy', onCopy!, color));
    }
    if (isUser && onEdit != null) {
      children.add(_actionButton(Icons.edit_rounded, 'Edit', onEdit!, color));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _actionButton(
      IconData icon, String tooltip, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  Widget _buildMessageContent(Color textColor) {
    // Full markdown rendering (tables, bold, lists, links) instead of the
    // old line-by-line parser, which only understood **bold** and bullet
    // dashes — a markdown table from the AI came through as literal
    // "| Col | Col |" pipe text instead of an actual table.
    if (!isUser) {
      return GptMarkdown(
        message,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          height: 1.5,
        ),
      );
    }

    // User's own messages are always plain text they typed themselves —
    // no need to parse markdown out of them.
    return Text(
      message,
      style: TextStyle(
        color: textColor,
        fontSize: 14,
        height: 1.5,
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: 1200.ms,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i * 0.2;
              final value = (_controller.value - delay).clamp(0.0, 1.0);
              final opacity =
                  (value < 0.5 ? value * 2 : 2 - value * 2).clamp(0.2, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: DesignColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
