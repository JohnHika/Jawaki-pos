import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Desktop-side client for phone-approved sign-in (QR / short code).
///
/// The desktop asks the phone's local server to open a pairing challenge,
/// shows the returned QR + 6-digit code, polls until the phone approves or
/// denies, then redeems the pairing for the same tokens a phone login
/// mints. The claim secret travels only inside the QR payload; the desktop
/// stores it in memory for the life of the pairing screen.
class DesktopLinkClient {
  DesktopLinkClient({this.baseUrlOverride});

  /// Host base like `http://192.168.1.20:3000` (no /api/v1 suffix).
  final String? baseUrlOverride;

  static const _requestTimeout = Duration(seconds: 12);
  static final HttpClient _httpClient = HttpClient()..maxConnectionsPerHost = 4;

  static bool isPrivateNetworkHost(String host) {
    final normalized = host
        .toLowerCase()
        .replaceAll('[', '')
        .replaceAll(']', '');
    if (normalized == 'localhost' || normalized.endsWith('.local')) return true;

    final address = InternetAddress.tryParse(normalized);
    if (address == null) return false;
    final bytes = address.rawAddress;

    if (address.type == InternetAddressType.IPv4) {
      if (bytes.length != 4) return false;
      final a = bytes[0];
      final b = bytes[1];
      return a == 10 ||
          a == 127 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168);
    }

    if (address.type != InternetAddressType.IPv6 || bytes.length != 16) {
      return false;
    }
    if (bytes.take(15).every((byte) => byte == 0) && bytes.last == 1) {
      return true;
    }
    final isIpv4Mapped =
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (isIpv4Mapped) {
      final a = bytes[12];
      final b = bytes[13];
      return a == 10 ||
          a == 127 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168);
    }
    return (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  static bool isPrivateNetworkBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.hasAuthority &&
        {'http', 'https'}.contains(uri.scheme.toLowerCase()) &&
        isPrivateNetworkHost(uri.host) &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final rawBase = baseUrlOverride?.trim() ?? '';
    if (!isPrivateNetworkBaseUrl(rawBase)) {
      throw const DesktopLinkFailure(
        'Enter the phone’s private-network address shown in its Backend Server settings.',
      );
    }
    final base = Uri.parse(rawBase);
    return base.replace(path: '/api/v1$path', queryParameters: query);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final request = await _httpClient
          .postUrl(_uri(path))
          .timeout(_requestTimeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final httpResponse = await request.close().timeout(_requestTimeout);
      final text = await utf8
          .decodeStream(httpResponse)
          .timeout(_requestTimeout);
      return _decode(httpResponse.statusCode, text);
    } on TimeoutException {
      throw const DesktopLinkFailure(
        'The phone is not answering. Check both devices are on the same network.',
      );
    } on SocketException {
      throw const DesktopLinkFailure(
        'Could not reach the phone. Check both devices are on the same network.',
      );
    } on HttpException {
      throw const DesktopLinkFailure(
        'The phone did not complete the local sign-in request. Try again.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(String path, String linkId) async {
    try {
      final request = await _httpClient
          .getUrl(_uri(path, {'linkId': linkId}))
          .timeout(_requestTimeout);
      request.followRedirects = false;
      final httpResponse = await request.close().timeout(_requestTimeout);
      final text = await utf8
          .decodeStream(httpResponse)
          .timeout(_requestTimeout);
      return _decode(httpResponse.statusCode, text);
    } on TimeoutException {
      throw const DesktopLinkFailure('The phone stopped answering.');
    } on SocketException {
      throw const DesktopLinkFailure('Could not reach the phone.');
    } on HttpException {
      throw const DesktopLinkFailure(
        'The phone did not complete the local sign-in request. Try again.',
      );
    }
  }

  /// Opens a challenge. Returns the QR payload, the human code, and ids.
  Future<DesktopLinkStart> start({required String desktopName}) async {
    final data = await _post('/desktop-link/start', {
      'desktopName': desktopName,
    });
    return DesktopLinkStart(
      linkId: data['linkId'] as String,
      code: data['code'] as String,
      qr: data['qr'] as String,
      expiresAt:
          DateTime.tryParse(data['expiresAt']?.toString() ?? '') ??
          DateTime.now().add(const Duration(minutes: 3)),
    );
  }

  /// Polls once. Never throws for business states; only for transport loss.
  Future<DesktopLinkStatus> status(String linkId) async {
    final data = await _get('/desktop-link/status', linkId);
    final account = data['account'] as Map<String, dynamic>?;
    return DesktopLinkStatus(
      status: (data['status'] ?? 'expired').toString(),
      accountName: account == null
          ? null
          : '${account['firstName'] ?? ''} ${account['lastName'] ?? ''}'.trim(),
      expiresAt:
          DateTime.tryParse(data['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Redeems an approved pairing for session tokens.
  Future<DesktopLinkSession> claim({
    required String linkId,
    required String secret,
  }) async {
    final data = await _post('/desktop-link/claim', {
      'linkId': linkId,
      'secret': secret,
    });
    final user = data['user'] as Map<String, dynamic>? ?? const {};
    return DesktopLinkSession(
      accessToken: data['accessToken']?.toString() ?? '',
      refreshToken: data['refreshToken']?.toString() ?? '',
      userName: '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
      role: user['role']?.toString() ?? 'CASHIER',
    );
  }

  static Map<String, dynamic> _decode(int statusCode, String text) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw DesktopLinkFailure(
        'The phone answered with something unexpected (HTTP $statusCode).',
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw DesktopLinkFailure(
        (body['message'] ??
                body['error'] ??
                'Request failed (HTTP $statusCode)')
            .toString(),
      );
    }
    return body;
  }
}

class DesktopLinkFailure implements Exception {
  const DesktopLinkFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class DesktopLinkStart {
  const DesktopLinkStart({
    required this.linkId,
    required this.code,
    required this.qr,
    required this.expiresAt,
  });

  final String linkId;
  final String code;
  final String qr;
  final DateTime expiresAt;

  /// The claim secret embedded in the QR payload (field `s`).
  String? get secret {
    try {
      final parsed = jsonDecode(qr);
      return parsed is Map<String, dynamic> ? parsed['s'] as String? : null;
    } catch (_) {
      return null;
    }
  }
}

class DesktopLinkStatus {
  const DesktopLinkStatus({
    required this.status,
    this.accountName,
    required this.expiresAt,
  });

  final String status;
  final String? accountName;
  final DateTime expiresAt;
}

class DesktopLinkSession {
  const DesktopLinkSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userName,
    required this.role,
  });

  final String accessToken;
  final String refreshToken;
  final String userName;
  final String role;
}
