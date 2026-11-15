import 'package:flutter/material.dart';

import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/theme/design_system.dart';

BusinessLayoutAction? _actionFor(String path) {
  for (final action in businessLayoutActions) {
    if (action.path == path) return action;
  }
  return null;
}

/// A miniature of the shop's screen that redraws as the layout changes: the
/// opening screen, the checkout tiles, the quick actions and the navigation
/// bar. On a wide space it is drawn as a tablet or POS terminal, on a narrow
/// one as a phone, so the owner sees how the same layout redistributes.
class LayoutLivePreview extends StatelessWidget {
  const LayoutLivePreview({
    super.key,
    required this.layout,
    this.wide = false,
    this.height = 190,
  });

  final BusinessLayoutConfig layout;

  /// Draw a landscape tablet / POS terminal instead of a portrait phone.
  final bool wide;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = layout.preset.accent ?? DesignColors.accent;
    final frame = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final line = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final muted = isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    final nav = layout.priorityPaths
        .where(layout.isActionVisible)
        .map(_actionFor)
        .whereType<BusinessLayoutAction>()
        .take(wide ? 6 : 4)
        .toList(growable: false);
    final startPath = layout.startPath ??
        (layout.priorityPaths.isEmpty ? null : layout.priorityPaths.first);
    final startAction = startPath == null ? null : _actionFor(startPath);
    final title = startAction == null
        ? 'Home'
        : layout.actionLabel(startAction.path, startAction.label);
    final quick = layout.effectivePosQuickActions
        .map((id) => businessLayoutPosActions.where((a) => a.id == id).firstOrNull)
        .whereType<BusinessLayoutPosAction>()
        .take(wide ? 5 : 3)
        .toList(growable: false);
    final grid = layout.effectivePosProductView != 'list';

    final screen = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: KeyedSubtree(
        key: ValueKey('${layout.profileId}|$title|${nav.map((a) => a.path).join()}|$grid|${quick.length}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              color: accent.withValues(alpha: .14),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: accent),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: grid
                          ? GridView.count(
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: wide ? 4 : 3,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                              children: [
                                for (var i = 0; i < (wide ? 8 : 6); i++)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: i.isEven ? .16 : .08),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                              ],
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < 4; i++)
                                  Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 3),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: i.isEven ? .16 : .08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (wide) ...[
                      const SizedBox(width: 7),
                      Expanded(
                        flex: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: line),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: LayoutBuilder(builder: (context, box) {
                              // Only as many rows as fit above the button.
                              final rows = ((box.maxHeight - 17) / 14)
                                  .floor()
                                  .clamp(0, quick.length);
                              return Column(
                              children: [
                                for (final a in quick.take(rows))
                                  Container(
                                    height: 11,
                                    margin: const EdgeInsets.only(bottom: 3),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: .12),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      a.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(fontSize: 6.5, color: accent, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                const Spacer(),
                                Container(
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!wide && quick.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 0, 7, 5),
                child: Row(
                  children: [
                    for (var i = 0; i < quick.length; i++)
                      Expanded(
                        child: Container(
                          height: 12,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            border: Border.all(color: accent.withValues(alpha: .5)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Container(
              height: 26,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: line))),
              child: Row(
                children: [
                  for (var i = 0; i < nav.length; i++)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(nav[i].icon, size: 10, color: i == 0 ? accent : muted),
                          Text(
                            layout.actionLabel(nav[i].path, nav[i].label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 5.5, color: i == 0 ? accent : muted),
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: Icon(Icons.more_horiz_rounded, size: 10, color: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      label: 'Preview of the ${layout.preset.name} screen',
      child: SizedBox(
        height: height,
        child: AspectRatio(
          aspectRatio: wide ? 1.5 : .62,
          child: Container(
            padding: EdgeInsets.all(wide ? 5 : 4),
            decoration: BoxDecoration(
              color: frame,
              borderRadius: BorderRadius.circular(wide ? 12 : 16),
              border: Border.all(color: line, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(wide ? 8 : 12),
              child: ColoredBox(
                color: isDark ? DesignColors.darkSurface : const Color(0xFFFAFAF9),
                child: screen,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
