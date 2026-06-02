import axios from 'axios';
import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { existsSync } from 'fs';
import { isAbsolute, resolve } from 'path';

type AndroidUpdateManifest = {
  platform: 'android';
  latestVersion: string;
  minSupportedVersion: string;
  forceUpdate: boolean;
  apkUrl: string;
  releaseNotes: string;
  publishedAt: string | null;
};

@Injectable()
export class AppUpdatesService {
  private readonly logger = new Logger(AppUpdatesService.name);

  constructor(private readonly config: ConfigService) {}

  async getLatestAndroidUpdate(): Promise<AndroidUpdateManifest> {
    const fallbackManifest = this.buildLocalAndroidManifest();
    const manifestUrl = this.config.get<string>('ANDROID_APP_MANIFEST_URL', '').trim();

    if (!manifestUrl) {
      return fallbackManifest;
    }

    try {
      const response = await axios.get<Record<string, unknown>>(manifestUrl, {
        timeout: this.getManifestTimeoutMs(),
      });

      return this.mergeRemoteManifest(response.data, fallbackManifest);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      this.logger.warn(
        `Failed to load Android app manifest from ${manifestUrl}. Falling back to local env configuration. ${message}`,
      );

      return fallbackManifest;
    }
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

  private buildLocalAndroidManifest(): AndroidUpdateManifest {
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

  private mergeRemoteManifest(
    remoteManifest: Record<string, unknown>,
    fallbackManifest: AndroidUpdateManifest,
  ): AndroidUpdateManifest {
    const latestVersion = this.readString(remoteManifest.latestVersion) || fallbackManifest.latestVersion;

    return {
      platform: 'android',
      latestVersion,
      minSupportedVersion:
        this.readString(remoteManifest.minSupportedVersion) || fallbackManifest.minSupportedVersion,
      forceUpdate: this.parseBoolean(remoteManifest.forceUpdate, fallbackManifest.forceUpdate),
      apkUrl: this.readString(remoteManifest.apkUrl) || fallbackManifest.apkUrl,
      releaseNotes: this.readString(remoteManifest.releaseNotes) || fallbackManifest.releaseNotes,
      publishedAt: this.readString(remoteManifest.publishedAt) || fallbackManifest.publishedAt,
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

  private getManifestTimeoutMs(): number {
    const value = this.config.get<string>('ANDROID_APP_MANIFEST_TIMEOUT_MS', '5000');
    const parsed = Number.parseInt(value, 10);

    return Number.isFinite(parsed) && parsed > 0 ? parsed : 5000;
  }

  private readString(value: unknown): string | null {
    return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
  }

  private parseBoolean(value: unknown, fallback = false): boolean {
    if (typeof value === 'boolean') {
      return value;
    }

    if (typeof value === 'number') {
      return value !== 0;
    }

    if (typeof value === 'string') {
      return ['true', '1', 'yes', 'on'].includes(value.toLowerCase().trim());
    }

    return fallback;
  }
}
