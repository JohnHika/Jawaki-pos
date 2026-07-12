import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gpt_markdown_lite/gpt_markdown_lite.dart';
import '../../../../core/services/export_document_service.dart';
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
      final result = await _aiService.sendMessage(content: message);
      await _maybeShareGeneratedFile(result);
    } on AiSubscriptionRequiredException {
      if (mounted) {
        context.push('/ai/trial', extra: _aiService.branchId);
      }
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  /// The AI can generate a downloadable report (PDF/DOCX/CSV) — it's carried
  /// inline as base64 on the response rather than persisted anywhere server-
  /// side, so this is the one chance to hand it to the user: save it to disk
  /// and open the OS share sheet immediately, mirroring how every other
  /// export in the app (dashboard reports, receipts) already works.
  Future<void> _maybeShareGeneratedFile(AiSendResult result) async {
    final file = result.file;
    if (file == null) return;
    try {
      final bytes = base64Decode(file.base64);
      await ExportDocumentService.shareGeneratedFile(bytes, file.filename);
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Could not open the generated report.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  /// Resumes a paused agent turn (AskUserQuestion answered, or a mutating
  /// tool call approved/declined) — mirrors [_sendMessage] but doesn't
  /// touch the text input, since the pending-turn UI itself is the input.
  Future<void> _resumePendingTurn({
    Map<String, String>? questionAnswers,
    bool? toolConfirmed,
  }) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    _scrollToBottom();

    try {
      final result = await _aiService.resumePendingTurn(
        questionAnswers: questionAnswers,
        toolConfirmed: toolConfirmed,
      );
      await _maybeShareGeneratedFile(result);
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
  Future<void> _editMessage(int index, String content) async {
    if (_isLoading) return;
    await _aiService.truncateFrom(index);
    _controller.text = content;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    if (mounted) setState(() {});
  }

  /// Re-runs the last AI response with a fresh answer to the same question.
  Future<void> _regenerate() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    _scrollToBottom();

    try {
      await _aiService.regenerateLast();
    } on AiSubscriptionRequiredException {
      if (mounted) {
        context.push('/ai/trial', extra: _aiService.branchId);
      }
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  /// Rewinds to an earlier message: drops it and everything after it from
  /// the shared thread. If it was a user message, repopulates the input
  /// with its content (mirrors edit & resubmit); AI messages just vanish
  /// along with what followed, ready for a fresh question.
  Future<void> _rewindTo(int index, String role, String content) async {
    if (_isLoading) return;
    await _aiService.rewindTo(index);
    if (role == 'user') {
      _controller.text = content;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
    if (mounted) setState(() {});
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
    final pending = _aiService.pendingTurn;
    // Extra trailing list items: the typing indicator while loading, or the
    // interactive pending-turn card (question / confirm-mutate) once the
    // agent has paused and is waiting on the user.
    final trailingCount = _isLoading
        ? 1
        : pending != null
            ? 1
            : 0;

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
          if (_aiService.todos.isNotEmpty) _buildTodoChecklist(),
          // Chat messages
          Expanded(
            child: messages.isEmpty && pending == null
                ? _buildWelcomeScreen()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: messages.length + trailingCount,
                    itemBuilder: (context, index) {
                      if (index == messages.length) {
                        if (_isLoading) return _buildTypingIndicator();
                        return _PendingTurnCard(
                          pending: pending!,
                          onAnswerQuestions: (answers) =>
                              _resumePendingTurn(questionAnswers: answers),
                          onConfirmMutation: (confirmed) =>
                              _resumePendingTurn(toolConfirmed: confirmed),
                        ).animate().fadeIn(duration: 300.ms).slideY(
                              begin: 0.1,
                              end: 0,
                              duration: 300.ms,
                            );
                      }
                      final msg = messages[index];
                      final isUser = msg['role'] == 'user';
                      final content = msg['content']!;
                      final isLastAssistant =
                          !isUser && index == messages.length - 1 && pending == null;
                      return _ChatBubble(
                        message: content,
                        isUser: isUser,
                        onCopy: isUser ? null : () => _copyMessage(content),
                        onEdit: isUser ? () => _editMessage(index, content) : null,
                        onRegenerate: isLastAssistant ? _regenerate : null,
                        onRewind: () => _rewindTo(index, msg['role']!, content),
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

  /// A compact, persistent checklist for the AI's current TodoWrite list —
  /// shown above the conversation whenever the AI is tracking a multi-step
  /// task, so progress stays visible without scrolling back through chat.
  Widget _buildTodoChecklist() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final todos = _aiService.todos;
    final completedCount = todos.where((t) => t.status == 'completed').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tasks · $completedCount/${todos.length}',
            style: TextStyle(color: secondaryColor, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final todo in todos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    todo.status == 'completed'
                        ? Icons.check_circle_rounded
                        : todo.status == 'in_progress'
                            ? Icons.autorenew_rounded
                            : Icons.circle_outlined,
                    size: 15,
                    color: todo.status == 'completed'
                        ? DesignColors.success
                        : todo.status == 'in_progress'
                            ? DesignColors.accent
                            : secondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      todo.status == 'in_progress' ? todo.activeForm : todo.content,
                      style: TextStyle(
                        color: todo.status == 'completed' ? secondaryColor : textColor,
                        fontSize: 13,
                        decoration: todo.status == 'completed' ? TextDecoration.lineThrough : null,
                        fontWeight: todo.status == 'in_progress' ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

/// Renders a paused agent turn: an AskUserQuestion (multiple-choice
/// question(s), each with an auto-added "Other" free-text option) or a
/// confirm-before-mutate card for a mutating tool call (e.g. raising a
/// stock reorder). Answering/confirming resolves the turn via the
/// callbacks, which resume the same backend agent loop.
class _PendingTurnCard extends StatefulWidget {
  final AiPendingTurn pending;
  final ValueChanged<Map<String, String>> onAnswerQuestions;
  final ValueChanged<bool> onConfirmMutation;

  const _PendingTurnCard({
    required this.pending,
    required this.onAnswerQuestions,
    required this.onConfirmMutation,
  });

  @override
  State<_PendingTurnCard> createState() => _PendingTurnCardState();
}

class _PendingTurnCardState extends State<_PendingTurnCard> {
  // question -> selected label(s) (multiSelect joins with comma when submitted)
  final Map<String, Set<String>> _selections = {};
  final Map<String, TextEditingController> _otherControllers = {};
  bool _submitted = false;

  @override
  void dispose() {
    for (final c in _otherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(AiPendingQuestion q, String label) {
    if (_submitted) return;
    setState(() {
      final set = _selections.putIfAbsent(q.question, () => {});
      if (q.multiSelect) {
        if (set.contains(label)) {
          set.remove(label);
        } else {
          set.add(label);
        }
      } else {
        set
          ..clear()
          ..add(label);
      }
    });
  }

  bool _canSubmit() {
    for (final q in widget.pending.questions) {
      final selected = _selections[q.question] ?? const {};
      if (selected.isEmpty) return false;
      if (selected.contains('Other')) {
        final text = _otherControllers[q.question]?.text.trim() ?? '';
        if (text.isEmpty) return false;
      }
    }
    return true;
  }

  void _submitQuestions() {
    if (!_canSubmit()) return;
    final answers = <String, String>{};
    for (final q in widget.pending.questions) {
      final selected = _selections[q.question] ?? const {};
      final resolved = selected.map((label) {
        if (label == 'Other') {
          return _otherControllers[q.question]?.text.trim() ?? '';
        }
        return label;
      }).where((s) => s.isNotEmpty);
      answers[q.question] = resolved.join(', ');
    }
    setState(() => _submitted = true);
    widget.onAnswerQuestions(answers);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pending.type == 'confirmation') {
      return _buildConfirmation(context);
    }
    if (widget.pending.type == 'plan') {
      return _buildPlan(context);
    }
    return _buildQuestions(context);
  }

  Widget _buildQuestions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final q in widget.pending.questions) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: DesignColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      q.header,
                      style: const TextStyle(
                        color: DesignColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                q.question,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              ...q.options.map((opt) => _buildOption(q, opt.label, opt.description, textColor, secondaryColor, border)),
              _buildOption(q, 'Other', 'Type your own answer', textColor, secondaryColor, border),
              if ((_selections[q.question] ?? const {}).contains('Other'))
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
                  child: TextField(
                    controller: _otherControllers.putIfAbsent(
                      q.question,
                      () => TextEditingController(),
                    ),
                    enabled: !_submitted,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Your answer...',
                      hintStyle: TextStyle(color: secondaryColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: DesignColors.accent),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: (_submitted || !_canSubmit()) ? null : _submitQuestions,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: (_submitted || !_canSubmit())
                        ? border
                        : DesignColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _submitted ? 'Sent' : 'Submit',
                    style: TextStyle(
                      color: (_submitted || !_canSubmit()) ? secondaryColor : Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    AiPendingQuestion q,
    String label,
    String description,
    Color textColor,
    Color secondaryColor,
    Color border,
  ) {
    final selected = (_selections[q.question] ?? const {}).contains(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _toggle(q, label),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? DesignColors.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? DesignColors.accent : border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                q.multiSelect
                    ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                    : (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                size: 18,
                color: selected ? DesignColors.accent : secondaryColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: TextStyle(color: secondaryColor, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmation(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: DesignColors.accent),
                SizedBox(width: 6),
                Text(
                  'Confirm action',
                  style: TextStyle(
                    color: DesignColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.pending.summary ?? 'Run this action?',
              style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_submitted) ...[
                  GestureDetector(
                    onTap: () {
                      setState(() => _submitted = true);
                      widget.onConfirmMutation(false);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: secondaryColor, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() => _submitted = true);
                      widget.onConfirmMutation(true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: DesignColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Approve',
                        style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Sent',
                    style: TextStyle(color: secondaryColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlan(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.checklist_rounded, size: 18, color: DesignColors.accent),
                SizedBox(width: 6),
                Text(
                  'Proposed plan',
                  style: TextStyle(
                    color: DesignColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GptMarkdown(
              widget.pending.plan ?? '',
              style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_submitted) ...[
                  GestureDetector(
                    onTap: () {
                      setState(() => _submitted = true);
                      widget.onConfirmMutation(false);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        'Reject',
                        style: TextStyle(color: secondaryColor, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() => _submitted = true);
                      widget.onConfirmMutation(true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: DesignColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Approve plan',
                        style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Sent',
                    style: TextStyle(color: secondaryColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
              ],
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
  final VoidCallback? onRegenerate;
  final VoidCallback? onRewind;

  const _ChatBubble({
    required this.message,
    required this.isUser,
    this.onCopy,
    this.onEdit,
    this.onRegenerate,
    this.onRewind,
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
    if (onRegenerate != null) {
      children.add(_actionButton(Icons.refresh_rounded, 'Regenerate', onRegenerate!, color));
    }
    if (onRewind != null) {
      children.add(_actionButton(Icons.history_rounded, 'Rewind here', onRewind!, color));
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
