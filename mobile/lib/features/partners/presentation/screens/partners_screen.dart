import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../../domain/partner_models.dart';
import '../providers/partners_provider.dart';

/// "Trade Partners": the businesses this shop trades with. Connect using the
/// other business's company code, accept requests, and chat.
class PartnersScreen extends ConsumerWidget {
  const PartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(partnersProvider);
    final controller = ref.read(partnersProvider.notifier);
    final slug = getIt<StorageService>().getTenantSlug() ?? '';

    return Scaffold(
      // A tab-style destination from More, but also opened on top of the stack
      // from a notification — then it needs a way back.
      appBar: BrandedAppBar(
          title: 'Trade Partners', showBackButton: GoRouter.of(context).canPop()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showConnectSheet(context, ref),
        backgroundColor: DesignColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('Connect'),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
              DesignSpacing.lg, 120),
          children: [
            _MyCodeCard(slug: slug),
            const SizedBox(height: DesignSpacing.lg),
            if (!state.loadedOnce && state.partners.isEmpty)
              const Padding(
                padding: EdgeInsets.all(DesignSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.partners.isEmpty)
              _EmptyState(error: state.error, onRetry: controller.refresh)
            else ...[
              if (state.error != null) ...[
                InlineRetryNotice(
                  message: state.error!,
                  onRetry: controller.refresh,
                ),
                const SizedBox(height: DesignSpacing.md),
              ],
              if (state.incomingRequests.isNotEmpty) ...[
                const _SectionLabel('Requests for you'),
                for (final (i, p) in state.incomingRequests.indexed)
                  SoftEntrance(
                    delay: Duration(milliseconds: 60 * i.clamp(0, 6)),
                    child: _RequestCard(partner: p, controller: controller),
                  ),
                const SizedBox(height: DesignSpacing.lg),
              ],
              if (state.connected.isNotEmpty) ...[
                const _SectionLabel('Your partners'),
                for (final (i, p) in state.connected.indexed)
                  SoftEntrance(
                    delay: Duration(milliseconds: 60 * i.clamp(0, 6)),
                    child: _PartnerTile(partner: p),
                  ),
                const SizedBox(height: DesignSpacing.lg),
              ],
              if (state.outgoingRequests.isNotEmpty) ...[
                const _SectionLabel('Waiting for a reply'),
                for (final p in state.outgoingRequests)
                  _OutgoingTile(partner: p, controller: controller),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showConnectSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.themed(DesignColors.darkSurface),
      builder: (sheetContext) => _ConnectSheet(
        onSubmit: (code, message) => ref
            .read(partnersProvider.notifier)
            .connect(code, message: message),
      ),
    );
  }
}

class _MyCodeCard extends StatelessWidget {
  const _MyCodeCard({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE6D2), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        border: Border.all(color: DesignColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: const Icon(Icons.handshake_rounded,
                color: DesignColors.accentDark),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your company code',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: DesignColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  slug.isEmpty ? '—' : slug,
                  style: DesignType.numeric(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: DesignColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Share it so a business you trade with can connect.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: DesignColors.textSecondary)),
              ],
            ),
          ),
          if (slug.isNotEmpty)
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_rounded, color: DesignColors.accentDark),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: slug));
                showGlassSnackBar(
                  context,
                  'Company code copied',
                  icon: Icons.check_circle_rounded,
                  color: DesignColors.success,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.themed(DesignColors.darkTextTertiary),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.error, this.onRetry});

  final String? error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xxl),
      child: Column(
        children: [
          Icon(error != null ? Icons.cloud_off_rounded : Icons.groups_2_rounded,
              size: 56, color: context.themed(DesignColors.darkTextTertiary)),
          const SizedBox(height: DesignSpacing.lg),
          Text(
            error != null
                ? "Couldn't load your partners"
                : 'Connect with the businesses you trade with',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: context.themed(DesignColors.darkTextPrimary),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: DesignSpacing.sm),
          Text(
            error ??
                'Add a supplier, wholesaler or another shop using their company code. '
                    'Once they accept, you can message each other right here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.themed(DesignColors.darkTextSecondary),
              height: 1.35,
            ),
          ),
          if (error != null && onRetry != null) ...[
            const SizedBox(height: DesignSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.partner});

  final TradePartner partner;

  @override
  Widget build(BuildContext context) {
    final logo = partner.logo;
    return Container(
      width: 46,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
      ),
      alignment: Alignment.center,
      child: logo != null && logo.startsWith('http')
          ? Image.network(
              logo,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letter(),
            )
          : _letter(),
    );
  }

  Widget _letter() => Text(
        partner.initial,
        style: const TextStyle(
          color: DesignColors.accentDark,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      );
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
        child: Material(
          color: context.themed(DesignColors.darkSurface),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            child: Container(
              padding: const EdgeInsets.all(DesignSpacing.md + 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                border:
                    Border.all(color: context.themed(DesignColors.darkBorder)),
              ),
              child: child,
            ),
          ),
        ),
      );
}

class _PartnerTile extends StatelessWidget {
  const _PartnerTile({required this.partner});

  final TradePartner partner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = partner.lastMessageBody == null
        ? 'Say hello 👋'
        : '${partner.lastMessageFromMe ? 'You: ' : ''}${partner.lastMessageBody}';
    return _CardShell(
      onTap: () => context.push('/partners/${partner.id}'),
      child: Row(
        children: [
          _Avatar(partner: partner),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partner.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: context.themed(DesignColors.darkTextPrimary),
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 2),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.themed(DesignColors.darkTextSecondary),
                      fontWeight: partner.unreadCount > 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                    )),
              ],
            ),
          ),
          if (partner.unreadCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: DesignColors.accent,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
              ),
              child: Text('${partner.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            )
          else
            Icon(Icons.chevron_right_rounded,
                color: context.themed(DesignColors.darkTextTertiary)),
        ],
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.partner, required this.controller});

  final TradePartner partner;
  final PartnersController controller;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String doneText) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        showGlassSnackBar(context, doneText,
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
    } on PartnerActionException catch (e) {
      if (mounted) {
        showGlassSnackBar(context, e.message,
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.partner;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(partner: p),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: context.themed(DesignColors.darkTextPrimary),
                          fontWeight: FontWeight.w800,
                        )),
                    Text('wants to connect with you',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.themed(DesignColors.darkTextSecondary),
                        )),
                  ],
                ),
              ),
            ],
          ),
          if (p.message != null && p.message!.trim().isNotEmpty) ...[
            const SizedBox(height: DesignSpacing.sm),
            Text('“${p.message!.trim()}”',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: context.themed(DesignColors.darkTextSecondary),
                )),
          ],
          const SizedBox(height: DesignSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.controller.accept(p.id),
                          'You are now connected with ${p.name}'),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.controller.decline(p.id), 'Request declined'),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutgoingTile extends StatelessWidget {
  const _OutgoingTile({required this.partner, required this.controller});

  final TradePartner partner;
  final PartnersController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      child: Row(
        children: [
          _Avatar(partner: partner),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partner.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: context.themed(DesignColors.darkTextPrimary),
                      fontWeight: FontWeight.w800,
                    )),
                Text('Request sent — waiting for them to accept',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.themed(DesignColors.darkTextSecondary),
                    )),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await controller.remove(partner.id);
              } on PartnerActionException catch (e) {
                if (context.mounted) {
                  showGlassSnackBar(context, e.message,
                      icon: Icons.error_outline_rounded,
                      color: DesignColors.error);
                }
              }
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.onSubmit});

  final Future<void> Function(String code, String? message) onSubmit;

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final _code = TextEditingController();
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;
  int _shakes = 0;

  @override
  void dispose() {
    _code.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = "Enter the other business's company code";
        _shakes++;
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code, _note.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      showGlassSnackBar(
        context,
        'Request sent. You will be notified when they accept.',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
    } on PartnerActionException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _shakes++;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(DesignSpacing.xl, 0, DesignSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + DesignSpacing.xl),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect with a business',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: context.themed(DesignColors.darkTextPrimary),
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(height: DesignSpacing.xs),
            Text(
              'Ask them for their company code — they can find it on their Trade Partners screen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.themed(DesignColors.darkTextSecondary),
                height: 1.3,
              ),
            ),
            const SizedBox(height: DesignSpacing.lg),
            Shake(
              trigger: _shakes,
              child: TextField(
                controller: _code,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Company code',
                  hintText: 'e.g. levisa-ventures',
                  prefixIcon: const Icon(Icons.business_rounded),
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _note,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Short note (optional)',
                hintText: 'Hi, we buy flour from you…',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sending ? null : _submit,
                child: Text(_sending ? 'Sending…' : 'Send request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
