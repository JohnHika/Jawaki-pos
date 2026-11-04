import 'dart:convert';

import '../../../core/services/storage_service.dart';
import '../domain/licence_codec.dart';
import '../domain/licence_keys.dart';
import '../domain/licence_standing.dart';
import '../domain/setup_pricing.dart';

/// The last standing worked out, readable from anywhere without waiting. Code
/// that rings up a sale asks here. When no licence is being enforced, or the
/// standing is not known yet, selling is allowed: a shop is never stopped by
/// a doubt.
class LicenceGate {
  const LicenceGate._();

  static LicenceStanding? standing;

  static bool get canSell => standing?.canSell ?? true;

  static const String pausedMessage =
      'New sales are paused until your payment is made. Your records stay open. See Settings, Plan and licence.';
}

/// Reads and checks the shop's licence on the phone. Works with no internet.
class LicenceService {
  LicenceService(
    this._storage, {
    List<int>? publicKey,
    DateTime Function()? clock,
  })  : _publicKey = publicKey ?? decodeLicencePublicKey(kLicencePublicKeyBase64),
        _clock = clock ?? DateTime.now;

  final StorageService _storage;
  final List<int>? _publicKey;
  final DateTime Function() _clock;

  /// False until Arche Axon's public key is set in the app. While false, no
  /// shop is limited in any way.
  bool get enforced => _publicKey != null && _publicKey.isNotEmpty;

  /// This shop's workspace id, the one a licence is made for.
  String? get shopId {
    final tenant = _storage.getLocalWorkspace()?['tenant'];
    final id = tenant is Map ? tenant['id'] : null;
    return id is String && id.isNotEmpty ? id : null;
  }

  DateTime? get _workspaceCreatedAt {
    final raw = _storage.getLocalWorkspace()?['createdAt'];
    return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
  }

  /// The checked claims of the saved licence, or null when there is none or it
  /// no longer checks out.
  Future<LicenceClaims?> savedClaims() async {
    final key = _publicKey;
    final shop = shopId;
    final token = _storage.getLicenceToken();
    if (key == null || key.isEmpty || shop == null || token == null) {
      return null;
    }
    final check = await verifyLicence(token, publicKey: key, shopId: shop);
    return check.claims;
  }

  /// Works out the standing, remembers it for [LicenceGate] and returns it.
  /// Returns null when licences are not enforced.
  Future<LicenceStanding?> refresh() async {
    if (!enforced) {
      LicenceGate.standing = null;
      return null;
    }
    final created = _workspaceCreatedAt;
    if (shopId == null || created == null) {
      LicenceGate.standing = null;
      return null;
    }

    // Winding the phone's clock back must not buy more time, so time never
    // goes backwards from the latest moment this phone has seen.
    var now = _clock().toUtc();
    final lastSeen = _storage.getLicenceLastSeenMs();
    if (lastSeen != null) {
      final seen = DateTime.fromMillisecondsSinceEpoch(lastSeen, isUtc: true);
      if (seen.isAfter(now)) now = seen;
    }
    if (lastSeen == null || now.millisecondsSinceEpoch > lastSeen) {
      await _storage.saveLicenceLastSeenMs(now.millisecondsSinceEpoch);
    }

    final claims = await savedClaims();
    final standing = claims != null
        ? standingFor(everPaid: claims.everPaid, dueAt: claims.dueAt, now: now)
        : standingFor(
            everPaid: false,
            dueAt: created.add(const Duration(days: kTrialDays)),
            now: now,
          );
    LicenceGate.standing = standing;
    return standing;
  }

  /// Checks a licence code and, if it is good for this shop, saves it.
  Future<LicenceCheck> redeem(String token) async {
    final key = _publicKey;
    final shop = shopId;
    if (key == null || key.isEmpty || shop == null) {
      return const LicenceCheck.invalid(LicenceProblem.malformed);
    }
    final check = await verifyLicence(token, publicKey: key, shopId: shop);
    if (check.isValid) {
      await _storage.saveLicenceToken(token.replaceAll(RegExp(r'\s+'), ''));
      await refresh();
    }
    return check;
  }
}

/// Decodes the public key written in [kLicencePublicKeyBase64]. Empty or bad
/// text gives null, which switches enforcement off.
List<int>? decodeLicencePublicKey(String text) {
  final cleaned = text.trim();
  if (cleaned.isEmpty) return null;
  try {
    final bytes = base64Url.decode(base64Url.normalize(cleaned));
    return bytes.length == 32 ? bytes : null;
  } on FormatException {
    return null;
  }
}
