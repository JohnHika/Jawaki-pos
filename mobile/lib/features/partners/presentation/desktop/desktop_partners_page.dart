import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../domain/partner_models.dart';
import '../providers/partners_provider.dart';
import '../screens/partner_chat_screen.dart';
import '../screens/partners_screen.dart' show showPartnerConnectSheet;
import 'desktop_partners_view.dart';

/// The routed Trade partners page inside the desktop shell. Reads the same
/// provider as the phone page, keeps only "which partner is open" locally, and
/// swaps the middle pane when it changes instead of navigating.
///
/// `/partners/:id` opens it with that partner already selected, so deep links
/// and notification taps still land on the right conversation.
class DesktopPartnersPage extends ConsumerStatefulWidget {
  const DesktopPartnersPage({super.key, this.initialPartnerId});

  final String? initialPartnerId;

  @override
  ConsumerState<DesktopPartnersPage> createState() =>
      _DesktopPartnersPageState();
}

class _DesktopPartnersPageState extends ConsumerState<DesktopPartnersPage> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPartnerId;
  }

  @override
  void didUpdateWidget(DesktopPartnersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPartnerId != widget.initialPartnerId) {
      _selected = widget.initialPartnerId;
    }
  }

  Future<void> _run(
    Future<void> Function() action,
    String doneText,
  ) async {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(partnersProvider);
    final controller = ref.read(partnersProvider.notifier);
    final slug = getIt<StorageService>().getTenantSlug() ?? '';

    return Scaffold(
      body: DesktopPartnersView(
        partners: state.partners,
        loadedOnce: state.loadedOnce,
        error: state.error,
        slug: slug,
        selectedId: _selected,
        onSelect: (id) => setState(() => _selected = id),
        onConnect: () => showPartnerConnectSheet(context, ref),
        onCopyCode: () {
          Clipboard.setData(ClipboardData(text: slug));
          showGlassSnackBar(
            context,
            'Company code copied',
            icon: Icons.check_circle_rounded,
            color: DesignColors.success,
          );
        },
        onRetry: controller.refresh,
        onAccept: (p) => _run(() => controller.accept(p.id),
            'You are now connected with ${p.name}'),
        onDecline: (p) =>
            _run(() => controller.decline(p.id), 'Request declined'),
        onCancelRequest: (p) =>
            _run(() => controller.remove(p.id), 'Request cancelled'),
        onRemove: (p) async {
          await _run(() => controller.remove(p.id), '${p.name} was removed');
          if (mounted && _selected == p.id) setState(() => _selected = null);
        },
        conversationBuilder: (context, TradePartner partner) =>
            PartnerConversationView(
          key: ValueKey(partner.id),
          partnershipId: partner.id,
          embedded: true,
        ),
      ),
    );
  }
}
