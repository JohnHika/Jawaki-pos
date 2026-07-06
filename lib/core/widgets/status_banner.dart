import 'package:flutter/material.dart';
import '../../core/theme.dart';

class StatusBanner extends StatelessWidget {
  final String status; // 'active', 'trial', 'expired', 'free_trial'
  final int daysRemaining;
  final VoidCallback? onTap;

  const StatusBanner({
    super.key,
    required this.status,
    required this.daysRemaining,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _bannerColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              _bannerIcon,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _bannerText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (status == 'expired')
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tap to Renew',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color get _bannerColor {
    switch (status) {
      case 'active':
        return JawakiTheme.accentGreen;
      case 'trial':
        return JawakiTheme.accentOrange;
      case 'expired':
        return JawakiTheme.accentRed;
      case 'free_trial':
        return JawakiTheme.primaryDeepBlue;
      default:
        return JawakiTheme.accentOrange;
    }
  }

  IconData get _bannerIcon {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'trial':
        return Icons.access_time;
      case 'expired':
        return Icons.warning_amber_rounded;
      case 'free_trial':
        return Icons.card_giftcard;
      default:
        return Icons.info;
    }
  }

  String get _bannerText {
    switch (status) {
      case 'active':
        return 'AI Active — $daysRemaining days left';
      case 'trial':
        return 'Trial — $daysRemaining days left';
      case 'expired':
        return 'Expired — Renew Now';
      case 'free_trial':
        return 'Free Trial Active — $daysRemaining days';
      default:
        return 'AI Status Unknown';
    }
  }
}
