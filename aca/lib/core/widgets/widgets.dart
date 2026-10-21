import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../state/session.dart';
import '../format.dart';
import '../theme.dart';

// ------------------------------------------------------------------ surfaces

/// Rounded, bordered surface. The basic building block of every screen.
class AcaCard extends StatelessWidget {
  const AcaCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.tone});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Optional accent: tints the border (e.g. a danger card).
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final radius = BorderRadius.circular(16);
    return Material(
      color: p.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: tone == null ? p.border : p.toneColor(tone!).withValues(alpha: 0.55)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.textMuted),
            ),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Number-first tile for dashboards.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone = Tone.neutral,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final color = tone == Tone.neutral ? p.text : p.toneColor(tone);
    return AcaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: p.textMuted), const SizedBox(width: 6)],
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.textMuted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.textMuted)),
          ],
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.tone = Tone.neutral, this.icon, this.dense = false});

  final String text;
  final Tone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final color = p.toneColor(tone);
    return LayoutBuilder(builder: (context, c) {
      final label = Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700, color: color),
      );
      return Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
        decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
            // Only shrink the text when the parent actually bounds our width.
            if (c.hasBoundedWidth) Flexible(child: label) else label,
          ],
        ),
      );
    });
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, this.tone});

  final String? name;
  final double size;
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final color = p.toneColor(tone ?? Tone.brand);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
      child: Text(Fmt.initials(name),
          style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// Label on the left, value on the right; used in detail cards.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.valueWidget, this.onCopy});

  final String label;
  final String? value;
  final Widget? valueWidget;

  /// When set, long-pressing the value copies it.
  final String? onCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final v = valueWidget ??
        Text(value ?? '—',
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.w600, color: p.text));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: p.textMuted))),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: onCopy == null
                  ? v
                  : GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: onCopy!));
                        toast(context, 'Copied');
                      },
                      child: v,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- states

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.surfaceHigh, shape: BoxShape.circle),
              child: Icon(icon, color: p.textMuted, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, height: 1.4)),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
                child: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final api = error is ApiException ? error as ApiException : null;
    final forbidden = api?.isForbidden ?? false;
    final offline = api?.isNetwork ?? false;
    return EmptyState(
      icon: forbidden
          ? Icons.lock_outline_rounded
          : offline
              ? Icons.cloud_off_rounded
              : Icons.error_outline_rounded,
      title: forbidden
          ? 'Not allowed for your role'
          : offline
              ? 'Can\'t reach Counterbase'
              : 'Couldn\'t load this',
      message: api?.message ?? error.toString(),
      action: onRetry == null || forbidden ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

/// Pulsing placeholder block shown while the first load is in flight.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 8});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(p.surfaceHigh, p.border, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Generic list skeleton: [rows] card-shaped placeholders.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 6, this.rowHeight = 76});
  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Skeleton(height: rowHeight, radius: 16),
      );
}

// ------------------------------------------------------------ async plumbing

/// Loads data once, shows skeleton → data/error, supports pull-to-refresh and
/// keeps showing stale data (with a snackbar) if a refresh fails.
///
///     LoadBuilder<List<Foo>>(
///       load: () => repo.foos(),
///       builder: (context, data, reload) => ListView(...),   // must be scrollable
///     )
class LoadBuilder<T> extends StatefulWidget {
  const LoadBuilder({
    super.key,
    required this.load,
    required this.builder,
    this.skeleton,
    this.emptyWhen,
    this.empty,
  });

  final Future<T> Function() load;

  /// Build the loaded UI. Return a scrollable (ListView/CustomScrollView) so
  /// pull-to-refresh works. Call `reload()` after a mutation.
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Widget? skeleton;

  /// Optional: show [empty] instead of the builder when this returns true.
  final bool Function(T data)? emptyWhen;
  final Widget? empty;

  @override
  State<LoadBuilder<T>> createState() => LoadBuilderState<T>();
}

class LoadBuilderState<T> extends State<LoadBuilder<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_data != null) toast(context, e is ApiException ? e.message : 'Refresh failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null && _loading) return widget.skeleton ?? const ListSkeleton();
    if (_data == null && _error != null) return ErrorState(error: _error!, onRetry: reload);
    final d = _data as T;
    if (widget.emptyWhen != null && widget.empty != null && widget.emptyWhen!(d)) {
      return RefreshIndicator(
        onRefresh: reload,
        child: LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(height: c.maxHeight, child: widget.empty),
          ),
        ),
      );
    }
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, d, reload));
  }
}

// --------------------------------------------------------------- interaction

OverlayEntry? _toastEntry;

/// Brief message pinned to the top of the screen. It lives in the ROOT overlay, so
/// unlike a SnackBar it stays visible above bottom sheets, dialogs and the keyboard.
/// Dismissal is driven by an animation controller (not a Timer) so it dies with the
/// widget tree instead of leaking.
void toast(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final palette = context.aca;

  if (_toastEntry?.mounted ?? false) _toastEntry!.remove();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _ToastView(
      message: message,
      error: error,
      palette: palette,
      top: MediaQuery.of(ctx).padding.top + 12,
      onDone: () {
        if (entry.mounted) entry.remove();
        if (_toastEntry == entry) _toastEntry = null;
      },
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.error,
    required this.palette,
    required this.top,
    required this.onDone,
  });

  final String message;
  final bool error;
  final AcaPalette palette;
  final double top;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.error ? 5200 : 3200),
  )
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final tone = widget.error ? p.danger : p.success;
    return Positioned(
      top: widget.top,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final v = _c.value;
          final t = ((v / 0.06).clamp(0.0, 1.0)).clamp(0.0, ((1 - v) / 0.08).clamp(0.0, 1.0)).toDouble();
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child));
        },
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: p.surfaceHigh,
            elevation: 6,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tone.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                Icon(widget.error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    color: tone, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.message, style: TextStyle(color: p.text, fontWeight: FontWeight.w500))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs a mutation with a busy overlay, toasts success or the API error, and
/// returns true on success. Use for every button that changes server state.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    await action();
    navigator.pop();
    if (success != null && context.mounted) toast(context, success);
    return true;
  } on ApiException catch (e) {
    navigator.pop();
    if (context.mounted) toast(context, e.message, error: true);
    return false;
  } catch (e) {
    navigator.pop();
    if (context.mounted) toast(context, 'Something went wrong. Try again.', error: true);
    return false;
  }
}

/// Bottom-sheet confirmation. Destructive actions render the button in danger red.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final p = context.aca;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: p.textMuted, height: 1.45)),
          const SizedBox(height: 24),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Bottom-sheet single text prompt (reasons, notes). Returns null on cancel.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? message,
  String confirmLabel = 'Save',
  bool required = false,
  int maxLines = 3,
  int maxLength = 300,
  bool destructive = false,
  TextInputType? keyboardType,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PromptSheet(
      title: title,
      label: label,
      message: message,
      confirmLabel: confirmLabel,
      required: required,
      maxLines: maxLines,
      maxLength: maxLength,
      destructive: destructive,
      keyboardType: keyboardType,
    ),
  );
}

class _PromptSheet extends StatefulWidget {
  const _PromptSheet({
    required this.title,
    required this.label,
    required this.message,
    required this.confirmLabel,
    required this.required,
    required this.maxLines,
    required this.maxLength,
    required this.destructive,
    required this.keyboardType,
  });

  final String title;
  final String label;
  final String? message;
  final String confirmLabel;
  final bool required;
  final int maxLines;
  final int maxLength;
  final bool destructive;
  final TextInputType? keyboardType;

  @override
  State<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<_PromptSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final canSubmit = !widget.required || _c.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          if (widget.message != null) ...[
            const SizedBox(height: 6),
            Text(widget.message!, style: TextStyle(color: p.textMuted, height: 1.4)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            autofocus: true,
            maxLines: widget.maxLines,
            minLines: 1,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: widget.label),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: widget.destructive
                ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white)
                : null,
            onPressed: canSubmit ? () => Navigator.pop(context, _c.text.trim()) : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- permissions

/// Shows [child] only if the signed-in staff member holds [permission].
class Gate extends StatelessWidget {
  const Gate({super.key, required this.permission, required this.child, this.fallback = const SizedBox.shrink()});

  final String permission;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final allowed = context.select<SessionController, bool>((s) => s.can(permission));
    return allowed ? child : fallback;
  }
}

/// Slim banner shown while the free-tier host is waking up.
class WakingBanner extends StatelessWidget {
  const WakingBanner({super.key, required this.api});
  final AcaApi api;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return ValueListenableBuilder<bool>(
      valueListenable: api.waking,
      builder: (_, waking, _) => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: !waking
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                color: p.toneFill(Tone.warning),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: p.warning),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Waking up the Counterbase server… this can take up to a minute.',
                        style: TextStyle(fontSize: 12.5, color: p.warning, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
      ),
    );
  }
}

/// Maps backend vocabulary to a [Tone] so every screen colours status the same way.
class StatusTone {
  StatusTone._();

  static Tone subscription(String? s) {
    switch (s) {
      case 'ACTIVE':
        return Tone.success;
      case 'TRIAL':
        return Tone.info;
      case 'PAST_DUE':
        return Tone.warning;
      case 'SUSPENDED':
      case 'CANCELLED':
        return Tone.danger;
      default:
        return Tone.neutral;
    }
  }

  static Tone severity(String s) =>
      s == 'CRITICAL' ? Tone.danger : (s == 'WARN' ? Tone.warning : Tone.neutral);

  static Tone role(String r) {
    switch (r) {
      case 'OWNER':
        return Tone.brand;
      case 'ADMIN':
        return Tone.warning;
      case 'SECURITY':
        return Tone.danger;
      case 'FINANCE':
        return Tone.success;
      case 'SUPPORT':
        return Tone.info;
      default:
        return Tone.neutral;
    }
  }
}
