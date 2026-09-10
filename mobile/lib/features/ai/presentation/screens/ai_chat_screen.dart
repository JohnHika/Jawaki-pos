import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gpt_markdown_lite/gpt_markdown_lite.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/services/voice_input_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/widgets/motion.dart';
import 'ai_chart_widget.dart';
import 'ai_chat_service.dart';
import 'ai_add_to_chat_sheet.dart';
import 'ai_skill_picker.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiChatService _aiService = AiChatService();
  final VoiceInputService _voiceService = VoiceInputService();
  bool _isLoading = false;
  bool _isListening = false;
  // Text already in the field before this listen session started — partial
  // results replace only what was dictated, so voice input can be appended
  // to (or mixed with) whatever the user already typed instead of clobbering it.
  String _preVoiceText = '';

  // Charts aren't persisted into AiChatService.messages (they'd bloat every
  // future turn's request payload the same way file attachments would) —
  // kept here instead, keyed by the assistant message id the chart belongs
  // to, so it renders inline right below that reply for this session only.
  final Map<String, AiChartData> _charts = {};

  // The assistant message id that should play its typewriter reveal — only
  // the reply that JUST arrived this session, never history loaded on open
  // or scrolled back to. Cleared once shown so it never replays (e.g. on a
  // rebuild triggered by something unrelated).
  String? _justArrivedMessageId;

  // Non-null while the input starts with "/" and hasn't been submitted yet —
  // drives the inline skill-suggestion list shown above the input bar.
  List<AiSkillCommand>? _skillSuggestions;

  // True while the shared history fetch kicked off in [initState] is still in
  // flight. The stagger entrance is keyed on the moment this flips false:
  // only the initial batch of messages (loaded at open, or typed before the
  // fetch resolves) plays the once-per-entry reveal. Messages appended AFTER
  // the initial mount — live replies, later edits — render with no entrance
  // at all, so an ongoing conversation never re-animates per frame.
  bool _initialMessagesMounted = false;

  // How many messages were on screen at the moment the current stagger
  // batch mounted. Only indices below this played (or would have played)
  // the entrance; anything at or beyond it is a live message and skips it.
  int _initialCount = 0;

  /// True when [index] belongs to the current initial batch — i.e. the
  /// message was already on screen (or the batch was declared) before new
  /// messages started being appended. Returns false for anything appended
  /// later, so live conversation never re-animates.
  bool _messageIsInitial(int index) => index < _initialCount;

  @override
  void initState() {
    super.initState();
    // Pull the shop's shared conversation so every staff member on this
    // shop sees and continues the same thread.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _aiService.loadSharedHistory();
      if (mounted) {
        // Snapshot the history batch at the moment the initial mount is
        // declared: everything present now plays the once-per-entry stagger;
        // anything appended AFTER this point (live replies, later edits) has
        // an index at or beyond [_initialCount] and never animates.
        setState(() {
          _initialCount = _aiService.messages.length;
          _initialMessagesMounted = true;
        });
      }
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    if (_isListening) _voiceService.cancel();
    super.dispose();
  }

  /// Push-to-talk voice input — tap to start listening, tap again (or pause
  /// speaking) to stop. Dictated text lands in the same field as typed text,
  /// appended after whatever was there when listening started.
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _voiceService.stop();
      setState(() => _isListening = false);
      return;
    }

    _preVoiceText = _controller.text;
    final started = await _voiceService.startListening(
      onResult: (text, isFinal) {
        if (!mounted) return;
        final separator =
            _preVoiceText.isEmpty || _preVoiceText.endsWith(' ') ? '' : ' ';
        setState(() {
          _controller.text = '$_preVoiceText$separator$text';
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
        if (isFinal) {
          setState(() => _isListening = false);
        }
      },
    );

    if (!mounted) return;
    if (!started) {
      showGlassSnackBar(
        context,
        'Microphone permission is needed for voice input.',
        icon: Icons.mic_off_rounded,
        color: DesignColors.warning,
      );
      return;
    }
    setState(() => _isListening = true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Reduced motion: snap without animating — the scroll is functional
        // positioning, not decorative motion, but the glide is still movement.
        if (reducedMotion(context)) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
          return;
        }
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: DesignAnimation.fast,
          curve: DesignAnimation.smooth,
        );
      }
    });
  }

  /// Parses a leading "/command" (optionally followed by more text) out of
  /// [text] into a matching [AiSkillCommand]'s natural-language prompt, so
  /// submitting "/cashup" behaves exactly like typing the full trigger
  /// phrase by hand. Falls through to plain text unchanged if there's no
  /// exact command match (e.g. it's still mid-suggestion or just a message
  /// that happens to start with "/").
  String _resolveSlashCommand(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/')) return text;
    final firstSpace = trimmed.indexOf(' ');
    final commandWord = (firstSpace == -1
            ? trimmed.substring(1)
            : trimmed.substring(1, firstSpace))
        .toLowerCase();
    final match = aiSkillCommands.where((c) => c.command == commandWord);
    if (match.isEmpty) return text;
    final extra = firstSpace == -1 ? '' : trimmed.substring(firstSpace).trim();
    final prompt = match.first.prompt;
    return extra.isEmpty ? prompt : '$prompt $extra';
  }

  void _onInputChanged(String text) {
    setState(() {
      _skillSuggestions = text.startsWith('/') && !text.contains(' ')
          ? filterAiSkillCommands(text.substring(1))
          : null;
    });
  }

  void _selectSkill(AiSkillCommand cmd) {
    setState(() => _skillSuggestions = null);
    _sendMessage(cmd.prompt);
  }

  Future<void> _sendMessage(String rawText) async {
    if (rawText.trim().isEmpty || _isLoading) return;

    final message = _resolveSlashCommand(rawText).trim();
    _controller.clear();
    setState(() => _skillSuggestions = null);

    setState(() => _isLoading = true);
    _scrollToBottom();

    try {
      final result = await _aiService.sendMessage(content: message);
      _markJustArrived();
      await _maybeShareGeneratedFile(result);
      _maybeStoreChart(result);
    } on AiSubscriptionRequiredException {
      if (mounted) {
        context.push('/ai/trial', extra: _aiService.branchId);
      }
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  /// Marks the assistant message that was just appended as the one that
  /// should play its typewriter reveal (see [_justArrivedMessageId]).
  void _markJustArrived() {
    final messages = _aiService.messages;
    if (messages.isEmpty) return;
    final last = messages.last;
    if (last['role'] != 'assistant') return;
    final id = last['id'];
    if (id == null || id.isEmpty) return;
    setState(() => _justArrivedMessageId = id);
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

  /// The AI can return chart data alongside its reply — stash it against the
  /// assistant message that was just appended so the bubble list can render
  /// it inline (see [_charts]).
  void _maybeStoreChart(AiSendResult result) {
    final chartJson = result.chart;
    if (chartJson == null) return;
    final messages = _aiService.messages;
    if (messages.isEmpty) return;
    final lastId = messages.last['id'];
    if (lastId == null || lastId.isEmpty) return;
    setState(() {
      _charts[lastId] = AiChartData.fromJson(chartJson);
    });
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
      _markJustArrived();
      await _maybeShareGeneratedFile(result);
      _maybeStoreChart(result);
    } on AiSubscriptionRequiredException {
      if (mounted) {
        context.push('/ai/trial', extra: _aiService.branchId);
      }
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  /// Exports the visible conversation as a branded PDF transcript (same
  /// header/footer style as dashboard reports and receipts) and opens the
  /// OS share sheet. Tool-call/tool-result turns never reach [_aiService
  /// .messages] as separate entries (only the user/assistant text turns
  /// do — see AiChatService), so no filtering is needed here beyond that.
  Future<void> _exportConversation() async {
    final messages = _aiService.messages;
    if (messages.isEmpty) return;

    final buffer = StringBuffer();
    for (final msg in messages) {
      final speaker = msg['role'] == 'user' ? 'You' : 'Axon AI';
      buffer.writeln('$speaker:');
      buffer.writeln(msg['content'] ?? '');
      buffer.writeln();
    }

    try {
      final bytes = await ExportDocumentService.buildPdfReport(
        title: 'AI Conversation',
        companyName: _aiService.companyName,
        subtitle: 'Exported ${DateTime.now().toString().split('.').first}',
        bodyText: buffer.toString().trim(),
      );
      await ExportDocumentService.sharePdf(bytes, 'ai_conversation');
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Could not export the conversation.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  Future<void> _newConversation() async {
    await _aiService.startNewSharedConversation();
    if (mounted) {
      setState(() {
        _isLoading = false;
        // A fresh thread: its opening messages form a NEW initial batch, so
        // the stagger snapshot is re-taken here rather than reusing the old
        // thread's count.
        _initialCount = _aiService.messages.length;
        _initialMessagesMounted = true;
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
          IconButton(
            icon: const Icon(Icons.psychology_alt_outlined, size: 20),
            tooltip: 'AI Memory',
            onPressed: () => context.push('/ai/memory'),
          ),
          if (messages.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (value) {
                if (value == 'new') _newConversation();
                if (value == 'export') _exportConversation();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.ios_share_rounded, size: 18),
                      SizedBox(width: DesignSpacing.xs + 6),
                      Text('Export conversation'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'new',
                  child: Row(
                    children: [
                      Icon(Icons.refresh_rounded, size: 18),
                      SizedBox(width: DesignSpacing.xs + 6),
                      Text('New conversation'),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(width: DesignSpacing.xs),
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
                        horizontal: DesignSpacing.lg,
                        vertical: DesignSpacing.md),
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
                        ).animateEntrance(
                          context,
                          effects: () => [
                            const FadeEffect(
                              duration: DesignAnimation.fast,
                              curve: DesignAnimation.smooth,
                            ),
                            const SlideEffect(
                              begin: Offset(0, 0.1),
                              end: Offset.zero,
                              duration: DesignAnimation.fast,
                              curve: DesignAnimation.smooth,
                            ),
                          ],
                        );
                      }
                      final msg = messages[index];
                      final isUser = msg['role'] == 'user';
                      final content = msg['content']!;
                      final isLastAssistant = !isUser &&
                          index == messages.length - 1 &&
                          pending == null;
                      final chart = _charts[msg['id']];
                      final shouldAnimateIn = !isUser &&
                          msg['id'] != null &&
                          msg['id'] == _justArrivedMessageId;
                      if (shouldAnimateIn) {
                        // One-shot: clear right after reading so a later
                        // rebuild (e.g. a chart arriving, a scroll) never
                        // replays the reveal for the same message.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _justArrivedMessageId == msg['id']) {
                            setState(() => _justArrivedMessageId = null);
                          }
                        });
                      }
                      // Staggered entrance ONLY for the initial batch of
                      // messages present on first mount (history loaded at
                      // open). Messages appended afterwards — every live
                      // reply — skip it entirely so the chat never animates
                      // on each frame of a conversation.
                      // No unconditional entrance here: history rows render
                      // as plain widgets (a ListView recycles children, so a
                      // fresh [Animate] state would replay on every scroll
                      // remount — the "animates every frame" bug). Only the
                      // initial batch is wrapped (below), and only the reply
                      // that just arrived gets its one-shot typewriter.
                      final staggerThis =
                          _initialMessagesMounted && _messageIsInitial(index);
                      Widget row = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ChatBubble(
                            message: content,
                            isUser: isUser,
                            onCopy: isUser ? null : () => _copyMessage(content),
                            onEdit: isUser
                                ? () => _editMessage(index, content)
                                : null,
                            onRegenerate: isLastAssistant ? _regenerate : null,
                            onRewind: () =>
                                _rewindTo(index, msg['role']!, content),
                            animateIn: shouldAnimateIn,
                          ),
                          if (chart != null) AiChartCard(chart: chart),
                        ],
                      );
                      if (!staggerThis) return row;
                      return StaggeredItem(
                        itemKey: 'chat-${msg['id'] ?? index}',
                        index: index,
                        child: row,
                      );
                    },
                  ),
          ),
          // Input bar
          if (_skillSuggestions != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.md),
              child: AiSkillSuggestionList(
                commands: _skillSuggestions!,
                onSelect: _selectSkill,
              ),
            ),
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
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final todos = _aiService.todos;
    final completedCount = todos.where((t) => t.status == 'completed').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          DesignSpacing.lg, DesignSpacing.sm, DesignSpacing.lg, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: DesignSpacing.md + 2,
          vertical: DesignSpacing.sm + DesignSpacing.xs),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd + 2),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tasks · $completedCount/${todos.length}',
            style: TextStyle(
                color: secondaryColor,
                fontSize: DesignType.chatMeta,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: DesignSpacing.xs + 2),
          for (final todo in todos)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: DesignSpacing.xs / 2),
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
                  const SizedBox(width: DesignSpacing.sm),
                  Expanded(
                    child: Text(
                      todo.status == 'in_progress'
                          ? todo.activeForm
                          : todo.content,
                      style: TextStyle(
                        color: todo.status == 'completed'
                            ? secondaryColor
                            : textColor,
                        fontSize: DesignType.chatBody,
                        decoration: todo.status == 'completed'
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight: todo.status == 'in_progress'
                            ? FontWeight.w600
                            : FontWeight.normal,
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
        padding: const EdgeInsets.all(DesignSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
              ),
              child: Center(
                child: AxonAiIcon(
                  tenantLogoUrl: ref.watch(tenantIdentityProvider).logoUrl,
                  size: 44,
                ),
              ),
            ).animateEntrance(
              context,
              effects: () => [
                const ScaleEffect(
                  duration: DesignAnimation.slowest,
                  curve: DesignAnimation.bounce,
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.xl),
            Text(
              'Axon AI Assistant',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ).animateEntrance(
              context,
              delay: DesignAnimation.fast,
              effects: () => [
                const FadeEffect(duration: DesignAnimation.fast),
              ],
            ),
            const SizedBox(height: DesignSpacing.sm),
            Text(
              'Your intelligent business companion.\nAsk me anything about your sales, inventory, and customers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: secondaryColor, fontSize: DesignType.chatBody),
            ).animateEntrance(
              context,
              delay: DesignAnimation.normal,
              effects: () => [
                const FadeEffect(duration: DesignAnimation.fast),
              ],
            ),
            const SizedBox(height: DesignSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: DesignSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _TypingIndicator(),
      ),
    );
  }

  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted;
    final hintColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final iconColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final hasText = _controller.text.trim().isNotEmpty;

    return Padding(
      // Keyboard-safe: the Scaffold (resizeToAvoidBottomInset) already shrinks
      // the body to make room for the keyboard, so only the safe-area inset
      // is added here — adding viewInsets.bottom too would double-count it
      // and push the bar needlessly high above the keyboard. The input row
      // itself uses `isDense`-free intrinsic sizing and stays pinned above
      // the keyboard on both resizing and non-resizing scaffolds.
      padding: EdgeInsets.fromLTRB(
        DesignSpacing.md,
        DesignSpacing.sm,
        DesignSpacing.md,
        MediaQuery.of(context).padding.bottom + DesignSpacing.sm,
      ),
      // A floating rounded pill with no top shadow/divider line — it reads
      // as a compact input control sitting over the content, not a full
      // width toolbar boxed off from the rest of the screen.
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: DesignSpacing.xs + DesignSpacing.xs,
            vertical: DesignSpacing.xs + DesignSpacing.xs),
        decoration: BoxDecoration(
          color: fill,
          borderRadius:
              BorderRadius.circular(DesignSpacing.radiusXxl + DesignSpacing.xs),
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
                onChanged: (text) {
                  setState(() {});
                  _onInputChanged(text);
                },
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
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: DesignSpacing.sm + 2),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
              ),
            ),
            if (!hasText && !_isLoading)
              IconButton(
                icon: Icon(
                  _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _isListening ? DesignColors.accent : iconColor,
                ),
                onPressed: _toggleListening,
                tooltip: _isListening ? 'Stop listening' : 'Voice input',
              ).animateEntrance(
                context,
                effects: () => [
                  const ScaleEffect(
                    begin: Offset(1, 1),
                    end: Offset(1.15, 1.15),
                    duration: DesignAnimation.slower,
                  ),
                ],
              ),
            const SizedBox(width: DesignSpacing.xs),
            Padding(
              padding: const EdgeInsets.all(DesignSpacing.xs),
              child: _isLoading
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: Padding(
                        padding: EdgeInsets.all(DesignSpacing.xs + 2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  // Material+InkWell so the send press shows an ink ripple;
                  // 44px minimum tap target per the design system's a11y rule
                  // (the visual circle stays 32px, the hit area does not).
                  // Disabled when the field is empty — grey fill, inert tap.
                  : Semantics(
                      button: true,
                      enabled: hasText,
                      label: 'Send message',
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: hasText
                              ? () => _sendMessage(_controller.text)
                              : null,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: AnimatedContainer(
                                duration: DesignAnimation.pressScale,
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
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xs + 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignSpacing.md + 2),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final q in widget.pending.questions) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.sm,
                        vertical: DesignSpacing.xs / 2),
                    decoration: BoxDecoration(
                      color: DesignColors.accent.withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusSm),
                    ),
                    child: Text(
                      q.header,
                      style: const TextStyle(
                        color: DesignColors.accent,
                        fontSize: DesignType.chatMeta,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignSpacing.sm),
              Text(
                q.question,
                style: TextStyle(
                  color: textColor,
                  fontSize: DesignType.chatBody,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: DesignSpacing.xs + 6),
              ...q.options.map((opt) => _buildOption(q, opt.label,
                  opt.description, textColor, secondaryColor, border)),
              _buildOption(q, 'Other', 'Type your own answer', textColor,
                  secondaryColor, border),
              if ((_selections[q.question] ?? const {}).contains('Other'))
                Padding(
                  padding: const EdgeInsets.only(
                      top: DesignSpacing.sm,
                      left: DesignSpacing.xs / 2,
                      right: DesignSpacing.xs / 2),
                  child: TextField(
                    controller: _otherControllers.putIfAbsent(
                      q.question,
                      () => TextEditingController(),
                    ),
                    enabled: !_submitted,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                        color: textColor, fontSize: DesignType.chatBody),
                    decoration: InputDecoration(
                      hintText: 'Your answer...',
                      hintStyle: TextStyle(color: secondaryColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: DesignSpacing.xs + 6,
                          vertical: DesignSpacing.xs + 6),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusSm + 2),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusSm + 2),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusSm + 2),
                        borderSide:
                            const BorderSide(color: DesignColors.accent),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: DesignSpacing.xs),
            ],
            const SizedBox(height: DesignSpacing.xs + 2),
            Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: (_submitted || !_canSubmit())
                    ? border
                    : DesignColors.accent,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                child: InkWell(
                  onTap:
                      (_submitted || !_canSubmit()) ? null : _submitQuestions,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  child: Container(
                    constraints:
                        const BoxConstraints(minHeight: DesignSpacing.huge),
                    padding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.xl + 2,
                        vertical: DesignSpacing.sm + DesignSpacing.xs),
                    alignment: Alignment.center,
                    child: Text(
                      _submitted ? 'Sent' : 'Submit',
                      style: TextStyle(
                        color: (_submitted || !_canSubmit())
                            ? secondaryColor
                            : Colors.black,
                        fontSize: DesignType.chatBody,
                        fontWeight: FontWeight.w600,
                      ),
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
      padding: const EdgeInsets.only(bottom: DesignSpacing.xs + 2),
      child: InkWell(
        onTap: () => _toggle(q, label),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: DesignSpacing.md, vertical: DesignSpacing.xs + 6),
          decoration: BoxDecoration(
            color: selected
                ? DesignColors.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            border: Border.all(
              color: selected ? DesignColors.accent : border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                q.multiSelect
                    ? (selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded)
                    : (selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded),
                size: 18,
                color: selected ? DesignColors.accent : secondaryColor,
              ),
              const SizedBox(width: DesignSpacing.xs + 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: DesignType.chatBody,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: TextStyle(
                            color: secondaryColor,
                            fontSize: DesignType.chatSecondary),
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
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xs + 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignSpacing.md + 2),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: DesignColors.accent),
                SizedBox(width: DesignSpacing.xs + 2),
                Text(
                  'Confirm action',
                  style: TextStyle(
                    color: DesignColors.accent,
                    fontSize: DesignType.chatSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.sm),
            Text(
              widget.pending.summary ?? 'Run this action?',
              style: TextStyle(
                  color: textColor, fontSize: DesignType.chatBody, height: 1.4),
            ),
            const SizedBox(height: DesignSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_submitted) ...[
                  // Material+InkWell: real ripple + >=44px target (a plain
                  // text tap target is far below the 44px minimum).
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    child: InkWell(
                      onTap: () {
                        setState(() => _submitted = true);
                        widget.onConfirmMutation(false);
                      },
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: DesignSpacing.huge,
                          minHeight: DesignSpacing.huge,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.md + 2,
                            vertical: DesignSpacing.sm + DesignSpacing.xs),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: DesignType.chatBody,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignSpacing.xs + 2),
                  Material(
                    color: DesignColors.accent,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    child: InkWell(
                      onTap: () {
                        setState(() => _submitted = true);
                        widget.onConfirmMutation(true);
                      },
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: DesignSpacing.huge,
                          minHeight: DesignSpacing.huge,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.xl + 2,
                            vertical: DesignSpacing.sm + DesignSpacing.xs),
                        child: const Text(
                          'Approve',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: DesignType.chatBody,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Sent',
                    style: TextStyle(
                        color: secondaryColor,
                        fontSize: DesignType.chatBody,
                        fontWeight: FontWeight.w600),
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
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xs + 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignSpacing.md + 2),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.checklist_rounded,
                    size: 18, color: DesignColors.accent),
                SizedBox(width: DesignSpacing.xs + 2),
                Text(
                  'Proposed plan',
                  style: TextStyle(
                    color: DesignColors.accent,
                    fontSize: DesignType.chatSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.sm),
            GptMarkdown(
              widget.pending.plan ?? '',
              style: TextStyle(
                  color: textColor, fontSize: DesignType.chatBody, height: 1.4),
            ),
            const SizedBox(height: DesignSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_submitted) ...[
                  // Material+InkWell: real ripple + >=44px target (a plain
                  // text tap target is far below the 44px minimum).
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    child: InkWell(
                      onTap: () {
                        setState(() => _submitted = true);
                        widget.onConfirmMutation(false);
                      },
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: DesignSpacing.huge,
                          minHeight: DesignSpacing.huge,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.md + 2,
                            vertical: DesignSpacing.sm + DesignSpacing.xs),
                        child: Text(
                          'Reject',
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: DesignType.chatBody,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignSpacing.xs + 2),
                  Material(
                    color: DesignColors.accent,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    child: InkWell(
                      onTap: () {
                        setState(() => _submitted = true);
                        widget.onConfirmMutation(true);
                      },
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: DesignSpacing.huge,
                          minHeight: DesignSpacing.huge,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.xl + 2,
                            vertical: DesignSpacing.sm + DesignSpacing.xs),
                        child: const Text(
                          'Approve plan',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: DesignType.chatBody,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Sent',
                    style: TextStyle(
                        color: secondaryColor,
                        fontSize: DesignType.chatBody,
                        fontWeight: FontWeight.w600),
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

  /// True only for an assistant reply that just arrived this session (not
  /// history loaded/scrolled back to) — the backend answers in one shot
  /// (see the "client-side typewriter, not real token streaming" decision:
  /// real streaming would mean re-asking the model a second time for every
  /// reply, doubling token cost, since the tool-calling loop can't know a
  /// turn is "final" until it already has the full text). This just reveals
  /// the already-fetched text progressively so it reads like it's arriving
  /// live, without any extra cost or latency.
  final bool animateIn;

  const _ChatBubble({
    required this.message,
    required this.isUser,
    this.onCopy,
    this.onEdit,
    this.onRegenerate,
    this.onRewind,
    this.animateIn = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final actionColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xs + 2),
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
            const SizedBox(width: DesignSpacing.sm),
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
                        horizontal: DesignSpacing.lg,
                        vertical: DesignSpacing.md),
                    decoration: BoxDecoration(
                      color: isUser
                          ? DesignColors.accent.withValues(alpha: 0.1)
                          : (isDark
                              ? DesignColors.darkSurfaceElevated
                              : DesignColors.surfaceMuted),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(DesignSpacing.radiusLg),
                        topRight: const Radius.circular(DesignSpacing.radiusLg),
                        bottomLeft: Radius.circular(
                            isUser ? DesignSpacing.radiusLg : DesignSpacing.xs),
                        bottomRight: Radius.circular(
                            isUser ? DesignSpacing.xs : DesignSpacing.radiusLg),
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
          if (isUser) const SizedBox(width: DesignSpacing.sm),
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
      children.add(_actionButton(
          Icons.refresh_rounded, 'Regenerate', onRegenerate!, color));
    }
    if (onRewind != null) {
      children.add(_actionButton(
          Icons.history_rounded, 'Rewind here', onRewind!, color));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(
          top: DesignSpacing.xs / 2,
          left: DesignSpacing.xs,
          right: DesignSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _actionButton(
      IconData icon, String tooltip, VoidCallback onTap, Color color) {
    // >=44px tap target (design-system a11y rule): the 15px glyph sits inside
    // a 44x44 hit box via a SizedBox wrapper; the ink ripple is clipped to
    // the same rounded shape.
    return SizedBox(
      width: DesignSpacing.huge,
      height: DesignSpacing.huge,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusSm + 2),
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
      if (animateIn) {
        return _TypewriterMarkdown(
          text: message,
          style: TextStyle(
              color: textColor, fontSize: DesignType.chatBody, height: 1.5),
        );
      }
      return GptMarkdown(
        message,
        style: TextStyle(
          color: textColor,
          fontSize: DesignType.chatBody,
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
        fontSize: DesignType.chatBody,
        height: 1.5,
      ),
    );
  }
}

/// Reveals an already-fetched reply word-by-word so it reads like it's
/// arriving live, without any real streaming round-trip. Reveals whole
/// words (not characters) so markdown syntax (bold/tables/links) is never
/// caught mid-token — a construct only ever appears once it's complete.
class _TypewriterMarkdown extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _TypewriterMarkdown({required this.text, required this.style});

  @override
  State<_TypewriterMarkdown> createState() => _TypewriterMarkdownState();
}

class _TypewriterMarkdownState extends State<_TypewriterMarkdown> {
  late final List<String> _words;
  int _visibleWords = 0;
  Timer? _timer;

  bool _revealedAll = false;

  @override
  void initState() {
    super.initState();
    // Split keeping the trailing whitespace attached to each word so
    // re-joining a prefix doesn't collapse spacing/newlines.
    _words = widget.text.split(RegExp(r'(?<=\s)'));
    if (_words.isEmpty) {
      _visibleWords = 0;
      _revealedAll = true;
    }
    // NOTE: [reducedMotion] is read in [didChangeDependencies], never here —
    // it is an inherited-widget lookup and initState runs before those exist.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_revealedAll) return;
    _startRevealing();
  }

  void _startRevealing() {
    // Reduced motion: skip the word-by-word reveal entirely and show the
    // full reply at once — motion is replaced by an instant final state.
    if (reducedMotion(context)) {
      setState(() => _visibleWords = _words.length);
      _revealedAll = true;
      return;
    }
    // A steady, brisk cadence rather than trying to match any real token
    // rate — this is a UI affordance, not a simulation of the model.
    _timer = Timer.periodic(const Duration(milliseconds: 18), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _visibleWords++);
      if (_visibleWords >= _words.length) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleText = _words.take(_visibleWords).join();
    return GptMarkdown(visibleText, style: widget.style);
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
      duration: DesignAnimation.slower + DesignAnimation.slower,
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: an infinite pulsing loop is exactly the kind of motion
    // the OS "remove animations" setting exists to stop. The loop is halted
    // and the dots render fully opaque — "AI is thinking" is still visible
    // (the bubble is), just without the animation.
    if (reducedMotion(context)) {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.reset();
      }
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DesignSpacing.lg, vertical: DesignSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(DesignSpacing.xs),
          topRight: Radius.circular(DesignSpacing.radiusLg),
          bottomLeft: Radius.circular(DesignSpacing.radiusLg),
          bottomRight: Radius.circular(DesignSpacing.radiusLg),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: DesignSpacing.xs / 2),
                child: Opacity(
                  opacity: reducedMotion(context) ? 1.0 : opacity,
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
