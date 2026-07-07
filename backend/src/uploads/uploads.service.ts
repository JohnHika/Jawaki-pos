import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { v2 as cloudinary, UploadApiResponse } from 'cloudinary';

/**
 * Axon POS Cloudinary Upload Service
 * Handles image uploads for Axon POS by Arche Axon Intelligence
 */

export interface UploadResult {
  url: string;
  secureUrl: string;
  publicId: string;
  width?: number;
  height?: number;
  format?: string;
  bytes?: number;
}

export type ImageType = 'logo' | 'category' | 'product' | 'stock-request';

@Injectable()
export class UploadsService {
  private readonly logger = new Logger(UploadsService.name);
  private readonly cloudFolder = 'axon_pos';

  constructor(private readonly config: ConfigService) {
    cloudinary.config({
      cloud_name: this.config.get<string>('CLOUDINARY_CLOUD_NAME'),
      api_key: this.config.get<string>('CLOUDINARY_API_KEY'),
      api_secret: this.config.get<string>('CLOUDINARY_API_SECRET'),
    });
  }

  /**
   * Upload an image buffer to Cloudinary for Axon POS.
   * @param buffer  File buffer from multer
   * @param mimeType File MIME type
   * @param tenantSlug  Sanitized tenant slug (used as Cloudinary subfolder)
   * @param type    'logo' | 'category' | 'product'
   */
  async uploadImage(
    buffer: Buffer,
    mimeType: string,
    tenantSlug: string,
    type: ImageType,
  ): Promise<UploadResult> {
    const safeSlug = this.sanitizeSlug(tenantSlug);
    const folder = `${this.cloudFolder}/${safeSlug}/${type}s`;

    const resourceType = mimeType.startsWith('image/') ? 'image' : 'raw';

    return new Promise((resolve, reject) => {
      const uploadStream = cloudinary.uploader.upload_stream(
        {
          folder,
          resource_type: resourceType,
          allowed_formats: ['jpg', 'jpeg', 'png', 'webp'],
          transformation: [
            ...(type === 'logo'
              ? [{ width: 400, height: 400, crop: 'limit', quality: 'auto:good' }]
              : type === 'category'
              ? [{ width: 800, height: 600, crop: 'limit', quality: 'auto:good' }]
              : [{ width: 1200, height: 1200, crop: 'limit', quality: 'auto:good' }]),
          ],
        },
        (error, result) => {
          if (error || !result) {
            this.logger.error(`Cloudinary upload failed: ${error?.message}`);
            reject(error || new Error('Upload failed with no result'));
          } else {
            resolve({
              url: result.url,
              secureUrl: result.secure_url,
              publicId: result.public_id,
              width: result.width,
              height: result.height,
              format: result.format,
              bytes: result.bytes,
            });
          }
        },
      );
      uploadStream.end(buffer);
    });
  }

  /**
   * Delete an image from Cloudinary by public_id.
   * Failures are logged but not thrown (non-blocking).
   */
  async deleteImage(publicId: string): Promise<void> {
    try {
      await cloudinary.uploader.destroy(publicId);
      this.logger.log(`Deleted Cloudinary image: ${publicId}`);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Failed to delete Cloudinary image ${publicId}: ${msg}`);
    }
  }

  /** Sanitize a tenant slug to safe folder path characters. */
  private sanitizeSlug(slug: string): string {
    return slug
      .toLowerCase()
      .replace(/[^a-z0-9_-]/g, '_')
      .substring(0, 50);
  }
}
