import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/workspace_image.dart';

/// The AI assistant's icon — the Axon hex mark with the tenant's own
/// company logo merged on as a small badge, bottom-right, overlapping the
/// hex edge. Mirrors the same "~3/4 Axon, ~1/4 company badge" composition
/// used for the app's launcher icon (see
/// assets/images/axon_app_icon_master.svg) so the AI icon and the home
/// screen app icon read as the same design language, instead of the
/// generic Material sparkle (Icons.auto_awesome) previously used.
///
/// Falls back to the plain Axon mark (no badge) when the tenant hasn't
/// uploaded a logo yet, so it never shows a broken/empty badge.
class AxonAiIcon extends StatelessWidget {
  final String? tenantLogoUrl;
  final double size;
  final Color? badgeColor;

  /// A small "AI" tag on the mark, so it reads as the assistant and not as the
  /// app's own logo.
  final bool showAiTag;

  const AxonAiIcon({
    super.key,
    this.tenantLogoUrl,
    this.size = 40,
    this.badgeColor,
    this.showAiTag = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // One merged mark (Counterbase cube with the Arche Axon network) works on
    // both light and dark surfaces.
    const asset = 'assets/images/counterbase_axon_mark.svg';
    final logoUrl = tenantLogoUrl?.trim();
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

    final badgeSize = size * 0.42;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SvgPicture.asset(
            asset,
            width: size,
            height: size,
            semanticsLabel: 'Axon AI',
          ),
          if (showAiTag)
            Positioned(
              top: -size * 0.12,
              right: -size * 0.22,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: size * 0.14, vertical: size * 0.03),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF7A33),
                  borderRadius: BorderRadius.circular(size),
                  border: Border.all(
                    color: isDark ? const Color(0xFF0B0A0F) : Colors.white,
                    width: size * 0.04,
                  ),
                ),
                child: Text(
                  'AI',
                  style: TextStyle(
                    fontSize: size * 0.3,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1C1917),
                  ),
                ),
              ),
            ),
          if (hasLogo)
            Positioned(
              right: -badgeSize * 0.12,
              bottom: -badgeSize * 0.12,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                padding: EdgeInsets.all(badgeSize * 0.12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeColor ?? const Color(0xFFFF7A33),
                  border: Border.all(
                    color: isDark ? const Color(0xFF0B0A0F) : Colors.white,
                    width: badgeSize * 0.1,
                  ),
                ),
                child: ClipOval(
                  child: WorkspaceImage(
                    source: logoUrl,
                    fit: BoxFit.cover,
                    placeholder: const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
