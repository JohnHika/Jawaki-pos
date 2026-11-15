import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import '../desktop/desktop_layout.dart';

/// Which kind of screen the app is being drawn on.
///
/// One answer for phone, tablet / till terminal and computer, so every screen
/// stops guessing from its own width check and they redistribute together:
///
/// - [phone]: under 600 logical pixels wide. Bottom bar, one column.
/// - [tablet]: 600 and up on a phone, tablet or till terminal, and a computer
///   window narrower than the desktop shell (900). Side rail, two columns
///   where a page has them.
/// - [desktop]: a computer window 900 wide or more. Sidebar, top bar, panels.
enum DeviceClass { phone, tablet, desktop }

/// Widths where the layout changes. The desktop switch lives in
/// [DesktopLayout.shellMinWidth]; this adds the tablet tier below it.
class Breakpoints {
  const Breakpoints._();

  /// A phone held sideways, a small tablet or a till terminal starts here.
  static const double tablet = DesktopLayout.tabletMinWidth;

  /// A page with a list and a detail beside each other starts here, measured
  /// on the page itself (after any rail), not on the whole screen.
  static const double twoColumn = 640;

  /// Tablet pages stop growing here so a large tablet does not stretch a line
  /// of text across the room.
  static const double tabletContentMaxWidth = 1240;

  static DeviceClass classify(double width, {required bool desktopShell}) {
    if (desktopShell) return DeviceClass.desktop;
    return width >= tablet ? DeviceClass.tablet : DeviceClass.phone;
  }
}

extension DeviceClassContext on BuildContext {
  /// The device class for this context's window.
  DeviceClass get deviceClass => Breakpoints.classify(
        MediaQuery.sizeOf(this).width,
        desktopShell: DesktopLayout.wantsShell(this),
      );

  bool get isPhoneLayout => deviceClass == DeviceClass.phone;

  /// True on a tablet or till terminal (not the computer shell).
  bool get isTabletLayout => deviceClass == DeviceClass.tablet;

  /// True when there is room for two columns on this page, wherever the page
  /// sits (inside a rail, a sidebar or full width).
  bool get hasRoomForTwoColumns =>
      MediaQuery.sizeOf(this).width >= Breakpoints.twoColumn;
}

/// What a folding phone's hinge is doing right now.
///
/// - [none]: no fold or hinge reported (every ordinary phone and tablet).
/// - [flat]: a fold exists but the screen is open flat (or the posture is not
///   reported), so the page spreads across both halves.
/// - [book]: half open with a vertical hinge, like a book held upright.
/// - [tabletop]: half open with a horizontal hinge, like a small laptop.
enum FoldPosture { none, flat, book, tabletop }

/// The fold or hinge of a foldable phone, if there is one, in screen
/// coordinates. Cut-outs (notches) are ignored: they never split a page.
@immutable
class FoldInfo {
  const FoldInfo({this.bounds, this.posture = FoldPosture.none});

  /// No fold: the answer on every phone and tablet that does not bend.
  static const FoldInfo none = FoldInfo();

  /// Where the fold or hinge sits on screen (logical pixels), or null.
  final Rect? bounds;
  final FoldPosture posture;

  bool get hasFold => bounds != null;

  /// A fold that runs top to bottom, which puts a page's panes side by side.
  bool get isVertical => bounds != null && bounds!.height >= bounds!.width;

  /// Reads the first fold or hinge out of the window's display features.
  factory FoldInfo.fromFeatures(Iterable<DisplayFeature> features) {
    for (final feature in features) {
      if (feature.type != DisplayFeatureType.fold &&
          feature.type != DisplayFeatureType.hinge) {
        continue;
      }
      final bounds = feature.bounds;
      final vertical = bounds.height >= bounds.width;
      final halfOpen = feature.state == DisplayFeatureState.postureHalfOpened;
      return FoldInfo(
        bounds: bounds,
        posture: !halfOpen
            ? FoldPosture.flat
            : (vertical ? FoldPosture.book : FoldPosture.tabletop),
      );
    }
    return FoldInfo.none;
  }

  @override
  bool operator ==(Object other) =>
      other is FoldInfo && other.bounds == bounds && other.posture == posture;

  @override
  int get hashCode => Object.hash(bounds, posture);
}

extension FoldContext on BuildContext {
  /// The fold or hinge of this device, or [FoldInfo.none].
  FoldInfo get foldInfo =>
      FoldInfo.fromFeatures(MediaQuery.displayFeaturesOf(this));
}

/// Centres tablet content and stops it growing past [maxWidth]. A phone and the
/// computer shell pass through untouched (the shell has its own content width).
class TabletContent extends StatelessWidget {
  const TabletContent({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.tabletContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.isTabletLayout) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
