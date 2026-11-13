import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/httpsms_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';

class HttpsmsSettingsScreen extends StatefulWidget {
  const HttpsmsSettingsScreen({super.key});

  @override
  State<HttpsmsSettingsScreen> createState() => _HttpsmsSettingsScreenState();
}

class _HttpsmsSettingsScreenState extends State<HttpsmsSettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _senderController = TextEditingController();
  bool _hasApiKey = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscureKey = true;
  String? _error;

  StorageService get _storage => getIt<StorageService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _senderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final key = await _storage.getHttpsmsApiKey();
      final sender = await _storage.getHttpsmsSenderNumber();
      if (mounted) {
        setState(() {
          _hasApiKey = key != null;
          _senderController.text = sender ?? '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Secure storage is unavailable on this device.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final apiKey = _apiKeyController.text.trim();
    final sender = _senderController.text.trim();
    if (!_hasApiKey && apiKey.isEmpty) {
      setState(() => _error = 'Enter the HTTPSMS account API key.');
      return;
    }
    if (sender.isEmpty) {
      setState(() => _error = 'Enter the registered HTTPSMS sender number.');
      return;
    }

    late final String normalizedSender;
    try {
      normalizedSender = HttpsmsService.normalizePhoneNumber(sender);
    } on HttpsmsException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (apiKey.isNotEmpty) await _storage.saveHttpsmsApiKey(apiKey);
      await _storage.saveHttpsmsSenderNumber(normalizedSender);
      _apiKeyController.clear();
      if (mounted) {
        setState(() {
          _hasApiKey = true;
          _senderController.text = normalizedSender;
        });
        showGlassSnackBar(
          context,
          'HTTPSMS connection saved securely on this device.',
          icon: Icons.lock_outline_rounded,
          color: DesignColors.success,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save HTTPSMS settings securely.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove HTTPSMS connection?'),
        content: const Text(
          'Counterbase will forget the account API key and sender number stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep connection'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove connection'),
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
      await _storage.clearHttpsmsCredentials();
      if (mounted) {
        setState(() {
          _hasApiKey = false;
          _senderController.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not remove the saved connection.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openDocs() async {
    final uri = Uri.parse('https://docs.httpsms.com/');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      showGlassSnackBar(
        context,
        'Could not open the HTTPSMS setup guide.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  Widget _instructions(BuildContext context) {
    const message =
        'HTTPSMS queues messages for an Android phone paired to your account. '
        'That phone sends them through its SIM; it must be online and your carrier may charge for each SMS segment.';
    if (context.inDesktopShell) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.desktop.panelAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.desktop.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.sms_outlined, color: context.desktop.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openDocs,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('HTTPSMS setup guide'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.sms_outlined, color: DesignColors.accent),
            const SizedBox(height: 8),
            const Text(message),
            TextButton.icon(
              onPressed: _openDocs,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('HTTPSMS setup guide'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionForm(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _hasApiKey
              ? 'Account API key is stored securely. Leave the key field blank to keep it.'
              : 'Use the account API key from HTTPSMS settings. Do not use the separate phone API key from the Android app.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('httpsms-account-api-key'),
          controller: _apiKeyController,
          obscureText: _obscureKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText:
                _hasApiKey ? 'Replace account API key' : 'Account API key',
            suffixIcon: IconButton(
              tooltip: _obscureKey ? 'Show key' : 'Hide key',
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
              icon: Icon(
                _obscureKey
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('httpsms-sender-number'),
          controller: _senderController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[+0-9 ()-]'))
          ],
          decoration: const InputDecoration(
            labelText: 'Registered sender number',
            hintText: '+2547…',
            helperText: 'Use the number registered to your HTTPSMS account.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const ValueKey('httpsms-settings-error'),
            style: const TextStyle(color: DesignColors.error),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('httpsms-save'),
              onPressed: _loading || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_outline_rounded, size: 17),
              label: Text(_saving ? 'Saving…' : 'Save securely'),
            ),
            if (_hasApiKey)
              TextButton.icon(
                key: const ValueKey('httpsms-remove'),
                onPressed: _loading || _saving ? null : _remove,
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                label: const Text('Remove connection'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'The account key is stored in this device’s secure credential store, not in Counterbase’s database or backup. When you send, the customer number and statement text go to HTTPSMS and your mobile carrier; HTTPSMS end-to-end encryption is off for Counterbase sends. Carrier rates vary and Counterbase cannot estimate the charge. Counterbase supports manual statement sends only; it does not send login codes, bulk messages or process customer replies. Check for SMS opt-outs before each send.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );

    if (context.inDesktopShell) {
      return DesktopPanel(
        title: 'Connection details',
        subtitle: 'Configure the HTTPSMS account and registered sender',
        child: content,
      );
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = context.inDesktopShell;
    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _instructions(context),
        const SizedBox(height: 12),
        _connectionForm(context),
      ],
    );

    return Scaffold(
      appBar: desktop ? null : const BrandedAppBar(title: 'HTTPSMS'),
      body: desktop
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DesktopPageHeader(
                  title: 'HTTPSMS messaging',
                  subtitle:
                      'Send a customer statement through your paired phone',
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 12),
                ),
                Divider(height: 1, color: context.desktop.border),
                Expanded(
                  child: DesktopContent(
                    maxWidth: 820,
                    child: body,
                  ),
                ),
              ],
            )
          : SafeArea(top: false, child: body),
    );
  }
}
