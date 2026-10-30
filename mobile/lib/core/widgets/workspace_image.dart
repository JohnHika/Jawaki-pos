import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../di/injection.dart';
import '../services/auth_service.dart';

/// Renders images saved on this device in local workspaces. A local workspace
/// never requests an old cloud image URL, so a retired POS host cannot slow or
/// break catalog and receipt screens.
class WorkspaceImage extends StatelessWidget {
  const WorkspaceImage({
    super.key,
    required this.source,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String? source;
  final Widget placeholder;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final value = source?.trim();
    if (value == null || value.isEmpty) return placeholder;

    final uri = Uri.tryParse(value);
    final isHttpUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (isHttpUrl) {
      if (getIt<AuthService>().isLocalWorkspace) return placeholder;
      return CachedNetworkImage(
        imageUrl: value,
        fit: fit,
        width: width,
        height: height,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    }

    final filePath = uri?.scheme == 'file' ? uri!.toFilePath() : value;
    return Image.file(
      File(filePath),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
