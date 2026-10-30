import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';

class AxonGatewaySettingsScreen extends StatefulWidget {
  const AxonGatewaySettingsScreen({super.key});

  @override
  State<AxonGatewaySettingsScreen> createState() =>
      _AxonGatewaySettingsScreenState();
}

class _AxonGatewaySettingsScreenState extends State<AxonGatewaySettingsScreen> {
  final _keyController = TextEditingController();
  bool _hasKey = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscureKey = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final hasKey = await getIt<StorageService>().hasAxonGatewayApiKey();
      if (mounted) setState(() => _hasKey = hasKey);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Secure storage is unavailable on this device.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter the key issued for this install.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await getIt<StorageService>().saveAxonGatewayApiKey(key);
      _keyController.clear();
      if (mounted) {
        setState(() => _hasKey = true);
        showGlassSnackBar(
          context,
          'Axon Gateway key stored securely on this device.',
          icon: Icons.lock_outline_rounded,
          color: DesignColors.success,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the key to secure storage.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this Gateway key?'),
        content: const Text(
          'Axon Gateway features will remain unavailable on this device until a key is added again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep key'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove key'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await getIt<StorageService>().clearAxonGatewayApiKey();
      if (mounted) setState(() => _hasKey = false);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove the saved key.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Scaffold(
      appBar: const BrandedAppBar(title: 'Axon AI Gateway'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(DesignSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(DesignSpacing.lg),
              decoration: BoxDecoration(
                color: isDark ? DesignColors.darkSurface : DesignColors.surface,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
                border: Border.all(
                  color: isDark
                      ? DesignColors.darkBorder
                      : DesignColors.surfaceBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: DesignColors.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.hub_rounded,
                          color: DesignColors.accent,
                        ),
                      ),
                      const SizedBox(width: DesignSpacing.md),
                      Expanded(
                        child: Text(
                          _loading
                              ? 'Checking secure storage…'
                              : _hasKey
                                  ? 'Key saved on this device'
                                  : 'Gateway key not set',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (!_loading)
                        Icon(
                          _hasKey
                              ? Icons.verified_rounded
                              : Icons.key_off_rounded,
                          color: _hasKey
                              ? DesignColors.success
                              : DesignColors.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  Text(
                    'Axon AI uses gateway.archeaxon.com. The key is saved in this device’s secure credential store and is never written to the shop database or preferences.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: secondary, height: 1.45),
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  Text(
                    'AI requests go only to gateway.archeaxon.com. Each chat request can include your new message and up to 24 recent messages from this conversation. If needed, the app can also send a selected read-only result: today’s totals, low-stock products, top products, or matching product details. Dashboard and date-summary briefs send aggregate sales totals, the top product names and totals, and low/out-of-stock counts for the selected date. Images you choose for analysis are sent to the Gateway. Automatic lookups do not include customer records, and Axon AI cannot change shop data. Avoid including customer personal information in chat.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: secondary, height: 1.4),
                  ),
                  const SizedBox(height: DesignSpacing.xl),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscureKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: _hasKey ? 'Replace saved key' : 'Gateway key',
                      hintText: 'Paste the key issued for this install',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscureKey ? 'Show key' : 'Hide key',
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(_obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: DesignSpacing.sm),
                    Text(
                      _error!,
                      style: const TextStyle(color: DesignColors.error),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    height: DesignSpacing.huge,
                    child: FilledButton.icon(
                      onPressed: _saving || _loading ? null : _saveKey,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_outline_rounded),
                      label: Text(_saving ? 'Saving…' : 'Save key securely'),
                    ),
                  ),
                  if (_hasKey) ...[
                    const SizedBox(height: DesignSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _saving ? null : _removeKey,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Remove saved key'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
