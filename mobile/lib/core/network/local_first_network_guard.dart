import 'dart:io';

import 'package:dio/dio.dart';

/// Prevents the downloadable POS from silently talking to the retired online
/// backend. Requests to loopback/private LAN hosts are reserved for optional
/// device-to-device local networking. The Axon gateway is allowed only for
/// explicitly tagged POS-AI requests carrying a bearer key.
class LocalFirstNetworkGuard extends Interceptor {
  const LocalFirstNetworkGuard();

  static bool isLocalNetworkHost(String host) {
    final normalized =
        host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (normalized == 'localhost' || normalized.endsWith('.local')) return true;

    // Parse IP literals before applying private-range checks. Prefix checks on
    // the raw host (for example startsWith('fd')) also match public DNS names
    // such as "fd.example.com", which would bypass the local-only guard.
    final address = InternetAddress.tryParse(normalized);
    if (address == null) return false;

    if (address.type == InternetAddressType.IPv6) {
      final bytes = address.rawAddress;
      if (bytes.length != 16) return false;

      // IPv6 loopback (::1).
      if (bytes.take(15).every((byte) => byte == 0) && bytes.last == 1) {
        return true;
      }

      // IPv4-mapped IPv6 addresses inherit the IPv4 local-network policy.
      final isIpv4Mapped = bytes.take(10).every((byte) => byte == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff;
      if (isIpv4Mapped) {
        return _isPrivateIpv4(bytes[12], bytes[13], bytes[14], bytes[15]);
      }

      // Unique-local fc00::/7 and link-local fe80::/10 only.
      final isUniqueLocal = (bytes[0] & 0xfe) == 0xfc;
      final isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
      return isUniqueLocal || isLinkLocal;
    }

    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes.length == 4 &&
        _isPrivateIpv4(bytes[0], bytes[1], bytes[2], bytes[3]);
  }

  static bool _isPrivateIpv4(int a, int b, int c, int d) {
    return a == 10 ||
        a == 127 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  static bool isLocalNetworkUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        isLocalNetworkHost(uri.host);
  }

  bool _isAuthorizedGatewayAiRequest(RequestOptions options) {
    final uri = options.uri;
    final validPath = const {
      '/v1/pos/chat',
      '/v1/pos/chat/stream',
      '/v1/pos/vision',
    }.contains(uri.path);
    final authorization = options.headers['Authorization']?.toString() ?? '';
    return options.extra['allowAxonGatewayAi'] == true &&
        uri.scheme == 'https' &&
        uri.host == 'gateway.archeaxon.com' &&
        validPath &&
        authorization.startsWith('Bearer ') &&
        authorization.length > 'Bearer '.length;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isLocalNetworkHost(options.uri.host) ||
        _isAuthorizedGatewayAiRequest(options)) {
      handler.next(options);
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message:
            'This downloadable POS only connects to this device or a local network. Online POS services are retired.',
      ),
    );
  }
}
