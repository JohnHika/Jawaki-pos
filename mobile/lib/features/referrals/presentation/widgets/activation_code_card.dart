import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';

/// "Have a referral or promo code?" on the activation screen. A code from a
/// shop that told you about Counterbase gives extra free days once you
/// activate; a promo code does the same. Entering one is optional.
class ActivationCodeCard extends StatefulWidget {
  const ActivationCodeCard({super.key});

  @override
  State<ActivationCodeCard> createState() => _ActivationCodeCardState();
}

class _ActivationCodeCardState extends State<ActivationCodeCard> {
  final _code = TextEditingController();
  bool _open = false;
  bool _busy = false;
  bool _accepted = false;
  String? _message;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await getIt<ApiClient>().redeemCode(code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _accepted = true;
        _message = '${result['message'] ?? 'Code accepted.'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) {
      return Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: DesignColors.success, size: 20),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(_message ?? 'Code accepted.',
                style: const TextStyle(
                    color: DesignColors.success, fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _open = true),
          icon: const Icon(Icons.redeem_rounded, size: 18),
          label: const Text('Have a referral or promo code?'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (_) => _apply(),
          decoration: kitFieldDecoration(context,
              label: 'Referral or promo code',
              hint: 'e.g. KAMA-7H2Q',
              prefixIcon: Icons.redeem_rounded),
        ),
        if (_message != null) ...[
          const SizedBox(height: DesignSpacing.sm),
          Text(_message!,
              style: const TextStyle(
                  color: DesignColors.error, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: DesignSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : _apply,
            child: Text(_busy ? 'Checking...' : 'Apply code'),
          ),
        ),
      ],
    );
  }
}
