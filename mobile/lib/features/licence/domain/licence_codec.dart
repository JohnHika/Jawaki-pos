import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// A licence is a short signed code that tells one shop's app where it stands
/// with its payments to Arche Axon. The app checks it with no internet.
///
/// Shape: `CBL1.<payload>.<signature>`, both parts base64url without padding.
/// The signature is Ed25519 over the exact payload bytes. Only Arche Axon holds
/// the private key; the app holds the public key, so a shop cannot make or
/// change a licence. A licence names its shop, so one shop's code does not work
/// for another.
const String kLicencePrefix = 'CBL1';

class LicenceClaims {
  const LicenceClaims({
    required this.shopId,
    required this.plan,
    required this.issuedAt,
    required this.dueAt,
    required this.everPaid,
  });

  /// The shop's workspace id on its phone.
  final String shopId;

  /// CORE, BUSINESS or ENTERPRISE.
  final String plan;

  final DateTime issuedAt;

  /// When the next payment falls due (the end of what is paid for).
  final DateTime dueAt;

  /// True once the shop has made a payment. False is a trial licence.
  final bool everPaid;

  Map<String, Object> toJson() => {
        'v': 1,
        'shop': shopId,
        'plan': plan.toUpperCase(),
        'iat': issuedAt.toUtc().toIso8601String(),
        'due': dueAt.toUtc().toIso8601String(),
        'paid': everPaid,
      };

  static LicenceClaims? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['v'] != 1) return null;
    final shop = json['shop'];
    final plan = json['plan'];
    final iat = DateTime.tryParse('${json['iat']}');
    final due = DateTime.tryParse('${json['due']}');
    final paid = json['paid'];
    if (shop is! String || shop.isEmpty) return null;
    if (plan is! String || plan.isEmpty) return null;
    if (iat == null || due == null || paid is! bool) return null;
    return LicenceClaims(
      shopId: shop,
      plan: plan,
      issuedAt: iat.toUtc(),
      dueAt: due.toUtc(),
      everPaid: paid,
    );
  }
}

enum LicenceProblem {
  /// Not a licence code at all, or damaged when copied.
  malformed,

  /// The signature does not match: changed, or not made by Arche Axon.
  badSignature,

  /// A real licence, but for a different shop.
  wrongShop,
}

class LicenceCheck {
  const LicenceCheck.valid(LicenceClaims this.claims) : problem = null;
  const LicenceCheck.invalid(LicenceProblem this.problem) : claims = null;

  final LicenceClaims? claims;
  final LicenceProblem? problem;

  bool get isValid => claims != null;
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int>? _unb64(String text) {
  try {
    return base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    return null;
  }
}

final Ed25519 _ed = Ed25519();

/// Makes a licence code. Used by Arche Axon's own tool and by tests, never by
/// the shop's app.
Future<String> signLicence(LicenceClaims claims, SimpleKeyPair keyPair) async {
  final payload = utf8.encode(jsonEncode(claims.toJson()));
  final signature = await _ed.sign(payload, keyPair: keyPair);
  return '$kLicencePrefix.${_b64(payload)}.${_b64(signature.bytes)}';
}

/// Checks a licence code against Arche Axon's public key and this shop's id.
Future<LicenceCheck> verifyLicence(
  String token, {
  required List<int> publicKey,
  required String shopId,
}) async {
  // Codes get copied over messages, so allow stray spaces and line breaks.
  final cleaned = token.replaceAll(RegExp(r'\s+'), '');
  final parts = cleaned.split('.');
  if (parts.length != 3 || parts[0] != kLicencePrefix) {
    return const LicenceCheck.invalid(LicenceProblem.malformed);
  }
  final payload = _unb64(parts[1]);
  final signature = _unb64(parts[2]);
  if (payload == null || signature == null || signature.length != 64) {
    return const LicenceCheck.invalid(LicenceProblem.malformed);
  }

  final ok = await _ed.verify(
    payload,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
  if (!ok) return const LicenceCheck.invalid(LicenceProblem.badSignature);

  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(payload));
  } on FormatException {
    return const LicenceCheck.invalid(LicenceProblem.malformed);
  }
  final claims = LicenceClaims.fromJson(decoded);
  if (claims == null) {
    return const LicenceCheck.invalid(LicenceProblem.malformed);
  }
  if (claims.shopId != shopId) {
    return const LicenceCheck.invalid(LicenceProblem.wrongShop);
  }
  return LicenceCheck.valid(claims);
}
