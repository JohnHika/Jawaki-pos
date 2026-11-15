import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// Checks the "how many" box of a stock request. Shared by the phone form's
/// wording so both say the same thing.
String? validateRequestQuantity(String? value) {
  if (value == null || value.trim().isEmpty) return 'Enter how many you need';
  final qty = double.tryParse(value.trim());
  if (qty == null) return 'Numbers only';
  if (qty <= 0) return 'Must be more than 0';
  return null;
}

/// One urgency choice.
class DesktopRequestPriority {
  const DesktopRequestPriority(this.value, this.label);
  final String value;
  final String label;
}

/// A photo already added to the request.
class DesktopRequestPhoto {
  const DesktopRequestPhoto({required this.id, required this.thumbnail});

  /// What [DesktopStockRequestForm.onRemovePhoto] is called with.
  final String id;
  final Widget thumbnail;
}

/// The "Request stock" page on a computer: one centred form column with the
/// product, how many, how urgent, why and photos, and a clear Send button in
/// the header. Enter in the quantity box or Ctrl+Enter sends, Esc goes back.
///
/// Plain data in, callbacks out. The routed screen owns the controllers and
/// does the sending.
class DesktopStockRequestForm extends StatelessWidget {
  const DesktopStockRequestForm({
    super.key,
    required this.formKey,
    required this.quantity,
    required this.reason,
    required this.unit,
    required this.priority,
    required this.priorities,
    required this.quickReasons,
    required this.photos,
    required this.onPickProduct,
    required this.onPriority,
    required this.onReason,
    required this.onChanged,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onSubmit,
    required this.onCancel,
    this.productName,
    this.onHand,
    this.onHandIsEmpty = false,
    this.summary,
    this.busy = false,
    this.sentMessage,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController quantity;
  final TextEditingController reason;
  final String unit;
  final String priority;
  final List<DesktopRequestPriority> priorities;
  final List<String> quickReasons;
  final List<DesktopRequestPhoto> photos;

  /// Null until a product is chosen.
  final String? productName;

  /// "You have 6 pieces now", when known.
  final String? onHand;
  final bool onHandIsEmpty;

  /// "Requesting 24 pieces of Milk".
  final String? summary;
  final bool busy;

  /// Set once the request is sent: replaces the form with a confirmation.
  final String? sentMessage;

  final VoidCallback onPickProduct;
  final ValueChanged<String> onPriority;
  final ValueChanged<String> onReason;
  final VoidCallback onChanged;
  final VoidCallback onAddPhoto;
  final ValueChanged<String> onRemovePhoto;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final sent = sentMessage != null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
        if (!sent && !busy)
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              onSubmit,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Request stock',
              subtitle: 'Ask a manager to bring more of an item to this shop.',
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              leading: IconButton(
                tooltip: 'Back (Esc)',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: onCancel,
              ),
              actions: sent
                  ? const []
                  : [
                      OutlinedButton(
                        style: desktopSecondaryButton(context),
                        onPressed: busy ? null : onCancel,
                        child: const Text('Cancel'),
                      ),
                      Tooltip(
                        message: 'Send request (Ctrl+Enter)',
                        child: FilledButton.icon(
                          key: const ValueKey('send-request'),
                          style: desktopPrimaryButton(context),
                          onPressed: busy ? null : onSubmit,
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 17),
                          label: Text(busy ? 'Sending…' : 'Send request'),
                        ),
                      ),
                    ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: sent
                  ? DesktopEmptyState(
                      icon: Icons.check_circle_rounded,
                      title: 'Request sent',
                      message: sentMessage,
                    )
                  : SingleChildScrollView(
                      child: DesktopContent(
                        maxWidth: 760 + 48,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                        child: _form(context),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text, {String? trailing}) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing,
              style: GoogleFonts.plusJakartaSans(
                color: p.textFaint,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final p = context.desktop;
    final hasProduct = productName != null;
    final reasonText = reason.text.trim();
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, 'Product'),
          Material(
            color: p.dark ? p.panelAlt : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
              side: BorderSide(
                color: hasProduct ? p.borderStrong : p.border,
              ),
            ),
            child: InkWell(
              key: const ValueKey('pick-product'),
              borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
              hoverColor: p.hover,
              onTap: onPickProduct,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      hasProduct
                          ? Icons.inventory_2_outlined
                          : Icons.search_rounded,
                      size: 20,
                      color: p.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productName ?? 'Choose a product',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: hasProduct ? p.text : p.textMuted,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            !hasProduct
                                ? 'Search your products'
                                : (onHand ?? 'Click to change'),
                            style: GoogleFonts.plusJakartaSans(
                              color: hasProduct && onHandIsEmpty
                                  ? DesignColors.error
                                  : p.textFaint,
                              fontSize: 12.5,
                              fontWeight: onHandIsEmpty
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      hasProduct ? 'Change' : 'Choose',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _label(context, 'How many do you need?'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: TextFormField(
                  key: const ValueKey('request-quantity'),
                  controller: quantity,
                  textAlign: TextAlign.right,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: DesignType.numeric(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. 24',
                    suffixText: unit,
                  ),
                  validator: validateRequestQuantity,
                  onChanged: (_) => onChanged(),
                  onFieldSubmitted: (_) {
                    if (!busy) onSubmit();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final n in const [5, 10, 20, 50])
                      DesktopFilterChip(
                        label: '+$n',
                        selected: false,
                        onTap: () {
                          final current =
                              double.tryParse(quantity.text.trim()) ?? 0;
                          final next = current + n;
                          quantity.text = next == next.roundToDouble()
                              ? next.toInt().toString()
                              : next.toString();
                          onChanged();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _label(context, 'How urgent is it?'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in priorities)
                DesktopFilterChip(
                  key: ValueKey('priority-${option.value}'),
                  label: option.label,
                  selected: priority == option.value,
                  onTap: () => onPriority(option.value),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _label(context, 'Why do you need it?', trailing: 'optional'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in quickReasons)
                DesktopFilterChip(
                  label: r,
                  selected: reasonText == r,
                  onTap: () => onReason(r),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: reason,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              hintText: 'A note for the manager (Ctrl+Enter sends)',
            ),
          ),
          const SizedBox(height: 24),
          _label(
            context,
            'Photos',
            trailing: 'optional, ${photos.length} added',
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final photo in photos)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        border: Border.all(color: p.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: photo.thumbnail,
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton(
                        tooltip: 'Remove photo',
                        visualDensity: VisualDensity.compact,
                        iconSize: 14,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: p.dark ? p.panelAlt : Colors.white,
                          side: BorderSide(color: p.borderStrong),
                        ),
                        icon: Icon(Icons.close_rounded, color: p.text),
                        onPressed: () => onRemovePhoto(photo.id),
                      ),
                    ),
                  ],
                ),
              OutlinedButton.icon(
                key: const ValueKey('add-photo'),
                style: desktopSecondaryButton(context),
                onPressed: onAddPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Add photo'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A photo of the empty shelf helps the manager decide faster.',
            style: GoogleFonts.plusJakartaSans(
              color: p.textFaint,
              fontSize: 12,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 24),
            Divider(height: 1, color: p.border),
            const SizedBox(height: 14),
            Text(
              summary!,
              key: const ValueKey('request-summary'),
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
