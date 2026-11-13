import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart' show roundCurrency;
import '../../domain/cash_tender.dart';
import '../../domain/recorded_payment.dart';
import '../providers/cart_provider.dart';
import '../providers/payment_provider.dart';
import '../widgets/record_payment_sheet.dart';
import 'checkout_support.dart';
import 'sell_style.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class _TenderDef {
  const _TenderDef(this.tender, this.label, this.icon);
  final SellTender tender;
  final String label;
  final IconData icon;
}

/// The payment half of the till. It replaces the ticket in the same place when
/// Pay is pressed: no dialog, no bottom sheet, no new page. Esc goes back to
/// the ticket. The money logic is the phone's ([PaymentNotifier] through
/// [DesktopCheckout]); this only lays it out for a keyboard and a wide screen.
class SellPaymentPanel extends ConsumerStatefulWidget {
  const SellPaymentPanel({
    super.key,
    required this.width,
    required this.onBack,
    required this.onSold,
    required this.onPickCustomer,
    this.onOpenPayments,
    this.onOpenPayoutSetup,
    this.customerSingular = 'Customer',
    this.canViewCustomers = true,
  });

  final double width;
  final VoidCallback onBack;
  final ValueChanged<CheckoutResult> onSold;

  /// Opens the customer picker; completes when it closes.
  final Future<void> Function() onPickCustomer;
  final VoidCallback? onOpenPayments;
  final VoidCallback? onOpenPayoutSetup;
  final String customerSingular;
  final bool canViewCustomers;

  @override
  ConsumerState<SellPaymentPanel> createState() => SellPaymentPanelState();
}

class SellPaymentPanelState extends ConsumerState<SellPaymentPanel> {
  late final SellCheckoutHost _host = ref.read(sellCheckoutHostProvider);
  late final RecordedPaymentRules _rules = _host.recordedRules;
  late final List<_TenderDef> _tenders = [
    const _TenderDef(SellTender.cash, 'Cash', Icons.payments_outlined),
    if (_host.isLocalWorkspace) ...[
      if (_rules.enabled) ...[
        const _TenderDef(
          SellTender.recordedMpesa,
          'M-Pesa to till',
          Icons.phone_android_rounded,
        ),
        const _TenderDef(
          SellTender.recordedBank,
          'Bank transfer',
          Icons.account_balance_rounded,
        ),
      ],
    ] else
      const _TenderDef(
        SellTender.mpesa,
        'M-Pesa',
        Icons.phone_android_rounded,
      ),
    const _TenderDef(
      SellTender.credit,
      'On credit',
      Icons.account_balance_wallet_outlined,
    ),
    const _TenderDef(SellTender.split, 'Split', Icons.call_split_rounded),
  ];

  late SellTender _tender = SellTender.cash;
  final _cash = TextEditingController();
  final _phone = TextEditingController();
  final _splitCash = TextEditingController();
  final _cashFocus = FocusNode(debugLabel: 'pay-cash');
  final _phoneFocus = FocusNode(debugLabel: 'pay-phone');
  final _splitFocus = FocusNode(debugLabel: 'pay-split');
  bool _busy = false;
  CheckoutResult? _result;

  String? _payoutStatus;
  bool _payoutVerified = false;
  bool _checkingPayout = false;

  /// Seconds since the M-Pesa request was sent, counted by the ticker (a real
  /// elapsed time, not a countdown). Null when this panel did not send it.
  int? _waitSeconds;
  String _mpesaPhone = '';
  Timer? _ticker;
  int _customerPhoneRequest = 0;

  bool get _canAcceptMpesa => _payoutStatus == 'ACTIVE' && _payoutVerified;

  @override
  void initState() {
    super.initState();
    final total = ref.read(cartProvider).total;
    _cash.text = _plain(total);
    _cash.selection =
        TextSelection(baseOffset: 0, extentOffset: _cash.text.length);
    final pay = ref.read(paymentProvider);
    if (!_host.isLocalWorkspace) {
      _loadPayout();
      if (pay.currentTransactionId != null ||
          pay.hasUnresolvedMerchantPayment) {
        _tender = SellTender.mpesa;
      }
    }
    _focusAmountField();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final pay = ref.read(paymentProvider);
      if (_busy || pay.isProcessing || pay.currentTransactionId != null) {
        setState(() {
          final seconds = _waitSeconds;
          if (seconds != null) _waitSeconds = seconds + 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cash.dispose();
    _phone.dispose();
    _splitCash.dispose();
    _cashFocus.dispose();
    _phoneFocus.dispose();
    _splitFocus.dispose();
    super.dispose();
  }

  /// The field for the chosen method takes the keyboard (the search field
  /// behind it keeps focus otherwise): type the amount, press Enter.
  void _focusAmountField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (_tender) {
        case SellTender.cash:
          _cashFocus.requestFocus();
        case SellTender.mpesa:
          _phoneFocus.requestFocus();
        case SellTender.split:
          _splitFocus.requestFocus();
        default:
          FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Future<void> _loadPayout() async {
    setState(() => _checkingPayout = true);
    try {
      final account = await _host.loadPayoutAccount();
      if (!mounted) return;
      setState(() {
        _payoutStatus = account?['status']?.toString().toUpperCase();
        _payoutVerified = account?['paystackVerified'] == true;
        _checkingPayout = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _payoutStatus = 'UNKNOWN';
        _payoutVerified = false;
        _checkingPayout = false;
      });
    }
  }

  /// True while Esc must not leave: a sale or request is being sent.
  bool get busy => _busy || ref.read(paymentProvider).isProcessing;

  void selectTenderIndex(int index) {
    if (index < 0 || index >= _tenders.length || _locked) return;
    _select(_tenders[index].tender);
  }

  bool get _locked {
    final pay = ref.read(paymentProvider);
    return _busy ||
        pay.isProcessing ||
        pay.currentTransactionId != null ||
        pay.hasUnresolvedMerchantPayment;
  }

  void _select(SellTender tender) {
    if (tender == _tender) return;
    setState(() {
      _tender = tender;
      _result = null;
    });
    _focusAmountField();
    if (ref.read(permissionsProvider).canSeeCustomers &&
        tender == SellTender.mpesa &&
        _phone.text.trim().isEmpty) {
      final id = ref.read(cartProvider).customerId;
      if (id != null) {
        final request = ++_customerPhoneRequest;
        _host.customerPhone(id).then((phone) {
          if (mounted &&
              request == _customerPhoneRequest &&
              ref.read(permissionsProvider).canSeeCustomers &&
              phone != null &&
              _phone.text.trim().isEmpty) {
            setState(() => _phone.text = phone);
          }
        });
      }
    }
  }

  double get _cashReceived => double.tryParse(_cash.text.trim()) ?? 0;

  double get _splitCashAmount => double.tryParse(_splitCash.text.trim()) ?? 0;

  bool _splitValid(double total) {
    final cash = _splitCashAmount;
    return cash > 0 && roundCurrency(total - cash) > 0;
  }

  Future<void> _run(
    SellTender tender, {
    double cashReceived = 0,
    String phone = '',
    double splitCash = 0,
    RecordedPaymentDetails? recorded,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
      if (tender == SellTender.mpesa) {
        _waitSeconds = 0;
        _mpesaPhone = phone;
      }
    });
    CheckoutResult result;
    try {
      result = await DesktopCheckout(ref).pay(
        context,
        tender,
        cashReceived: cashReceived,
        phone: phone,
        splitCash: splitCash,
        recorded: recorded,
      );
    } catch (error) {
      result = CheckoutResult.failed(apiErrorMessage(error));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.status != CheckoutStatus.sold) _result = result;
    });
    if (result.status == CheckoutStatus.sold) widget.onSold(result);
  }

  /// Enter / the big button.
  Future<void> primaryAction() async {
    final cart = ref.read(cartProvider);
    final pay = ref.read(paymentProvider);
    if (cart.items.isEmpty || _busy || pay.isProcessing) return;
    if (pay.hasUnresolvedMerchantPayment &&
        (pay.isRecoveredMerchantPayment || pay.currentTransactionId == null) &&
        widget.onOpenPayments != null) {
      widget.onOpenPayments!();
      return;
    }
    switch (_tender) {
      case SellTender.cash:
        if (!coversTotal(total: cart.total, tendered: _cashReceived)) return;
        await _run(SellTender.cash, cashReceived: _cashReceived);
      case SellTender.mpesa:
        final pending = pay.currentTransactionId != null;
        if (!pending && (!_canAcceptMpesa || !isKenyanPhone(_phone.text))) {
          return;
        }
        await _run(SellTender.mpesa, phone: _phone.text);
      case SellTender.recordedMpesa:
      case SellTender.recordedBank:
        final details = await showRecordPaymentSheet(
          context,
          method: _tender == SellTender.recordedMpesa
              ? RecordedPaymentMethod.mpesa
              : RecordedPaymentMethod.bank,
          total: cart.total,
          rules: _rules,
          recorderId: _host.recorderId,
          recorderName: _host.recorderName,
          approverForPin: _host.approverForPin,
        );
        if (details == null || !mounted) return;
        await _run(_tender, recorded: details);
      case SellTender.credit:
        if (cart.customerId == null) {
          await widget.onPickCustomer();
          if (mounted) setState(() {});
          return;
        }
        await _run(SellTender.credit);
      case SellTender.split:
        if (cart.customerId == null) {
          await widget.onPickCustomer();
          if (mounted) setState(() {});
          return;
        }
        if (!_splitValid(cart.total)) return;
        await _run(SellTender.split, splitCash: _splitCashAmount);
    }
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    ref.listen(permissionsProvider, (previous, next) {
      if (previous?.canSeeCustomers == true && !next.canSeeCustomers) {
        _customerPhoneRequest++;
        _phone.clear();
        _mpesaPhone = '';
        if (mounted) setState(() {});
      }
    });
    ref.watch(permissionsProvider);
    final cart = ref.watch(cartProvider);
    final pay = ref.watch(paymentProvider);
    final pending =
        pay.currentTransactionId != null || pay.hasUnresolvedMerchantPayment;
    final spec = _primary(cart, pay, pending);

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: s.ticket,
        border: Border(left: BorderSide(color: s.p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, pay),
          _summary(s, cart),
          Divider(height: 1, color: s.p.border),
          _tenderGrid(s, pending, pay),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _body(s, cart, pay, pending),
                  ..._messages(s, pay, pending),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: s.p.border)),
            ),
            child: SellPrimaryButton(
              key: const ValueKey('payment-primary'),
              label: spec.label,
              keyHint: 'Enter',
              loading: _busy || pay.isProcessing,
              onPressed: spec.enabled ? primaryAction : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(SellStyle s, PaymentState pay) {
    final canLeave = !(_busy || pay.isProcessing);
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
      child: Row(
        children: [
          SellQuietButton(
            label: 'Back to ticket',
            icon: Icons.arrow_back_rounded,
            keyHint: 'Esc',
            onPressed: canLeave ? widget.onBack : null,
          ),
          const Spacer(),
          Text('Payment', style: s.heading(size: 14)),
        ],
      ),
    );
  }

  Widget _summary(SellStyle s, CartState cart) {
    final total = cart.total;
    final cash = _tender == SellTender.cash ? _cashReceived : 0.0;
    final change = cashChange(total: total, tendered: cash);
    final remaining = cashShortfall(total: total, tendered: cash);
    final settled = cash > 0 && remaining == 0;
    Widget cell(String label, String value, {Color? color, Key? key}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: s.body(size: 12, color: s.p.textMuted)),
              Text(
                value,
                key: key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: s.number(size: 14, color: color),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount due',
                      style: s.body(size: 12, color: s.p.textMuted),
                    ),
                    Text(
                      '${cart.itemCount} ${cart.itemCount == 1 ? 'item' : 'items'}'
                      '${!ref.read(permissionsProvider).canSeeCustomers || cart.customerName == null ? '' : ' · ${cart.customerName}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: s.body(size: 12, color: s.p.textFaint),
                    ),
                  ],
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  sellMoney(total),
                  key: const ValueKey('payment-due'),
                  style: s.heading(size: 26),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              cell('Paid so far', sellMoney(cash)),
              if (change > 0)
                cell(
                  'Change due',
                  sellMoney(change),
                  color: s.success,
                  key: const ValueKey('payment-change'),
                )
              else
                cell(
                  'Remaining',
                  sellMoney(remaining),
                  color: settled ? s.p.text : s.warning,
                  key: const ValueKey('payment-remaining'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tenderGrid(SellStyle s, bool pending, PaymentState pay) {
    final locked = _locked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _tenders.length; i++)
                SizedBox(
                  width: w,
                  height: 40,
                  child: _TenderButton(
                    def: _tenders[i],
                    index: i + 1,
                    selected: _tender == _tenders[i].tender,
                    enabled: !locked || _tender == _tenders[i].tender,
                    onTap: () => _select(_tenders[i].tender),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(SellStyle s, CartState cart, PaymentState pay, bool pending) {
    switch (_tender) {
      case SellTender.cash:
        return _cashBody(s, cart);
      case SellTender.mpesa:
        return _mpesaBody(s, cart, pay, pending);
      case SellTender.recordedMpesa:
      case SellTender.recordedBank:
        final mpesa = _tender == SellTender.recordedMpesa;
        return _note(
          s,
          mpesa
              ? 'The customer pays your own till${_rules.tillNumber.isEmpty ? '' : ' (${_rules.tillNumber})'}. You then paste the M-Pesa message so the code and amount are checked and saved with the sale.'
              : 'The customer pays your bank account. You then enter the bank reference so it is saved with the sale.',
        );
      case SellTender.credit:
        return _customerNote(
          s,
          cart,
          'will owe ${sellMoney(cart.total)} for this sale. The shop\'s credit limit is checked before it is saved.',
        );
      case SellTender.split:
        return _splitBody(s, cart);
    }
  }

  Widget _note(SellStyle s, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text,
          style: s.body(size: 12.5, color: s.p.textMuted, height: 1.45),
        ),
      );

  Widget _customerNote(SellStyle s, CartState cart, String tail) {
    if (cart.customerId == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(
            s,
            'This needs a ${widget.customerSingular.toLowerCase()} so the balance is recorded against someone.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () async {
                await widget.onPickCustomer();
                if (mounted) setState(() {});
              },
              child: const Text('Choose customer  F3'),
            ),
          ),
        ],
      );
    }
    final customer = ref.read(permissionsProvider).canSeeCustomers
        ? cart.customerName ?? widget.customerSingular
        : 'Selected customer';
    return _note(s, '$customer $tail');
  }

  Widget _cashBody(SellStyle s, CartState cart) {
    final total = cart.total;
    final received = _cashReceived;
    final typed = _cash.text.trim().isNotEmpty;
    final short = cashShortfall(total: total, tendered: received);
    final chips = suggestedTenders(total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cash received', style: s.body(size: 12, color: s.p.textMuted)),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextField(
            key: const ValueKey('cash-field'),
            controller: _cash,
            focusNode: _cashFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => primaryAction(),
            onTapOutside: (_) {},
            style: s.number(size: 16),
            decoration: InputDecoration(
              prefixText: 'KES  ',
              prefixStyle: s.body(color: s.p.textMuted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final amount in chips)
              ActionChip(
                key: ValueKey('cash-chip-${amount.toInt()}'),
                label: Text(
                  amount == total ? 'Exact' : sellMoney(amount, symbol: false),
                  style: s.number(size: 12),
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _cash.text = _plain(amount);
                  _cash.selection = TextSelection.collapsed(
                    offset: _cash.text.length,
                  );
                }),
              ),
          ],
        ),
        if (typed && short > 0) ...[
          const SizedBox(height: 8),
          Text(
            'KES ${_plain(short)} short. The customer needs to give more.',
            key: const ValueKey('cash-short'),
            style: s.body(
              size: 12.5,
              weight: FontWeight.w600,
              color: s.warning,
            ),
          ),
        ],
      ],
    );
  }

  Widget _splitBody(SellStyle s, CartState cart) {
    if (cart.customerId == null) {
      return _customerNote(s, cart, '');
    }
    final customer = ref.read(permissionsProvider).canSeeCustomers
        ? cart.customerName ?? widget.customerSingular
        : 'customer account';
    final cash = _splitCashAmount;
    final credit = roundCurrency(cart.total - cash);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cash now', style: s.body(size: 12, color: s.p.textMuted)),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextField(
            key: const ValueKey('split-field'),
            controller: _splitCash,
            focusNode: _splitFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => primaryAction(),
            onTapOutside: (_) {},
            style: s.number(size: 16),
            decoration: InputDecoration(
              prefixText: 'KES  ',
              prefixStyle: s.body(color: s.p.textMuted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          cash <= 0
              ? 'Enter the cash part. The rest goes on $customer\'s account.'
              : credit > 0
                  ? 'On $customer\'s account: ${sellMoney(credit)}'
                  : 'Cash covers the whole sale. Use Cash instead, or lower the cash part.',
          style: s.body(
            size: 12.5,
            weight: FontWeight.w600,
            color: cash > 0 && credit <= 0 ? s.warning : s.p.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  String _maskedPhone(String raw) {
    final digits = normalizeKenyanPhone(raw);
    if (digits.length < 12) return raw;
    final local = '0${digits.substring(3)}';
    return '${local.substring(0, 4)} *** ${local.substring(local.length - 3)}';
  }

  String _elapsed() {
    final seconds = _waitSeconds;
    if (seconds == null) return '';
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _mpesaBody(
    SellStyle s,
    CartState cart,
    PaymentState pay,
    bool pending,
  ) {
    if (_checkingPayout) {
      return _note(s, 'Checking your payout account…');
    }
    if (!_canAcceptMpesa && !pending) {
      final status = _payoutStatus;
      final detail = status == 'PENDING_VERIFICATION'
          ? 'The payment partner must verify your business bank account before customers can pay by M-Pesa.'
          : status == 'NOT_CONFIGURED'
              ? 'Connect your business bank account to accept customer M-Pesa payments.'
              : status == 'INACTIVE'
                  ? 'Your payout account is inactive. Review it in Customer payments.'
                  : 'We could not confirm your payout account. Check your connection or Customer payments.';
      return _StatusCard(
        tone: SellNoticeKind.warning,
        title: status == 'PENDING_VERIFICATION'
            ? 'Verification pending'
            : 'M-Pesa setup needed',
        message: detail,
        action: widget.onOpenPayoutSetup == null
            ? null
            : SellNoticeAction(
                'Open Customer payments',
                widget.onOpenPayoutSetup!,
              ),
      );
    }
    final waiting = _busy || pay.isProcessing;
    if (waiting) {
      final long = (_waitSeconds ?? 0) >= 15;
      return _StatusCard(
        key: const ValueKey('mpesa-waiting'),
        tone: SellNoticeKind.info,
        title: 'Waiting for the customer',
        message: long
            ? 'Still waiting. Ask the customer to check their phone and enter their M-Pesa PIN.'
            : 'Request sent to ${_maskedPhone(_mpesaPhone.isEmpty ? _phone.text : _mpesaPhone)}. The customer approves it on their phone with their M-Pesa PIN.',
        footer: 'Waiting ${_elapsed()}',
        progress: true,
      );
    }
    if (pending) {
      return _StatusCard(
        key: const ValueKey('mpesa-pending'),
        tone: SellNoticeKind.info,
        title: 'Not confirmed yet',
        message:
            'M-Pesa has not confirmed this payment. The customer may still be entering their PIN. Check again in a few seconds. No second request is sent, and the other payment methods unlock once this is settled.',
        footer: _waitSeconds == null ? null : 'Waiting ${_elapsed()}',
        action: widget.onOpenPayments == null
            ? null
            : SellNoticeAction('Open Payments', widget.onOpenPayments!),
      );
    }
    final phone = _phone.text;
    final invalid = phone.trim().isNotEmpty && !isKenyanPhone(phone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Customer phone number',
          style: s.body(size: 12, color: s.p.textMuted),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextField(
            key: const ValueKey('mpesa-phone'),
            controller: _phone,
            focusNode: _phoneFocus,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => primaryAction(),
            onTapOutside: (_) {},
            style: s.number(size: 15),
            decoration: const InputDecoration(
              hintText: '0712 345 678',
              prefixIcon: Icon(Icons.phone_android_rounded, size: 18),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          invalid
              ? 'Enter a Kenyan mobile number, like 0712 345 678.'
              : 'Sends a request for ${sellMoney(cart.total)} to this phone. The customer approves it with their M-Pesa PIN.',
          style: s.body(
            size: 12.5,
            color: invalid ? s.danger : s.p.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// Cards for the last result: stock changes, rule stops and errors.
  List<Widget> _messages(SellStyle s, PaymentState pay, bool pending) {
    final r = _result;
    if (r == null) return const [];
    final cards = <Widget>[];
    if (r.stockIssues.isNotEmpty) {
      cards.add(const SizedBox(height: 10));
      cards.add(
        _StatusCard(
          key: const ValueKey('stock-changed'),
          tone: SellNoticeKind.warning,
          title: 'Stock changed',
          message:
              '${r.stockIssues.map((i) => '${i.name}: ${sellQty(i.requested)} on the ticket, ${i.available == null ? 'stock unknown' : '${sellQty(i.available!)} available'}').join('\n')}\nGo back to the ticket (Esc), fix these lines, then pay again.',
        ),
      );
    } else if (r.message != null && !pending) {
      cards.add(const SizedBox(height: 10));
      cards.add(
        _StatusCard(
          key: const ValueKey('payment-message'),
          tone: r.status == CheckoutStatus.failed
              ? SellNoticeKind.error
              : SellNoticeKind.warning,
          title: r.status == CheckoutStatus.failed
              ? 'The sale was not saved'
              : 'Not done yet',
          message: r.message!,
        ),
      );
    }
    return cards;
  }

  _Primary _primary(CartState cart, PaymentState pay, bool pending) {
    if (pay.hasUnresolvedMerchantPayment &&
        (pay.isRecoveredMerchantPayment || pay.currentTransactionId == null) &&
        widget.onOpenPayments != null) {
      return const _Primary('Open Payments to check', true);
    }
    switch (_tender) {
      case SellTender.cash:
        return _Primary(
          'Complete sale',
          coversTotal(total: cart.total, tendered: _cashReceived),
        );
      case SellTender.mpesa:
        if (_busy || pay.isProcessing) return const _Primary('Waiting…', false);
        if (pending) return const _Primary('Check again', true);
        return _Primary(
          'Send M-Pesa request',
          _canAcceptMpesa && isKenyanPhone(_phone.text),
        );
      case SellTender.recordedMpesa:
        return const _Primary('Record M-Pesa payment', true);
      case SellTender.recordedBank:
        return const _Primary('Record bank transfer', true);
      case SellTender.credit:
        return _Primary(
          cart.customerId == null ? 'Choose customer' : 'Put on credit',
          true,
        );
      case SellTender.split:
        return _Primary(
          cart.customerId == null ? 'Choose customer' : 'Complete split sale',
          cart.customerId == null || _splitValid(cart.total),
        );
    }
  }
}

class _Primary {
  const _Primary(this.label, this.enabled);
  final String label;
  final bool enabled;
}

class _TenderButton extends StatelessWidget {
  const _TenderButton({
    required this.def,
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _TenderDef def;
  final int index;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: HoverBuilder(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        builder: (context, hovered) => Material(
          color: selected
              ? s.p.selected
              : (hovered && enabled ? s.p.hover : s.surface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? s.accentFill : s.p.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            hoverColor: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(def.icon, size: 18, color: s.p.text),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      def.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: s.body(
                        size: 12.5,
                        weight: selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  SellKey('$index'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.tone,
    required this.title,
    required this.message,
    this.footer,
    this.action,
    this.progress = false,
  });

  final SellNoticeKind tone;
  final String title;
  final String message;
  final String? footer;
  final SellNoticeAction? action;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final color = switch (tone) {
      SellNoticeKind.info => s.info,
      SellNoticeKind.warning => s.warning,
      SellNoticeKind.error => s.danger,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.tint(color),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: s.body(size: 13.5, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            message,
            style: s.body(size: 12.5, color: s.p.textMuted, height: 1.45),
          ),
          if (progress) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                color: s.accentFill,
                backgroundColor: s.p.border,
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: s.number(size: 12, color: s.p.textMuted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SellQuietButton(
                label: action!.label,
                onPressed: action!.onPressed,
                color: s.p.text,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
