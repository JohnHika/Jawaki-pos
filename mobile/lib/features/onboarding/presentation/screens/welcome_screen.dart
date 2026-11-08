import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/providers/local_workspace_capabilities.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/welcome_pages.dart';

/// A few pages that explain the app to someone using it for the first time.
/// Shown once per person; the shop's database notes who has seen it. The
/// owner moves on to the setup checklist, everyone else to their work.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pager = PageController();
  int _page = 0;
  bool _closing = false;

  bool get _isOwner => getIt<AuthService>().isLocalWorkspaceOwner;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _close({required bool toSetup}) async {
    if (_closing) return;
    _closing = true;
    final userId = getIt<AuthService>().currentUser?['id']?.toString() ?? '';
    try {
      await getIt<AppDatabase>().noteWelcomeSeen(userId);
    } catch (_) {
      // Seeing the tour again next time is better than being stuck here.
    }
    if (!mounted) return;
    if (toSetup) {
      context.pushReplacement('/setup');
    } else if (context.canPop()) {
      context.pop();
    } else {
      final permissions = ref.read(permissionsProvider);
      final layout = ref.read(businessLayoutProvider);
      context.go(LocalWorkspaceCapabilities.homePathFor(permissions, layout));
    }
  }

  void _next(int pageCount) {
    if (_page >= pageCount - 1) {
      _close(toSetup: _isOwner);
      return;
    }
    if (reducedMotion(context)) {
      _pager.jumpToPage(_page + 1);
    } else {
      _pager.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final identity = ref.watch(tenantIdentityProvider);
    final pages = welcomePagesFor(
      shopName: identity.companyName,
      firstName: identity.userFirstName,
      permissions: ref.watch(permissionsProvider),
      isOwner: _isOwner,
    );
    final last = _page >= pages.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(toSetup: false);
      },
      child: Scaffold(
        backgroundColor: palette.page,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    BusinessMark(
                      name: identity.companyName,
                      logoUrl: identity.logoUrl,
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        identity.companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: palette.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!last)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(64, 48),
                          foregroundColor: palette.soft,
                        ),
                        onPressed: () => _close(toSetup: false),
                        child: const Text('Skip'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: pages.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) =>
                      _WelcomePageView(page: pages[index]),
                ),
              ),
              _PageDots(count: pages.length, current: _page),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: SignInButton(
                  label: !last
                      ? 'Next'
                      : _isOwner
                          ? 'Set up my shop'
                          : 'Start working',
                  onPressed: () => _next(pages.length),
                ),
              ),
              SizedBox(
                height: 52,
                child: last && _isOwner
                    ? Center(
                        child: SignInTextLink(
                          label: 'I will set up later',
                          onPressed: () => _close(toSetup: false),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePageView extends StatelessWidget {
  const _WelcomePageView({required this.page});

  final WelcomePage page;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: DesignColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(page.icon, color: DesignColors.accentDark, size: 32),
          ),
          const SizedBox(height: 28),
          Semantics(
            header: true,
            child: Text(
              page.title,
              style: DesignType.display.copyWith(
                color: palette.ink,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            style: TextStyle(color: palette.soft, fontSize: 16, height: 1.5),
          ),
          if (page.points.isNotEmpty) ...[
            const SizedBox(height: 28),
            for (var i = 0; i < page.points.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.line),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                            color: palette.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          page.points[i],
                          style: TextStyle(
                              color: palette.ink, fontSize: 15.5, height: 1.45),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: reducedMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == current ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == current ? DesignColors.accent : palette.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
