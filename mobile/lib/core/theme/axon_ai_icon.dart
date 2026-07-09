import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  const AxonAiIcon({
    super.key,
    this.tenantLogoUrl,
    this.size = 40,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/images/axon_logo_mark.svg'
        : 'assets/images/axon_logo_mark_light.svg';
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
                  child: Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
