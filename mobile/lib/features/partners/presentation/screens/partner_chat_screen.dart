import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../domain/partner_models.dart';
import '../providers/partners_provider.dart';

/// One-to-one chat between this business and a trade partner. New messages
/// arrive by light polling while the screen is open (and as push
/// notifications when it is not).
class PartnerChatScreen extends ConsumerStatefulWidget {
  const PartnerChatScreen({super.key, required this.partnershipId});

  final String partnershipId;

  @override
  ConsumerState<PartnerChatScreen> createState() => _PartnerChatScreenState();
}

class _PartnerChatScreenState extends ConsumerState<PartnerChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<PartnerMessage> _messages = [];
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  ApiClient get _api => getIt<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _fetchNew());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.getPartnerMessages(widget.partnershipId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(rows.map(PartnerMessage.fromJson));
        _loading = false;
        _error = null;
      });
      _scrollToEnd();
      // Opening the chat read them — refresh the list's unread badges.
      ref.read(partnersProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = partnerErrorMessage(e);
      });
    }
  }

  Future<void> _fetchNew() async {
    if (_loading || _sending || _messages.isEmpty && _error != null) return;
    try {
      final after = _messages.isEmpty
          ? null
          : _messages.last.createdAt.toUtc().toIso8601String();
      final rows =
          await _api.getPartnerMessages(widget.partnershipId, after: after);
      if (!mounted || rows.isEmpty) return;
      final known = _messages.map((m) => m.id).toSet();
      final fresh = rows
          .map(PartnerMessage.fromJson)
          .where((m) => !known.contains(m.id))
          .toList();
      if (fresh.isEmpty) return;
      setState(() => _messages.addAll(fresh));
      _scrollToEnd();
    } catch (_) {
      // Transient network error — the next tick retries.
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await _api.sendPartnerMessage(widget.partnershipId, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _messages.add(PartnerMessage.fromJson(sent));
        _sending = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showGlassSnackBar(
        context,
        partnerErrorMessage(e),
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(partnersProvider).byId(widget.partnershipId);
    return Scaffold(
      appBar: BrandedAppBar(
        title: partner?.name ?? 'Trade partner',
        showLogo: false,
      ),
      body: Column(
        children: [
          Expanded(child: _messagesView(context)),
          _composer(context),
        ],
      ),
    );
  }

  Widget _messagesView(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: DesignSpacing.md),
              OutlinedButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignSpacing.xxl),
          child: Text(
            'No messages yet. Say hello — orders, prices and delivery updates can all be sorted here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.themed(DesignColors.darkTextSecondary),
              height: 1.35,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, DesignSpacing.md),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final showDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
        return Column(
          children: [
            if (showDay) _DayChip(date: m.createdAt),
            _Bubble(message: m),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _composer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            DesignSpacing.md, DesignSpacing.sm, DesignSpacing.md, DesignSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message…',
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: DesignSpacing.lg, vertical: DesignSpacing.md),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: DesignSpacing.sm),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              style: IconButton.styleFrom(
                backgroundColor: DesignColors.accent,
                foregroundColor: Colors.white,
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date});

  final DateTime date;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignSpacing.md),
        child: Text(
          _label(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.themed(DesignColors.darkTextTertiary),
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final PartnerMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.fromMe;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: DesignSpacing.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: DesignSpacing.md + 2, vertical: DesignSpacing.sm + 2),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: mine
              ? DesignColors.accent
              : context.themed(DesignColors.darkSurface),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          border: mine
              ? null
              : Border.all(color: context.themed(DesignColors.darkBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine && message.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: DesignColors.accentDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Text(
              message.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: mine
                    ? Colors.white
                    : context.themed(DesignColors.darkTextPrimary),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                time,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.8)
                      : context.themed(DesignColors.darkTextTertiary),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
