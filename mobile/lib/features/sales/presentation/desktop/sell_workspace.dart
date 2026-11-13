import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/desktop/scan_capture.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/payment_provider.dart';
import '../widgets/product_quick_add.dart';
import 'checkout_support.dart';
import 'sell_catalog_pane.dart';
import 'sell_dialogs.dart';
import 'sell_payment_panel.dart';
import 'sell_style.dart';
import 'sell_ticket_panel.dart';

/// Finds the product whose code (the SKU / barcode field) is [code]. A scanner
/// may send an EAN-13 for a code stored as a UPC-A, so leading zeros are
/// ignored when both sides are digits.
Future<Map<String, dynamic>?> findProductByCode(
  WidgetRef ref,
  String code,
) async {
  final wanted = code.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  final products = await ref.read(
    filteredProductsProvider(FilterParams(searchQuery: code.trim())).future,
  );
  String zeros(String v) => RegExp(r'^\d+$').hasMatch(v)
      ? v.replaceFirst(RegExp(r'^0+(?=\d)'), '')
      : v;
  for (final product in products) {
    final sku = (product['sku'] as String? ?? '').trim().toLowerCase();
    if (sku.isNotEmpty && (sku == wanted || zeros(sku) == zeros(wanted))) {
      return product;
    }
  }
  return null;
}

/// The Sell page on a computer: product search and browsing on the left, the
/// ticket (or the payment, in the same place) on the right. Used instead of
/// the phone's Sell → Cart → Payment pages inside the desktop shell.
///
/// Keyboard: F2 search, F3 customer, F4 quantity, F7 discount, F8 void, F9 or
/// Ctrl+Enter pay, Ctrl+N new sale, Ctrl+H hold, Ctrl+Shift+H held sales, Esc
/// back, F1 or ? the list. A barcode scanner types into the page from anywhere
/// ([ScanCapture]).
class SellWorkspace extends ConsumerStatefulWidget {
  const SellWorkspace({
    super.key,
    required this.onSaleComplete,
    this.showFavorites = false,
    this.onFavoritesChanged,
    this.productPages = const [],
    this.selectedProductPageId,
    this.onProductPageChanged,
    this.catalogRefreshing = false,
    this.catalogSyncFailed = false,
    this.isOffline = false,
    this.isLocalWorkspace = false,
    this.onRetryCatalog,
    this.onOpenProducts,
    this.onAddUnknownProduct,
    this.onOpenPayments,
    this.onOpenPayoutSetup,
    this.heldSalesCount = 0,
    this.heldSalesRestoring = false,
    this.heldSalesRestoreWarning,
    this.onHoldSale,
    this.onOpenHeldSales,
    this.startInPayment = false,
  });

  /// The sale is saved and the cart is clear: show the receipt.
  final void Function(CheckoutResult result) onSaleComplete;

  final bool showFavorites;
  final ValueChanged<bool>? onFavoritesChanged;
  final List<BusinessLayoutProductPage> productPages;
  final String? selectedProductPageId;
  final ValueChanged<String?>? onProductPageChanged;
  final bool catalogRefreshing;
  final bool catalogSyncFailed;
  final bool isOffline;
  final bool isLocalWorkspace;
  final VoidCallback? onRetryCatalog;
  final VoidCallback? onOpenProducts;

  /// "Add product" on the unknown-barcode banner, with the code.
  final ValueChanged<String>? onAddUnknownProduct;
  final VoidCallback? onOpenPayments;
  final VoidCallback? onOpenPayoutSetup;
  final int heldSalesCount;
  final bool heldSalesRestoring;
  final String? heldSalesRestoreWarning;
  final VoidCallback? onHoldSale;
  final VoidCallback? onOpenHeldSales;

  /// Opens with the payment panel showing (a test or a deep link).
  final bool startInPayment;

  @override
  ConsumerState<SellWorkspace> createState() => _SellWorkspaceState();
}

enum _Panel { ticket, payment }

class _SellWorkspaceState extends ConsumerState<SellWorkspace> {
  static const _viewKey = 'sell_product_view';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'sell-search');
  final _ticketFocus = FocusNode(debugLabel: 'sell-ticket');
  final _rootFocus = FocusNode(
    debugLabel: 'sell-root',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final _ticketKey = GlobalKey<SellTicketPanelState>();
  final _paymentKey = GlobalKey<SellPaymentPanelState>();

  _Panel _panel = _Panel.ticket;
  SellProductView _view = SellProductView.list;
  String? _selectedLineId;
  SellNotice? _notice;
  Timer? _noticeTimer;
  Timer? _digitTimer;
  late final ScanCapture _capture;
  final _scanner = ScannerStatus();

  @override
  void initState() {
    super.initState();
    if (widget.startInPayment) _panel = _Panel.payment;
    _capture = ScanCapture(
      onScan: _onScan,
      enabled: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
      onBurst: () => _digitTimer?.cancel(),
    )..attach();
    _scanner.show();
    _loadView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _panel == _Panel.ticket) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _capture.detach();
    _scanner.dispose();
    _noticeTimer?.cancel();
    _digitTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _ticketFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  Future<void> _loadView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_viewKey);
      if (mounted && saved != null) {
        setState(() {
          _view = saved == 'grid' ? SellProductView.grid : SellProductView.list;
        });
      }
    } catch (_) {
      // Not remembering the view is harmless.
    }
  }

  Future<void> _setView(SellProductView view) async {
    setState(() => _view = view);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _viewKey, view == SellProductView.grid ? 'grid' : 'list');
    } catch (_) {}
  }

  // ─── Notices ───

  void _notify(SellNotice notice, {bool sticky = false}) {
    _noticeTimer?.cancel();
    setState(() => _notice = notice);
    if (!sticky && notice.actions.isEmpty) {
      _noticeTimer = Timer(const Duration(seconds: 7), () {
        if (mounted && identical(_notice, notice)) {
          setState(() => _notice = null);
        }
      });
    }
  }

  void _clearNotice() {
    _noticeTimer?.cancel();
    if (_notice != null) setState(() => _notice = null);
  }

  // ─── Focus ───

  bool _inTextField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _focusSearch() {
    if (_panel != _Panel.ticket) return;
    _searchFocus.requestFocus();
  }

  void _focusTicket() {
    if (_panel != _Panel.ticket || ref.read(cartProvider).items.isEmpty) return;
    _ticketFocus.requestFocus();
  }

  /// After a click on empty space nothing has focus and the keyboard (and the
  /// scanner's focus) would be lost; take it back to the search field.
  void _restoreFocus() {
    if (!mounted || _panel != _Panel.ticket) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!_rootFocus.hasFocus) _searchFocus.requestFocus();
  }

  // ─── Actions ───

  bool get _ticketLocked {
    final pay = ref.read(paymentProvider);
    return pay.currentTransactionId != null || pay.hasUnresolvedMerchantPayment;
  }

  Future<void> _addProduct(Map<String, dynamic> product) async {
    if (_panel == _Panel.payment || _ticketLocked) {
      _notify(
        const SellNotice(
          'A payment is open, so the ticket cannot change. Press Esc to go back, or finish the payment first.',
          kind: SellNoticeKind.warning,
        ),
      );
      return;
    }
    final result = await quickAddToCart(ref, product);
    if (!mounted) return;
    if (!result.success) {
      _notify(
        SellNotice(
          result.isStockBlocked
              ? stockBlockedMessage(
                  product['name'] as String? ?? 'This item',
                  result.currentStock,
                  unitLabel: product['unit']?.toString(),
                )
              : result.message,
          kind: SellNoticeKind.error,
        ),
      );
      _focusSearch();
      return;
    }
    _clearNotice();
    final line = ref
        .read(cartProvider)
        .items
        .where((i) => i.productId == product['id'])
        .firstOrNull;
    setState(() => _selectedLineId = line?.id);
    if (!_inTextField() || !_ticketFocus.hasFocus) _focusSearch();
  }

  Future<void> _onScan(ScanEvent scan) async {
    _scanner.flash(scan.code);
    if (_panel == _Panel.payment) {
      _notify(
        SellNotice(
          'Scanned ${scan.code}, but a payment is open. Press Esc to go back to the ticket, then scan again.',
          kind: SellNoticeKind.warning,
        ),
      );
      return;
    }
    Map<String, dynamic>? product;
    try {
      product = await findProductByCode(ref, scan.code);
    } catch (_) {
      if (!mounted) return;
      _notify(
        SellNotice(
          'Could not look up barcode ${scan.code}. Try again or search by name.',
          kind: SellNoticeKind.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (product == null) {
      _notify(
        SellNotice(
          'Barcode ${scan.code} not found.',
          kind: SellNoticeKind.warning,
          actions: [
            if (widget.onAddUnknownProduct != null)
              SellNoticeAction(
                'Add product',
                () {
                  _clearNotice();
                  widget.onAddUnknownProduct!(scan.code);
                },
              ),
            SellNoticeAction('Search by name', () {
              _clearNotice();
              _searchController.clear();
              _focusSearch();
            }),
          ],
        ),
        sticky: true,
      );
      return;
    }
    await _addProduct(product);
  }

  Future<void> _pickCustomer() async {
    if (_ticketLocked) return;
    final layout = ref.read(businessLayoutProvider);
    await showSellCustomerPicker(
      context,
      ref,
      customerSingular: layout.customerSingular,
      customersLabel: layout.customersLabel,
      canViewCustomers: ref.read(permissionsProvider).canSeeCustomers,
    );
    if (mounted) _focusSearch();
  }

  Future<void> _discount() async {
    if (ref.read(cartProvider).items.isEmpty || _ticketLocked) return;
    if (!ref.read(permissionsProvider).canApplyDiscount) {
      _notify(const SellNotice(
        'You do not have permission to apply discounts.',
        kind: SellNoticeKind.error,
      ));
      return;
    }
    await showSellDiscountDialog(context, ref);
    if (mounted) _focusSearch();
  }

  Future<void> _voidTicket() async {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty || _ticketLocked) return;
    final ok = await confirmVoidTicket(context, cart.itemCount);
    if (!mounted) return;
    if (ok) {
      ref.read(cartProvider.notifier).clear();
      setState(() {
        _selectedLineId = null;
        _panel = _Panel.ticket;
      });
      _notify(const SellNotice('Ticket voided. Nothing was saved.'));
    }
    _focusSearch();
  }

  void _newSale() {
    if (ref.read(cartProvider).items.isEmpty) {
      _searchController.clear();
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(selectedCategoryProvider.notifier).state = null;
      setState(() => _panel = _Panel.ticket);
      _focusSearch();
    } else {
      _voidTicket();
    }
  }

  void _openPayment() {
    if (ref.read(cartProvider).items.isEmpty) return;
    _clearNotice();
    setState(() => _panel = _Panel.payment);
  }

  void _backToTicket() {
    if (_paymentKey.currentState?.busy ?? false) {
      _notify(
        const SellNotice(
          'Wait for the payment to finish before leaving. It takes a few seconds.',
          kind: SellNoticeKind.warning,
        ),
      );
      return;
    }
    setState(() => _panel = _Panel.ticket);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearch());
  }

  void _sold(CheckoutResult result) {
    setState(() {
      _panel = _Panel.ticket;
      _selectedLineId = null;
    });
    widget.onSaleComplete(result);
  }

  // ─── Keyboard ───

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isDown = event is KeyDownEvent;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed;
    final inText = _inTextField();
    final payment = _panel == _Panel.payment;

    if (!isDown) return KeyEventResult.ignored;

    if (ctrl && key == LogicalKeyboardKey.keyH) {
      final callback =
          keyboard.isShiftPressed ? widget.onOpenHeldSales : widget.onHoldSale;
      if (callback != null) {
        callback();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.f1 ||
        (!inText && !ctrl && event.character == '?')) {
      showSellShortcuts(context).then((_) {
        if (mounted) _focusSearch();
      });
      return KeyEventResult.handled;
    }
    if (payment && ctrl) {
      // Ctrl+1..6 picks how they pay even while typing an amount.
      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
      ];
      final index = digits.indexOf(key);
      if (index >= 0) {
        _paymentKey.currentState?.selectTenderIndex(index);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.f2 ||
        (ctrl && key == LogicalKeyboardKey.digit1)) {
      if (payment) return KeyEventResult.handled;
      _focusSearch();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.digit3) {
      _focusTicket();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f3) {
      _pickCustomer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f4) {
      if (!payment) _ticketKey.currentState?.editSelectedQuantity();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f7) {
      if (!payment) _discount();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f8) {
      if (!payment) _voidTicket();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f9 ||
        (ctrl &&
            (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter))) {
      if (payment) {
        _paymentKey.currentState?.primaryAction();
      } else {
        _openPayment();
      }
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyN) {
      _newSale();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (payment) {
        _backToTicket();
        return KeyEventResult.handled;
      }
      if (_notice != null) {
        _clearNotice();
        return KeyEventResult.handled;
      }
      if (!_searchFocus.hasFocus) {
        _focusSearch();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (payment && !inText && !ctrl) {
      final ch = event.character;
      if (ch != null && ch.length == 1 && '123456'.contains(ch)) {
        // A scanner's first digit looks the same; wait a moment and drop the
        // key if a second fast character shows it was a barcode.
        _digitTimer?.cancel();
        final index = int.parse(ch) - 1;
        _digitTimer = Timer(const Duration(milliseconds: 70), () {
          if (mounted) _paymentKey.currentState?.selectTenderIndex(index);
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _paymentKey.currentState?.primaryAction();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(businessLayoutProvider);
    final permissions = ref.watch(permissionsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width >= 1600 ? 420.0 : (width >= 1200 ? 380.0 : 340.0);
    final pay = ref.watch(paymentProvider);
    final pending =
        pay.currentTransactionId != null || pay.hasUnresolvedMerchantPayment;
    final s = SellStyle.of(context);

    final ticket = SellTicketPanel(
      key: _ticketKey,
      width: panelWidth,
      focusNode: _ticketFocus,
      selectedLineId: _selectedLineId,
      onSelectLine: (id) => setState(() => _selectedLineId = id),
      onLeaveTicket: _focusSearch,
      onPay: _openPayment,
      onPickCustomer: _pickCustomer,
      onDiscount: _discount,
      onVoid: _voidTicket,
      onMessage: _notify,
      onHoldSale: widget.onHoldSale,
      onOpenHeldSales: widget.onOpenHeldSales,
      heldSalesCount: widget.heldSalesCount,
      heldSalesRestoring: widget.heldSalesRestoring,
      heldSalesRestoreWarning: widget.heldSalesRestoreWarning,
      locked: pending,
      payPending: pending,
      showCustomer: layout.effectiveShowPosCustomer,
      customerLabel: layout.customerSingular,
      canApplyDiscount: permissions.canApplyDiscount,
      canViewCustomers: permissions.canSeeCustomers,
    );
    final payment = SellPaymentPanel(
      key: _paymentKey,
      width: panelWidth,
      onBack: _backToTicket,
      onSold: _sold,
      onPickCustomer: _pickCustomer,
      onOpenPayments: widget.onOpenPayments,
      onOpenPayoutSetup: widget.onOpenPayoutSetup,
      customerSingular: layout.customerSingular,
      canViewCustomers: permissions.canSeeCustomers,
    );

    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerUp: (_) => WidgetsBinding.instance
            .addPostFrameCallback((_) => _restoreFocus()),
        child: ColoredBox(
          color: s.p.panel,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  // Dimmed while paying: the ticket is locked until Esc.
                  child: Opacity(
                    opacity: _panel == _Panel.payment ? 0.5 : 1,
                    child: SellCatalogPane(
                      searchController: _searchController,
                      searchFocus: _searchFocus,
                      view: _view,
                      onViewChanged: _setView,
                      onAdd: _addProduct,
                      notice: _notice,
                      onDismissNotice: _clearNotice,
                      showFavorites: widget.showFavorites,
                      onFavoritesChanged: widget.onFavoritesChanged,
                      productPages: widget.productPages,
                      selectedProductPageId: widget.selectedProductPageId,
                      onProductPageChanged: widget.onProductPageChanged,
                      catalogRefreshing: widget.catalogRefreshing,
                      catalogSyncFailed: widget.catalogSyncFailed,
                      isOffline: widget.isOffline,
                      isLocalWorkspace: widget.isLocalWorkspace,
                      onRetryCatalog: widget.onRetryCatalog,
                      onOpenProducts: widget.onOpenProducts,
                    ),
                  ),
                ),
              ),
              // Pay swaps the ticket for the payment panel in this same place.
              SizedBox(
                width: panelWidth,
                child: _panel == _Panel.ticket ? ticket : payment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
