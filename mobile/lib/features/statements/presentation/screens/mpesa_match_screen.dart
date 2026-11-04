import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../../sales/domain/recorded_payment.dart';
import '../../domain/statement_match.dart';

/// Checks the payments the shop recorded today against the owner's own M-Pesa
/// or bank statement. Counterbase never reads texts: the owner pastes the
/// statement, and each recorded code is matched or flagged.
///
/// A shop connected to the cloud keeps the older explanation, because there a
/// pasted statement cannot confirm a payment.
class MpesaMatchScreen extends StatelessWidget {
  const MpesaMatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (getIt<AuthService>().isLocalWorkspace) {
      return const _RecordedMatchView();
    }
    return const _CloudNotice();
  }
}

class _RecordedMatchView extends StatefulWidget {
  const _RecordedMatchView();

  @override
  State<_RecordedMatchView> createState() => _RecordedMatchViewState();
}

class _RecordedMatchViewState extends State<_RecordedMatchView> {
  final _statement = TextEditingController();
  late Future<List<RecordedItem>> _items;
  final Map<String, RecordedPaymentDetails?> _details = {};
  final Map<String, DateTime> _times = {};
  Map<String, dynamic> _checks = {};
  static final _timeFmt = DateFormat('h:mm a');

  @override
  void initState() {
    super.initState();
    _checks = _loadChecks();
    _items = _load();
  }

  @override
  void dispose() {
    _statement.dispose();
    super.dispose();
  }

  Map<String, dynamic> _loadChecks() {
    final raw = getIt<StorageService>().getRecordedPaymentChecksJson();
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveChecks() => getIt<StorageService>()
      .saveRecordedPaymentChecksJson(jsonEncode(_checks));

  Future<List<RecordedItem>> _load() async {
    final branchId = getIt<AuthService>().branchId;
    if (branchId == null || branchId.isEmpty) return const [];
    final sales = await getIt<AppDatabase>()
        .getRecordedSalesForDay(branchId, DateTime.now());
    final items = <RecordedItem>[];
    for (final sale in sales) {
      final details = RecordedPaymentDetails.tryParse(sale.paymentReference);
      if (details == null) continue;
      _details[sale.id] = details;
      _times[sale.id] = sale.createdAt;
      items.add(RecordedItem(
        saleId: sale.id,
        code: details.code,
        amount: sale.total,
        isBank: details.method == RecordedPaymentMethod.bank,
      ));
    }
    return items;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) return;
    setState(() => _statement.text = text);
  }

  Future<void> _markChecked(RecordedItem item) async {
    final controller = TextEditingController();
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final palette = SignInPalette.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Mark ${item.code} as checked',
                      style: DesignType.display.copyWith(
                          color: palette.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Say how you checked it, for example "saw the message on the cashier\'s phone". The note stays with today\'s record.',
                    style: TextStyle(color: palette.soft, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(hintText: 'How did you check it?'),
                  ),
                  const SizedBox(height: 14),
                  SignInButton(
                    label: 'Save note',
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.length < 3) return;
                      Navigator.pop(ctx, text);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();
    if (note == null || !mounted) return;
    final by = getIt<AuthService>().currentUser?['name']?.toString() ?? '';
    setState(() {
      _checks[item.saleId] = {
        'note': note,
        'by': by,
        'at': DateTime.now().toIso8601String(),
      };
    });
    await _saveChecks();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text('Match M-Pesa',
            style: DesignType.display.copyWith(
                color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: FutureBuilder<List<RecordedItem>>(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Today\'s recorded payments could not be read from this phone. Close this screen and open it again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.soft),
                  ),
                ),
              );
            }
            final items = snapshot.data ?? const <RecordedItem>[];
            if (items.isEmpty) return _empty(palette);
            return _body(palette, items);
          },
        ),
      ),
    );
  }

  Widget _empty(SignInPalette palette) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BusinessMarkCube(size: 54),
              const SizedBox(height: 14),
              Text('No recorded payments today',
                  style: DesignType.display.copyWith(
                      color: palette.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'When a customer pays your own till or bank and you record it at checkout, it will show here to check against your statement.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.soft, fontSize: 13.5, height: 1.45),
              ),
            ],
          ),
        ),
      );

  Widget _body(SignInPalette palette, List<RecordedItem> items) {
    final hasStatement = _statement.text.trim().isNotEmpty;
    final results = matchRecorded(items, _statement.text);
    final counts = summarise(results);
    final unresolved = results
        .where((r) =>
            r.status != MatchStatus.matched && !_checks.containsKey(r.item.saleId))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(
          'Paste today\'s statement or messages from your own M-Pesa or bank. Counterbase compares them with the payments you recorded. It does not read your texts.',
          style: TextStyle(color: palette.soft, fontSize: 13.5, height: 1.45),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _statement,
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Paste the statement here',
            alignLabelWithHint: true,
            suffixIcon: IconButton(
              tooltip: 'Paste from clipboard',
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: _paste,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (hasStatement) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (counts.matched > 0)
                    Expanded(
                      flex: counts.matched,
                      child: const ColoredBox(color: MoneyColors.cash),
                    ),
                  if (counts.differs + counts.missing > 0)
                    Expanded(
                      flex: counts.differs + counts.missing,
                      child: const ColoredBox(color: MoneyColors.recorded),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${counts.matched} matched',
                  style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(
                  '${counts.differs + counts.missing} to check',
                  style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
        ],
        Container(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(color: palette.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < results.length; i++) ...[
                if (i > 0) Divider(height: 1, color: palette.line),
                _row(palette, results[i], hasStatement),
              ],
            ],
          ),
        ),
        if (hasStatement && unresolved > 0) ...[
          const SizedBox(height: 14),
          _Notice(
            text:
                '$unresolved ${unresolved == 1 ? 'payment is' : 'payments are'} not confirmed by the statement. Ask the cashier to show the M-Pesa message or bank entry, then mark it checked with a note.',
          ),
        ],
      ],
    );
  }

  Widget _row(SignInPalette palette, MatchResult result, bool hasStatement) {
    final item = result.item;
    final check = _checks[item.saleId];
    final checked = check is Map;
    final recordedBy = _details[item.saleId]?.recordedByName ?? '';
    final time = _times[item.saleId];

    late final IconData icon;
    late final Color color;
    late final String chipText;
    if (!hasStatement) {
      icon = Icons.schedule_rounded;
      color = palette.faint;
      chipText = 'Waiting';
    } else if (result.status == MatchStatus.matched) {
      icon = Icons.check_rounded;
      color = MoneyColors.cash;
      chipText = 'Matched';
    } else if (checked) {
      icon = Icons.verified_outlined;
      color = MoneyColors.verified;
      chipText = 'Checked';
    } else {
      icon = Icons.warning_amber_rounded;
      color = MoneyColors.recorded;
      chipText = result.status == MatchStatus.amountDiffers
          ? 'Amount differs'
          : 'Not found';
    }

    final needsAction = hasStatement &&
        result.status != MatchStatus.matched &&
        !checked;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.code,
                        style: DesignType.numeric(
                            fontSize: 13, color: palette.ink)),
                    Text(
                      [
                        if (time != null) _timeFmt.format(time),
                        if (recordedBy.isNotEmpty) recordedBy,
                        item.isBank ? 'Bank' : 'M-Pesa',
                      ].join(' · '),
                      style: TextStyle(color: palette.soft, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat.decimalPattern('en_KE')
                        .format(item.amount.round()),
                    style: DesignType.numeric(fontSize: 13, color: palette.ink),
                  ),
                  Text(chipText,
                      style: TextStyle(
                          color: palette.isDark ? color : _darker(color),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
          if (hasStatement &&
              result.status == MatchStatus.amountDiffers &&
              result.statementAmounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'The statement shows ${result.statementAmounts.map((a) => NumberFormat.decimalPattern('en_KE').format(a)).take(3).join(', ')} beside this code. You recorded ${NumberFormat.decimalPattern('en_KE').format(item.amount.round())}.',
              style: TextStyle(color: palette.soft, fontSize: 12.5, height: 1.4),
            ),
          ],
          if (checked) ...[
            const SizedBox(height: 8),
            Text(
              '${(check['by'] ?? '').toString().isEmpty ? '' : '${check['by']}: '}${check['note']}',
              style: TextStyle(color: palette.soft, fontSize: 12.5, height: 1.4),
            ),
          ],
          if (needsAction) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _markChecked(item),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 40),
                  foregroundColor: DesignColors.accentDark,
                ),
                child: const Text('Mark checked with a note',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.35)!;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final background =
        palette.isDark ? const Color(0xFF3A2A14) : const Color(0xFFFBE9C8);
    final foreground =
        palette.isDark ? const Color(0xFFF0BF82) : const Color(0xFF5A3A06);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
      ),
      child: Text(text,
          style: TextStyle(color: foreground, fontSize: 13.5, height: 1.4)),
    );
  }
}

/// The Counterbase by Arche Axon mark, used on empty states.
class BusinessMarkCube extends StatelessWidget {
  const BusinessMarkCube({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) =>
      AxonLogoTitle(logoSize: size, showText: false);
}

/// The explanation kept for shops connected to the cloud.
class _CloudNotice extends StatelessWidget {
  const _CloudNotice();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'M-Pesa verification',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: GlassCard(
                padding: const EdgeInsets.all(DesignSpacing.xl),
                borderRadius: DesignSpacing.radiusLg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        size: 42, color: DesignColors.accent),
                    const SizedBox(height: DesignSpacing.lg),
                    Text(
                      'Verify debt payments with Paystack',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    const Text(
                      'Pasted M-Pesa messages cannot confirm a debt payment. '
                      'Open Finance, choose the customer debt, and send an '
                      'M-Pesa request. Counterbase will update the balance '
                      'only after Paystack confirms the payment.',
                    ),
                    const SizedBox(height: DesignSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.push('/finance'),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Open Finance'),
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => context.push('/payments/setup'),
                        child: const Text('Check customer payment setup'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
