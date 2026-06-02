import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { existsSync } from 'fs';
import { isAbsolute, resolve } from 'path';

@Injectable()
export class AppUpdatesService {
  constructor(private readonly config: ConfigService) {}

  getLatestAndroidUpdate() {
    const latestVersion = this.config.get<string>('ANDROID_APP_LATEST_VERSION', '1.0.2');

    return {
      platform: 'android',
      latestVersion,
      minSupportedVersion: this.config.get<string>(
        'ANDROID_APP_MIN_SUPPORTED_VERSION',
        latestVersion,
      ),
      forceUpdate: this.parseBoolean(
        this.config.get<string>('ANDROID_APP_FORCE_UPDATE', 'true'),
      ),
      apkUrl: this.config.get<string>(
        'ANDROID_APP_APK_URL',
        '/api/v1/app-updates/android/download',
      ),
      releaseNotes: this.config.get<string>('ANDROID_APP_RELEASE_NOTES', ''),
      publishedAt: this.config.get<string>('ANDROID_APP_PUBLISHED_AT') || null,
    };
  }

  getAndroidApkDownload() {
    const filePath = this.resolveAndroidApkFilePath();
    if (!filePath) {
      throw new NotFoundException(
        'Android update APK was not found on the server. Build the mobile app or set ANDROID_APP_APK_FILE_PATH.',
      );
    }

    const latestVersion = this.config.get<string>('ANDROID_APP_LATEST_VERSION', '1.0.2');

    return {
      filePath,
      fileName: `pos-${latestVersion}.apk`,
    };
  }

  private resolveAndroidApkFilePath(): string | null {
    const configuredPath = this.config.get<string>('ANDROID_APP_APK_FILE_PATH')?.trim();

    const candidates = [
      configuredPath
          ? isAbsolute(configuredPath)
              ? configuredPath
              : resolve(process.cwd(), configuredPath)
          : null,
      resolve(process.cwd(), 'public', 'downloads', 'pos-latest.apk'),
      resolve(
        process.cwd(),
        '..',
        'mobile',
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-release.apk',
      ),
    ].filter((value): value is string => Boolean(value));

    return candidates.find((candidate) => existsSync(candidate)) ?? null;
  }

  private parseBoolean(value: string): boolean {
    return ['true', '1', 'yes', 'on'].includes(value.toLowerCase().trim());
  }
}
