import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

/// State of the company record shared by the tabs that read it (Overview, Billing).
class DetailLoad {
  const DetailLoad({this.detail, this.error, this.loading = true});
  final TenantDetail? detail;
  final Object? error;
  final bool loading;
}

/// Standard padding for every tab's scrollable.
const EdgeInsets kTabPadding = EdgeInsets.fromLTRB(16, 12, 16, 32);

/// Keeps a tab's loaded data alive while the user swipes between tabs.
class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({super.key, required this.child});
  final Widget child;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Lets the detail screen tell every open tab "reload yourself" after a change.
mixin TenantRefreshMixin<T extends StatefulWidget> on State<T> {
  Listenable get refreshSignal;
  void onRefreshSignal();

  @override
  void initState() {
    super.initState();
    refreshSignal.addListener(onRefreshSignal);
  }

  @override
  void dispose() {
    refreshSignal.removeListener(onRefreshSignal);
    super.dispose();
  }
}

/// A message (empty / error) that can still be pulled to refresh.
class RefreshableFill extends StatelessWidget {
  const RefreshableFill({super.key, required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(height: c.maxHeight, child: child),
          ),
        ),
      );
}

/// Skeleton for a tab that has nothing to show yet.
class TabSkeleton extends StatelessWidget {
  const TabSkeleton({super.key, this.rows = 3, this.rowHeight = 120});
  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) => ListSkeleton(rows: rows, rowHeight: rowHeight);
}

/// Opens an `https`/`mailto`/`tel` link, telling the user when nothing can handle it.
Future<void> openLink(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) toast(context, 'No app on this phone can open that.', error: true);
}

/// A tappable row with an icon, a label and a value (owner e-mail, billing phone...).
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.icon, required this.label, required this.value, this.onTap, this.onLongPressCopy});

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String? onLongPressCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final has = value != null && value!.trim().isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: has ? onTap : null,
      onLongPress: has && onLongPressCopy != null
          ? () {
              Clipboard.setData(ClipboardData(text: onLongPressCopy!));
              toast(context, 'Copied');
            }
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: p.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: p.textMuted)),
                    Text(
                      has ? value! : 'Not on file',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: has ? (onTap != null ? p.brand : p.text) : p.textFaint),
                    ),
                  ],
                ),
              ),
              if (has && onTap != null) Icon(Icons.north_east_rounded, size: 16, color: p.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
