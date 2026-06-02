import { Controller, Get, Res } from '@nestjs/common';
import { ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import { AppUpdatesService } from './app-updates.service';

@ApiTags('app-updates')
@Controller({ path: 'app-updates', version: '1' })
export class AppUpdatesController {
  constructor(private readonly appUpdatesService: AppUpdatesService) {}

  @Get('android/latest')
  @ApiOperation({
    summary: 'Get the latest Android app update manifest',
    description:
      'Public endpoint used by the mobile POS app to determine whether an update is available or required.',
  })
  @ApiResponse({ status: 200, description: 'Android update manifest returned successfully' })
  getLatestAndroidUpdate() {
    return this.appUpdatesService.getLatestAndroidUpdate();
  }

  @Get('android/download')
  @ApiOperation({
    summary: 'Download the latest Android APK',
    description:
      'Public endpoint that serves the Android APK referenced by the mobile update manifest.',
  })
  @ApiResponse({ status: 200, description: 'Android APK download started successfully' })
  @ApiResponse({ status: 404, description: 'Android APK not found on the server' })
  downloadAndroidApk(@Res() res: Response) {
    const asset = this.appUpdatesService.getAndroidApkDownload();

    res.setHeader('Content-Type', 'application/vnd.android.package-archive');
    res.setHeader('Content-Disposition', `attachment; filename="${asset.fileName}"`);

    return res.sendFile(asset.filePath);
  }
}
