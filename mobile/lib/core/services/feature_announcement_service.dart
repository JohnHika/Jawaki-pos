import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One feature that can be announced via [FeatureAnnouncementTour].
///
/// Each feature has a stable [id] (used for seen-state persistence), an
/// [icon] and [accentColor] for the announcement card, and a [title] /
/// [description] pair. [animationType] controls which flutter_animate
/// effect the card uses on entrance.
class FeatureAnnouncement {
  const FeatureAnnouncement({
    required this.id,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.description,
    this.animationType = FeatureAnimationType.slideUp,
    this.actionLabel,
    this.onAction,
  });

  /// Stable, unique identifier — used for seen-state persistence so the
  /// same feature is never announced twice on the same device.
  final String id;

  /// IconData for the feature's visual (displayed large on the card).
  final IconData icon;

  /// Accent colour for the card's icon container, border, and glow.
  final Color accentColor;

  /// Short, punchy name of the feature (e.g. "Offline Mode").
  final String title;

  /// One or two sentences explaining what the feature does.
  final String description;

  /// Which entrance animation to use for this step.
  final FeatureAnimationType animationType;

  /// Optional call-to-action label (e.g. "Try it now").
  final String? actionLabel;

  /// Optional callback when the user taps the action button.
  final VoidCallback? onAction;
}

/// Entrance animation styles for feature announcement cards.
enum FeatureAnimationType {
  /// Slides up from the bottom with a slight fade.
  slideUp,

  /// Scales in from the center with a spring.
  scaleIn,

  /// Fades in from the left side.
  slideFromLeft,

  /// Fades in from the right side.
  slideFromRight,

  /// Pops in with a bounce scale effect.
  bounceIn,
}

/// Manages the lifecycle of feature announcements — which features have
/// been shown to this device, and which are pending.
///
/// Persists seen-state in SharedPreferences under the key prefix
/// `feature_announcement_seen_<id>` so the same feature is never
/// announced twice.
class FeatureAnnouncementService extends ChangeNotifier {
  FeatureAnnouncementService();

  static const String _seenPrefix = 'feature_announcement_seen_';

  SharedPreferences? _prefs;
  final List<FeatureAnnouncement> _pending = [];
  bool _initialized = false;

  // ── Initialisation ──────────────────────────────────────────────

  /// Must be called once after SharedPreferences is available (e.g. from
  /// StorageService.initialize or the app's bootstrap).
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // ── Registration ────────────────────────────────────────────────

  /// Register one or more features as pending announcements. Only
  /// features whose [FeatureAnnouncement.id] has not already been seen
  /// on this device are added to the pending queue.
  void register(List<FeatureAnnouncement> features) {
    if (!_initialized) {
      debugPrint(
        '[FeatureAnnouncement] Service not initialised — call initialize() first.',
      );
      return;
    }

    for (final feature in features) {
      if (!_isSeen(feature.id)) {
        _pending.add(feature);
      }
    }

    if (_pending.isNotEmpty) {
      notifyListeners();
    }
  }

  /// Register a single feature announcement.
  void registerOne(FeatureAnnouncement feature) {
    register([feature]);
  }

  // ── Query ───────────────────────────────────────────────────────

  /// Whether there are pending (unseen) announcements.
  bool get hasPending => _pending.isNotEmpty;

  /// The list of pending announcements, in registration order.
  List<FeatureAnnouncement> get pending => List.unmodifiable(_pending);

  /// Number of pending announcements.
  int get pendingCount => _pending.length;

  // ── Consumption ─────────────────────────────────────────────────

  /// Mark a feature as seen and remove it from the pending queue.
  /// Returns true if the feature was actually pending.
  Future<bool> markSeen(String featureId) async {
    if (!_initialized) return false;

    await _persistSeen(featureId);
    final before = _pending.length;
    _pending.removeWhere((f) => f.id == featureId);
    final removed = _pending.length < before;
    if (removed) notifyListeners();
    return removed;
  }

  /// Mark all currently-pending features as seen and clear the queue.
  Future<void> markAllSeen() async {
    if (!_initialized) return;
    for (final feature in _pending) {
      await _persistSeen(feature.id);
    }
    _pending.clear();
    notifyListeners();
  }

  /// Whether a specific feature id has already been seen on this device.
  bool isSeen(String featureId) {
    return _isSeen(featureId);
  }

  // ── Internal helpers ────────────────────────────────────────────

  bool _isSeen(String featureId) {
    return _prefs?.getBool('$_seenPrefix$featureId') ?? false;
  }

  Future<void> _persistSeen(String featureId) async {
    await _prefs?.setBool('$_seenPrefix$featureId', true);
  }
}
