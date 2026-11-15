import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/responsive/device_class.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/alive_feedback.dart';
import '../../../../core/widgets/skeleton_kit.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/linked_computer.dart';
import '../desktop/desktop_sub_page.dart';

/// The computers this account signed in from a phone, with a way to sign each
/// one out. Signing out takes effect at once: the computer is refused at its
/// next request and returns to sign-in.
class LinkedComputersScreen extends StatefulWidget {
  const LinkedComputersScreen({super.key});

  @override
  State<LinkedComputersScreen> createState() => _LinkedComputersScreenState();
}

class _LinkedComputersScreenState extends State<LinkedComputersScreen> {
  List<LinkedComputer>? _computers;
  bool _loading = true;
  bool _signingOutAll = false;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    if (!getIt<AuthService>().isLocalWorkspace) {
      _load();
    } else {
      _loading = false;
    }
  }

  /// Fetches the list. A failed refresh keeps what is already on screen.
  Future<void> _load() async {
    setState(() {
      _loading = _computers == null;
      _error = null;
    });
    try {
      final rows = await getIt<ApiClient>().getLinkedComputers();
      if (!mounted) return;
      setState(() => _computers = rows.map(LinkedComputer.fromJson).toList());
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut(LinkedComputer computer) async {
    final ok = await showConfirmDialog(
      context,
      title: computer.isThisDevice
          ? 'Sign out this computer?'
          : 'Sign out ${computer.name}?',
      message: computer.isThisDevice
          ? 'You are using this computer now. It will go back to the sign-in '
              'screen.'
          : 'It stops working with your account at once, even if it is '
              'switched off. To use it again, sign it in from this phone.',
      confirmLabel: 'Sign out',
      confirmColor: DesignColors.error,
    );
    if (!ok || !mounted) return;

    setState(() => _busy.add(computer.id));
    try {
      await getIt<ApiClient>().revokeLinkedComputer(computer.id);
      if (!mounted) return;
      setState(() {
        _computers = _computers?.where((c) => c.id != computer.id).toList();
      });
      Alive.done(context, '${computer.name} was signed out');
    } catch (e) {
      if (mounted) Alive.failed(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(computer.id));
    }
  }

  Future<void> _signOutAll() async {
    final count = _computers?.length ?? 0;
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out all computers?',
      message: count == 1
          ? 'The computer signed in with your account will be signed out.'
          : 'All $count computers signed in with your account will be signed '
              'out. Your phone stays signed in.',
      confirmLabel: 'Sign out all',
      confirmColor: DesignColors.error,
    );
    if (!ok || !mounted) return;

    setState(() => _signingOutAll = true);
    try {
      await getIt<ApiClient>().revokeAllLinkedComputers();
      if (!mounted) return;
      setState(() => _computers = const []);
      Alive.done(context,
          count == 1 ? 'The computer was signed out' : 'All computers were signed out');
    } catch (e) {
      if (mounted) Alive.failed(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _signingOutAll = false);
    }
  }

  void _openSignInAComputer() => context.push('/settings/desktop-approvals');

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    if (context.inDesktopShell) {
      return Scaffold(
        body: DesktopSubPage(
          title: 'Linked computers',
          subtitle: 'Computers that opened this shop with your account',
          maxWidth: 820,
          scroll: true,
          actions: [
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
            TextButton.icon(
              onPressed: _openSignInAComputer,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Sign in a computer'),
            ),
          ],
          child: _body(palette),
        ),
      );
    }
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        title: const Text('Linked computers'),
      ),
      body: SafeArea(
        child: TabletContent(
          maxWidth: 820,
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(DesignSpacing.lg),
              children: [_body(palette)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(SignInPalette palette) {
    final auth = getIt<AuthService>();
    if (auth.isLocalWorkspace) {
      return _Message(
        palette: palette,
        icon: Icons.phone_android_rounded,
        title: 'Kept on this phone only',
        body: 'This shop has no online account, so no computer can be signed '
            'in to it.',
      );
    }
    final computers = _computers;
    if (_loading && computers == null) {
      return const Column(
        children: [
          SkeletonRow(leading: true, height: 88),
          SkeletonRow(leading: true, height: 88),
        ],
      );
    }
    if (computers == null) {
      return _Message(
        palette: palette,
        icon: Icons.cloud_off_rounded,
        title: 'Could not load your computers',
        body: _error ?? 'Check your internet and try again.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (computers.isEmpty) {
      return _Message(
        palette: palette,
        icon: Icons.laptop_windows_rounded,
        title: 'No computers signed in',
        body: 'When you sign in a computer from this phone, it shows up here '
            'and you can sign it out any time.',
        actionLabel: 'Sign in a computer',
        onAction: _openSignInAComputer,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'These computers opened your shop with your account. Sign one out '
          'and it stops working at once.',
          style: TextStyle(color: palette.soft, height: 1.45),
        ),
        const SizedBox(height: DesignSpacing.md),
        if (_error != null) ...[
          _Banner(palette: palette, text: '$_error Showing the last list.'),
          const SizedBox(height: DesignSpacing.md),
        ],
        // One column on a phone, two once there is room (tablet, unfolded
        // foldable, computer window).
        LayoutBuilder(builder: (context, box) {
          const gap = DesignSpacing.md;
          final twoUp = box.maxWidth >= Breakpoints.twoColumn;
          final width = twoUp ? (box.maxWidth - gap) / 2 : box.maxWidth;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final computer in computers)
                SizedBox(
                  width: width,
                  child: _ComputerCard(
                    key: ValueKey(computer.id),
                    computer: computer,
                    palette: palette,
                    busy: _busy.contains(computer.id) || _signingOutAll,
                    onSignOut: () => _signOut(computer),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: DesignSpacing.lg),
        SignInOutlineButton(
          label: computers.length == 1
              ? 'Sign out this computer'
              : 'Sign out all computers',
          leading: const Icon(Icons.logout_rounded,
              color: DesignColors.error, size: 20),
          onPressed: _signingOutAll ? null : _signOutAll,
        ),
        const SizedBox(height: DesignSpacing.sm),
        TextButton(
          onPressed: _openSignInAComputer,
          child: const Text('Sign in another computer'),
        ),
      ],
    );
  }
}

class _ComputerCard extends StatelessWidget {
  const _ComputerCard({
    super.key,
    required this.computer,
    required this.palette,
    required this.busy,
    required this.onSignOut,
  });

  final LinkedComputer computer;
  final SignInPalette palette;
  final bool busy;
  final VoidCallback onSignOut;

  static IconData _icon(String? platform) => switch (platform) {
        'macos' => Icons.laptop_mac_rounded,
        'linux' => Icons.computer_rounded,
        _ => Icons.desktop_windows_rounded,
      };

  /// "Linked yesterday", "Linked 3 days ago", "Linked 12 Oct".
  static String _ago(DateTime when) {
    final text = timeAgo(when);
    return text == 'Yesterday' ? 'yesterday' : text;
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (computer.platformLabel != null) computer.platformLabel!,
      if (computer.place != null) computer.place!,
    ].join(' · ');
    final active = computer.activeNow();
    final seen = computer.lastActiveAt;
    final linked = computer.linkedAt;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A wrap, so on a narrow cover screen the chip drops under the name.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              computer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignType.display.copyWith(
                fontSize: 17,
                color: palette.ink,
              ),
            ),
            if (computer.isThisDevice)
              const _Chip(label: 'This computer', color: DesignColors.accent),
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(meta, style: TextStyle(color: palette.soft, fontSize: 13)),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? DesignColors.success : palette.faint,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                [
                  if (active)
                    'Active now'
                  else if (seen != null)
                    'Active ${_ago(seen)}',
                  if (linked != null) 'Linked ${_ago(linked)}',
                ].join(' · '),
                style: TextStyle(color: palette.faint, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );

    return Semantics(
      container: true,
      label: '${computer.name}, ${meta.isEmpty ? 'computer' : meta}',
      child: Container(
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DesignColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon(computer.platform),
                      color: DesignColors.accent, size: 24),
                ),
                const SizedBox(width: DesignSpacing.md),
                Expanded(child: details),
              ],
            ),
            const SizedBox(height: DesignSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: DesignColors.error,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: busy ? null : onSignOut,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded, size: 18),
                label: Text(busy ? 'Signing out' : 'Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: SignInPalette.of(context).ink,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.palette, required this.text});

  final SignInPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: DesignColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          border:
              Border.all(color: DesignColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: DesignColors.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: palette.ink, height: 1.4)),
            ),
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.palette,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final SignInPalette palette;
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xl),
        child: Column(
          children: [
            Icon(icon, color: palette.faint, size: 52),
            const SizedBox(height: DesignSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DesignType.display
                  .copyWith(fontSize: 20, color: palette.ink),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.soft, height: 1.45),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: DesignSpacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: SignInButton(label: actionLabel!, onPressed: onAction),
              ),
            ],
          ],
        ),
      );
}
