import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { BugReportService, CreateBugReportInput } from './bug-report.service';

class CreateBugReportDto {
  title: string;
  description: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  screenshotBase64?: string;
  screenshotMimeType?: string;
}

@ApiTags('bug-report')
@Controller({ path: 'bug-report', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class BugReportController {
  constructor(private readonly service: BugReportService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Submit a bug report that creates a Huly issue' })
  async create(
    @CurrentUser() user: any,
    @Body() dto: CreateBugReportDto,
  ) {
    const input: CreateBugReportInput = {
      title: dto.title,
      description: dto.description,
      severity: dto.severity,
      metadata: {
        appVersion: '1.0.49',
        deviceOs: 'Android',
        userId: user?.sub ?? 'unknown',
        currentScreen: 'in-app',
      },
      screenshotBase64: dto.screenshotBase64,
      screenshotMimeType: dto.screenshotMimeType,
    };
    return this.service.createBugReport(input);
  }
}
