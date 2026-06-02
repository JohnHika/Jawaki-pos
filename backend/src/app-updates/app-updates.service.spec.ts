import axios from 'axios';
import { ConfigService } from '@nestjs/config';
import { AppUpdatesService } from './app-updates.service';

describe('AppUpdatesService', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('returns the local env manifest when no remote manifest url is configured', async () => {
    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_LATEST_VERSION: '1.0.2',
        ANDROID_APP_MIN_SUPPORTED_VERSION: '1.0.1',
        ANDROID_APP_FORCE_UPDATE: 'false',
        ANDROID_APP_APK_URL: 'https://downloads.example.com/app-release.apk',
        ANDROID_APP_RELEASE_NOTES: 'Local fallback manifest',
        ANDROID_APP_PUBLISHED_AT: '2026-06-02T12:00:00Z',
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toEqual({
      platform: 'android',
      latestVersion: '1.0.2',
      minSupportedVersion: '1.0.1',
      forceUpdate: false,
      apkUrl: 'https://downloads.example.com/app-release.apk',
      releaseNotes: 'Local fallback manifest',
      publishedAt: '2026-06-02T12:00:00Z',
    });
  });

  it('uses the remote manifest when ANDROID_APP_MANIFEST_URL is configured', async () => {
    jest.spyOn(axios, 'get').mockResolvedValue({
      data: {
        latestVersion: '1.0.4',
        minSupportedVersion: '1.0.2',
        forceUpdate: true,
        apkUrl: 'https://pub.example.r2.dev/releases/1.0.4/app-release.apk',
        releaseNotes: 'Published from R2',
        publishedAt: '2026-06-03T08:30:00Z',
      },
    } as never);

    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_MANIFEST_URL: 'https://pub.example.r2.dev/android/latest.json',
        ANDROID_APP_LATEST_VERSION: '1.0.2',
        ANDROID_APP_MIN_SUPPORTED_VERSION: '1.0.1',
        ANDROID_APP_FORCE_UPDATE: 'false',
        ANDROID_APP_APK_URL: 'https://downloads.example.com/app-release.apk',
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toEqual({
      platform: 'android',
      latestVersion: '1.0.4',
      minSupportedVersion: '1.0.2',
      forceUpdate: true,
      apkUrl: 'https://pub.example.r2.dev/releases/1.0.4/app-release.apk',
      releaseNotes: 'Published from R2',
      publishedAt: '2026-06-03T08:30:00Z',
    });
  });

  it('falls back to the local env manifest when the remote manifest fetch fails', async () => {
    jest.spyOn(axios, 'get').mockRejectedValue(new Error('network down'));

    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_MANIFEST_URL: 'https://pub.example.r2.dev/android/latest.json',
        ANDROID_APP_LATEST_VERSION: '1.0.3',
        ANDROID_APP_MIN_SUPPORTED_VERSION: '1.0.2',
        ANDROID_APP_FORCE_UPDATE: 'true',
        ANDROID_APP_APK_URL: 'https://downloads.example.com/app-release.apk',
        ANDROID_APP_RELEASE_NOTES: 'Fallback after remote error',
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toEqual({
      platform: 'android',
      latestVersion: '1.0.3',
      minSupportedVersion: '1.0.2',
      forceUpdate: true,
      apkUrl: 'https://downloads.example.com/app-release.apk',
      releaseNotes: 'Fallback after remote error',
      publishedAt: null,
    });
  });
});

function createConfigService(values: Record<string, string>): ConfigService {
  return {
    get: jest.fn((key: string, defaultValue?: string) => values[key] ?? defaultValue),
  } as unknown as ConfigService;
}
