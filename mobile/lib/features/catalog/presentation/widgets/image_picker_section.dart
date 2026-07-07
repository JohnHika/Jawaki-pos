import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';

/// Reusable image picker + uploader used by product, category, and logo
/// forms. Handles camera/gallery selection, upload to the configured
/// storage backend, and shows a preview with change/remove actions.
class ImagePickerSection extends StatefulWidget {
  final String? initialImageUrl;
  final String type; // 'product' | 'category' | 'logo'
  final void Function(String? url, String? publicId) onImageChanged;
  final String label;

  const ImagePickerSection({
    super.key,
    this.initialImageUrl,
    required this.type,
    required this.onImageChanged,
    this.label = 'Add image',
  });

  @override
  State<ImagePickerSection> createState() => _ImagePickerSectionState();
}

class _ImagePickerSectionState extends State<ImagePickerSection> {
  String? _imageUrl;
  String? _localImagePath;
  String? _errorMessage;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.initialImageUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostImage());
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    setState(() => _errorMessage = null);

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                subtitle: const Text('Use the camera'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                subtitle: const Text('Pick an existing image'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 180));

    XFile? file;
    try {
      file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
      );
    } on PlatformException catch (e) {
      _showImageError(
        'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: ${e.message ?? e.code}',
      );
      return;
    } catch (e) {
      _showImageError(
        'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e',
      );
      return;
    }
    if (file == null || !mounted) return;

    setState(() {
      _localImagePath = file!.path;
      _isUploading = true;
    });

    try {
      final result = await getIt<ApiClient>().uploadImage(
        filePath: file.path,
        fileName: file.name,
        type: widget.type,
      );
      if (!mounted) return;
      final url = result['url'] as String?;
      final publicId = result['publicId'] as String?;
      setState(() {
        _imageUrl = url;
        _localImagePath = null;
      });
      widget.onImageChanged(url, publicId);
    } catch (e) {
      _showImageError('Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _recoverLostImage() async {
    try {
      final response = await ImagePicker().retrieveLostData();
      if (!mounted || response.isEmpty) return;
      if (response.exception != null) {
        _showImageError(
          'Image picker was interrupted: ${response.exception!.message ?? response.exception!.code}',
        );
        return;
      }

      final file = response.file;
      if (file == null) return;
      setState(() => _localImagePath = file.path);
    } catch (_) {
      // Lost-data recovery is best effort only.
    }
  }

  void _showImageError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DesignColors.error,
      ),
    );
  }

  void _removeImage() {
    setState(() {
      _imageUrl = null;
      _localImagePath = null;
      _errorMessage = null;
    });
    widget.onImageChanged(null, null);
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploading) {
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: DesignColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DesignColors.brand,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Uploading...',
              style: TextStyle(fontSize: 13, color: DesignColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if ((_localImagePath != null && _localImagePath!.isNotEmpty) ||
        (_imageUrl != null && _imageUrl!.isNotEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildPreviewImage(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: _isUploading ? null : _pickImage,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                      label: const Text('Change image'),
                      style: TextButton.styleFrom(
                        foregroundColor: DesignColors.brand,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _isUploading ? null : _removeImage,
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: DesignColors.error,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isUploading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              minHeight: 2,
              color: DesignColors.brand,
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: DesignColors.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: DesignColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DesignColors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: DesignColors.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: DesignColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: DesignColors.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewImage() {
    if (_localImagePath != null && _localImagePath!.isNotEmpty) {
      return Image.file(
        File(_localImagePath!),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _brokenPreview(),
      );
    }

    return CachedNetworkImage(
      imageUrl: _imageUrl!,
      width: 64,
      height: 64,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        width: 64,
        height: 64,
        color: DesignColors.surfaceSubtle,
      ),
      errorWidget: (_, __, ___) => _brokenPreview(),
    );
  }

  Widget _brokenPreview() {
    return Container(
      width: 64,
      height: 64,
      color: DesignColors.surfaceSubtle,
      child: const Icon(
        Icons.broken_image_outlined,
        color: DesignColors.textTertiary,
        size: 28,
      ),
    );
  }
}
