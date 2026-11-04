import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/widgets/workspace_image.dart';

/// Colours for the sign-in screens, taken from the app theme so light and
/// dark both follow the same tokens as the rest of the app.
class SignInPalette {
  SignInPalette._(this.isDark)
      : page = isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        card = isDark ? DesignColors.darkSurface : Colors.white,
        field = isDark
            ? DesignColors.darkSurfaceElevated
            : DesignColors.surfaceSubtle,
        line = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ink = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
        soft = isDark
            ? DesignColors.darkTextSecondary
            : DesignColors.textSecondary,
        faint = isDark
            ? DesignColors.darkTextTertiary
            : DesignColors.textTertiary;

  factory SignInPalette.of(BuildContext context) =>
      SignInPalette._(Theme.of(context).brightness == Brightness.dark);

  final bool isDark;
  final Color page;
  final Color card;
  final Color field;
  final Color line;
  final Color ink;
  final Color soft;
  final Color faint;

  /// Text on the orange button. The accent is bright, so dark text keeps the
  /// contrast above 4.5:1 in both themes.
  static const Color onAccent = DesignColors.textPrimary;
}

/// "mama-njeri" becomes "Mama Njeri". Names typed by the owner are kept as
/// they are; only a bare company code is turned into words.
String businessNameFrom({String? name, String? code}) {
  final typed = name?.trim() ?? '';
  if (typed.isNotEmpty) return typed;
  final slug = code?.trim() ?? '';
  if (slug.isEmpty) return '';
  return slug
      .split(RegExp(r'[-_\s]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

String initialsFor(String name) {
  final parts = name
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((part) => part.characters.first.toUpperCase()).join();
}

/// "stock_keeper" becomes "Stock keeper".
String roleLabel(String? role) {
  final text = (role ?? '').replaceAll('_', ' ').trim();
  if (text.isEmpty) return '';
  return text[0].toUpperCase() + text.substring(1).toLowerCase();
}

/// Round business mark: the logo when there is one, otherwise initials.
class BusinessMark extends StatelessWidget {
  const BusinessMark({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 56,
    this.loading = false,
  });

  final String name;
  final String? logoUrl;
  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      color: DesignColors.accentSubtle,
      alignment: Alignment.center,
      child: name.trim().isEmpty
          ? Icon(Icons.storefront_rounded,
              color: DesignColors.accent, size: size * 0.5)
          : Text(
        initialsFor(name),
        style: DesignType.display.copyWith(
          color: DesignColors.accent,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final url = logoUrl;
    return Semantics(
      image: true,
      label: name.isEmpty ? 'Business logo' : '$name logo',
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : url != null && url.isNotEmpty
                  ? WorkspaceImage(
                      source: url,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      placeholder: initials,
                    )
                  : initials,
        ),
      ),
    );
  }
}

/// Terms and privacy agreement shown wherever someone signs in. Both links
/// open the current documents under /legal.
class LegalConsent extends StatelessWidget {
  const LegalConsent({super.key, required this.palette, this.action = 'continuing'});

  final SignInPalette palette;

  /// What the person is doing, for the sentence "By {action} you accept…".
  final String action;

  @override
  Widget build(BuildContext context) {
    final link = TextStyle(
      color: palette.ink,
      decoration: TextDecoration.underline,
      decorationColor: palette.soft,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'By $action you accept the',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.soft, fontSize: 12, height: 1.4),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: () => context.push('/legal/terms'),
              child: Text('Terms of Service', style: link),
            ),
            Text('and', style: TextStyle(color: palette.soft, fontSize: 12)),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: () => context.push('/legal/privacy'),
              child: Text('Privacy Notice', style: link),
            ),
          ],
        ),
      ],
    );
  }
}

/// The one orange action on a sign-in screen.
class SignInButton extends StatelessWidget {
  const SignInButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final palette = SignInPalette.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? DesignColors.accent : palette.field,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          onTap: enabled ? onPressed : null,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: SignInPalette.onAccent,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: enabled ? SignInPalette.onAccent : palette.faint,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary action (for example "Continue with Google").
class SignInOutlineButton extends StatelessWidget {
  const SignInOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          side: BorderSide(color: palette.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain text link with a 48 dp touch target.
class SignInTextLink extends StatelessWidget {
  const SignInTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: onPressed,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color ?? palette.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: palette.faint,
        ),
      ),
    );
  }
}

/// Inline error shown above the action it belongs to.
class SignInError extends StatelessWidget {
  const SignInError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Error: $message',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: DesignColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          border: Border.all(color: DesignColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: DesignColors.error, size: 20),
            const SizedBox(width: DesignSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: DesignColors.error,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Number keypad with large keys. The left key clears the whole entry and
/// the right key deletes one digit.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onClear,
    required this.onBackspace,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    Widget key(String digit) => _Key(
          semantics: 'PIN digit $digit',
          onTap: enabled ? () => onDigit(digit) : null,
          fill: palette.card,
          border: palette.line,
          child: Text(
            digit,
            style: DesignType.numeric(fontSize: 24, color: palette.ink),
          ),
        );
    Widget row(List<String> digits) => Row(
          children: [
            for (var i = 0; i < digits.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: key(digits[i])),
            ],
          ],
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(['1', '2', '3']),
        const SizedBox(height: 10),
        row(['4', '5', '6']),
        const SizedBox(height: 10),
        row(['7', '8', '9']),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Key(
                semantics: 'Clear PIN',
                onTap: enabled ? onClear : null,
                fill: Colors.transparent,
                border: Colors.transparent,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: palette.soft,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: key('0')),
            const SizedBox(width: 10),
            Expanded(
              child: _Key(
                semantics: 'Delete digit',
                onTap: enabled ? onBackspace : null,
                fill: Colors.transparent,
                border: Colors.transparent,
                child: Icon(Icons.backspace_outlined,
                    color: palette.soft, size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.semantics,
    required this.onTap,
    required this.fill,
    required this.border,
    required this.child,
  });

  final String semantics;
  final VoidCallback? onTap;
  final Color fill;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
          onTap: onTap,
          child: Container(
            height: 58,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Row of PIN slots: filled slots are orange, the next one is outlined.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, required this.filled, this.error = false});

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      label: '$filled of $length digits entered',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: AnimatedContainer(
                duration: DesignAnimation.fastest,
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled
                      ? (error ? DesignColors.error : DesignColors.accent)
                      : Colors.transparent,
                  border: Border.all(
                    color: i < filled
                        ? (error ? DesignColors.error : DesignColors.accent)
                        : i == filled
                            ? palette.ink
                            : palette.faint,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
