import {
  Controller,
  Post,
  UseInterceptors,
  UploadedFile,
  Query,
  Request,
  BadRequestException,
  UseGuards,
  Logger,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiQuery,
  ApiConsumes,
  ApiBody,
} from '@nestjs/swagger';
import { memoryStorage } from 'multer';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { UploadsService, ImageType } from './uploads.service';
import { PrismaService } from '../common/prisma/prisma.service';

const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5 MB
const VALID_TYPES: ImageType[] = ['logo', 'category', 'product', 'stock-request', 'supplier-invoice'];

@ApiTags('uploads')
@Controller({ path: 'uploads', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class UploadsController {
  private readonly logger = new Logger(UploadsController.name);

  constructor(
    private readonly uploadsService: UploadsService,
    private readonly prisma: PrismaService,
  ) {}

  /**
   * Upload an image to Cloudinary.
   * Returns the secure URL + publicId that must be saved on the calling entity.
   */
  @Post('image')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('uploads.image')
  @ApiOperation({ summary: 'Upload a company image (logo, category, product)' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
    },
  })
  @ApiQuery({ name: 'type', enum: ['logo', 'category', 'product', 'stock-request', 'supplier-invoice'] })
  @ApiResponse({ status: 201, description: 'Image uploaded successfully' })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: MAX_FILE_SIZE },
      fileFilter: (_req, file, cb) => {
        if (ALLOWED_MIME_TYPES.includes(file.mimetype)) {
          cb(null, true);
        } else {
          cb(
            new BadRequestException(
              `Invalid file type "${file.mimetype}". Allowed: JPEG, PNG, WebP`,
            ),
            false,
          );
        }
      },
    }),
  )
  async uploadImage(
    @UploadedFile() file: Express.Multer.File,
    @Query('type') type: string,
    @Request() req: any,
  ) {
    if (!file) {
      throw new BadRequestException('No file provided');
    }

    if (!VALID_TYPES.includes(type as ImageType)) {
      throw new BadRequestException(
        `type must be one of: ${VALID_TYPES.join(', ')}`,
      );
    }

    const tenantId: string = req.user.tenantId;
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { slug: true },
    });

    if (!tenant) {
      throw new BadRequestException('Tenant not found');
    }

    this.logger.log(
      `Uploading ${type} image for tenant ${tenant.slug} (${file.size} bytes)`,
    );

    const result = await this.uploadsService.uploadImage(
      file.buffer,
      file.mimetype,
      tenant.slug,
      type as ImageType,
    );

    return {
      url: result.secureUrl,
      publicId: result.publicId,
      width: result.width,
      height: result.height,
      format: result.format,
      bytes: result.bytes,
    };
  }

  /**
   * Upload an image and trace it into a scalable SVG logo. Returns both the
   * original raster URL and the vectorized SVG URL so the caller can preview
   * and choose. Deterministic (Cloudinary vectorize), no AI/token cost.
   */
  @Post('logo/vectorize')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('uploads.image')
  @ApiOperation({ summary: 'Trace an uploaded image into a scalable SVG logo' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: { file: { type: 'string', format: 'binary' } },
    },
  })
  @ApiResponse({ status: 201, description: 'Logo vectorized' })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: MAX_FILE_SIZE },
      fileFilter: (_req, file, cb) => {
        if (ALLOWED_MIME_TYPES.includes(file.mimetype)) {
          cb(null, true);
        } else {
          cb(
            new BadRequestException(
              `Invalid file type "${file.mimetype}". Allowed: JPEG, PNG, WebP`,
            ),
            false,
          );
        }
      },
    }),
  )
  async vectorizeLogo(
    @UploadedFile() file: Express.Multer.File,
    @Request() req: any,
    @Query('colors') colors?: string,
    @Query('detail') detail?: string,
  ) {
    if (!file) {
      throw new BadRequestException('No file provided');
    }

    const tenantId: string = req.user.tenantId;
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { slug: true },
    });
    if (!tenant) {
      throw new BadRequestException('Tenant not found');
    }

    this.logger.log(`Vectorizing logo for tenant ${tenant.slug} (${file.size} bytes)`);

    const result = await this.uploadsService.vectorizeLogo(
      file.buffer,
      file.mimetype,
      tenant.slug,
      {
        colors: colors ? parseInt(colors, 10) : undefined,
        detail: detail ? parseInt(detail, 10) : undefined,
      },
    );

    return {
      rasterUrl: result.secureUrl,
      svgUrl: result.svgUrl,
      publicId: result.publicId,
    };
  }
}
