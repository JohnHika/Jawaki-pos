import {
  BadRequestException,
  Body,
  Controller,
  FileTypeValidator,
  HttpCode,
  HttpStatus,
  MaxFileSizeValidator,
  ParseFilePipe,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { BugReportService, CreateBugReportInput } from './bug-report.service';

class CreateBugReportDto {
  title: string;
  description: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  component?: string;
}

const ALLOWED_MIMETYPES = [
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'video/mp4',
  'video/webm',
  'video/quicktime',
];

@ApiTags('bug-report')
@Controller({ path: 'bug-report', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class BugReportController {
  constructor(private readonly service: BugReportService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Submit a bug report that creates a Huly issue' })
  @ApiConsumes('multipart/form-data')
  @Throttle({ default: { ttl: 60000, limit: 5 } })
  @UseInterceptors(FileInterceptor('attachment'))
  async create(
    @CurrentUser() user: any,
    @Body() dto: CreateBugReportDto,
    @UploadedFile(
      new ParseFilePipe({
        validators: [
          new MaxFileSizeValidator({ maxSize: 25 * 1024 * 1024, message: 'Attachment must be 25MB or smaller' }),
          new FileTypeValidator({ fileType: ALLOWED_MIMETYPES.join('|') }),
        ],
        fileIsRequired: false,
      }),
    )
    file: Express.Multer.File | undefined,
  ) {
    if (!dto.title || dto.title.trim().length < 3) {
      throw new BadRequestException('Title must be at least 3 characters');
    }
    if (!dto.description || dto.description.trim().length < 10) {
      throw new BadRequestException('Description must be at least 10 characters');
    }

    const input: CreateBugReportInput = {
      title: dto.title.trim(),
      description: dto.description.trim(),
      severity: dto.severity,
      component: dto.component,
      metadata: {
        appVersion: '1.0.49',
        deviceOs: 'Android',
        userId: user?.sub ?? 'unknown',
        currentScreen: 'in-app',
      },
      attachment: file
        ? {
            fileName: file.originalname,
            contentType: file.mimetype,
            buffer: file.buffer,
          }
        : undefined,
    };

    return this.service.createBugReport(input);
  }
}
