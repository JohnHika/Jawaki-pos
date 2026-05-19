import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Image serving routes for phone server mode.
///
/// Serves product images stored on the server phone's local filesystem.
/// GET /api/v1/images/products/<filename> → reads from app's images/products/ directory
class ImageRoutes {
  ImageRoutes();

  void addRoutes(Router r) {
    r.get('/api/v1/images/<path|[A-Za-z0-9_/\\-.]+>', _handleImage);
  }

  /// GET /api/v1/images/<path> — serve static image files from device storage
  Future<shelf.Response> _handleImage(shelf.Request request, String imagePath) async {
    // Security: prevent path traversal attacks
    final safePath = p.normalize(imagePath);
    if (safePath.contains('..')) {
      return shelf.Response.forbidden(
        jsonEncode({'error': 'Invalid path'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory(p.join(appDir.path, 'images'));
    if (!await imageDir.exists()) {
      return shelf.Response.notFound(
        jsonEncode({'error': 'Image not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final file = File(p.join(imageDir.path, safePath));
    if (!await file.exists()) {
      return shelf.Response.notFound(
        jsonEncode({'error': 'Image not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final bytes = await file.readAsBytes();
    final contentType = _getContentType(safePath);

    return shelf.Response.ok(
      bytes,
      headers: {'content-type': contentType, 'cache-control': 'public, max-age=86400'},
    );
  }

  String _getContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.svg':
        return 'image/svg+xml';
      default:
        return 'application/octet-stream';
    }
  }
}
