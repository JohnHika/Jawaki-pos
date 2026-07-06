import axios from "axios";
import { ConfigService } from "@nestjs/config";
import { AppUpdatesService } from "./app-updates.service";

describe("AppUpdatesService", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("returns the local env manifest when no remote manifest url is configured", async () => {
    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_LATEST_VERSION: "1.0.2",
        ANDROID_APP_RELEASE_NAME: "Axon POS 1.0",
        ANDROID_APP_BUILD_NUMBER: "2002",
        ANDROID_APP_MIN_SUPPORTED_VERSION: "1.0.1",
        ANDROID_APP_MIN_SUPPORTED_BUILD_NUMBER: "2001",
        ANDROID_APP_FORCE_UPDATE: "false",
        ANDROID_APP_APK_URL: "https://downloads.example.com/app-release.apk",
        ANDROID_APP_RELEASE_NOTES: "Local fallback manifest",
        ANDROID_APP_PUBLISHED_AT: "2026-06-02T12:00:00Z",
        ANDROID_APP_GITHUB_RELEASES_URL: "none",
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toEqual({
      platform: "android",
      latestVersion: "1.0.2",
      releaseName: "Axon POS 1.0",
      buildNumber: 2002,
      minSupportedVersion: "1.0.1",
      minSupportedBuildNumber: 2001,
      forceUpdate: false,
      apkUrl: "https://downloads.example.com/app-release.apk",
      releaseNotes: "Local fallback manifest",
      publishedAt: "2026-06-02T12:00:00Z",
    });
  });

  it("uses the remote manifest when ANDROID_APP_MANIFEST_URL is configured", async () => {
    jest.spyOn(axios, "get").mockResolvedValue({
      data: {
        latestVersion: "1.0.4",
        releaseName: "Axon POS 1.0",
        buildNumber: 2004,
        minSupportedVersion: "1.0.2",
        minSupportedBuildNumber: 2002,
        forceUpdate: true,
        apkUrl: "https://pub.example.r2.dev/releases/1.0.4/app-release.apk",
        releaseNotes: "Published from R2",
        publishedAt: "2026-06-03T08:30:00Z",
      },
    } as never);

    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_MANIFEST_URL:
          "https://pub.example.r2.dev/android/latest.json",
        ANDROID_APP_LATEST_VERSION: "1.0.2",
        ANDROID_APP_MIN_SUPPORTED_VERSION: "1.0.1",
        ANDROID_APP_FORCE_UPDATE: "false",
        ANDROID_APP_APK_URL: "https://downloads.example.com/app-release.apk",
        ANDROID_APP_GITHUB_RELEASES_URL: "none",
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toEqual({
      platform: "android",
      latestVersion: "1.0.4",
      releaseName: "Axon POS 1.0",
      buildNumber: 2004,
      minSupportedVersion: "1.0.2",
      minSupportedBuildNumber: 2002,
      forceUpdate: true,
      apkUrl: "https://pub.example.r2.dev/releases/1.0.4/app-release.apk",
      releaseNotes: "Published from R2",
      publishedAt: "2026-06-03T08:30:00Z",
      updateSources: [
        {
          name: "Cloudflare R2",
          url: "https://pub.example.r2.dev/android/latest.json",
          priority: "primary",
        },
        {
          name: "GitHub Packages",
          url: "https://github.com/JohnHika/Jawaki-pos/releases",
          priority: "secondary",
        },
      ],
    });
  });

  it("falls back to the local env manifest when the remote manifest fetch fails", async () => {
    jest.spyOn(axios, "get").mockRejectedValue(new Error("network down"));

    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_MANIFEST_URL:
          "https://pub.example.r2.dev/android/latest.json",
        ANDROID_APP_LATEST_VERSION: "1.0.3",
        ANDROID_APP_RELEASE_NAME: "Axon POS 1.0",
        ANDROID_APP_BUILD_NUMBER: "2003",
        ANDROID_APP_MIN_SUPPORTED_VERSION: "1.0.2",
        ANDROID_APP_MIN_SUPPORTED_BUILD_NUMBER: "2002",
        ANDROID_APP_FORCE_UPDATE: "true",
        ANDROID_APP_APK_URL: "https://downloads.example.com/app-release.apk",
        ANDROID_APP_RELEASE_NOTES: "Fallback after remote error",
        ANDROID_APP_GITHUB_RELEASES_URL: "none",
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toEqual({
      platform: "android",
      latestVersion: "1.0.3",
      releaseName: "Axon POS 1.0",
      buildNumber: 2003,
      minSupportedVersion: "1.0.2",
      minSupportedBuildNumber: 2002,
      forceUpdate: true,
      apkUrl: "https://downloads.example.com/app-release.apk",
      releaseNotes: "Fallback after remote error",
      publishedAt: null,
      updateSources: [
        {
          name: "Cloudflare R2",
          url: "https://pub.example.r2.dev/android/latest.json",
          priority: "primary",
        },
      ],
    });
  });

  it("uses the newest GitHub release when R2 is stale", async () => {
    jest
      .spyOn(axios, "get")
      .mockResolvedValueOnce({
        data: {
          latestVersion: "1.0.13",
          releaseName: "Axon POS 1.0",
          buildNumber: 2015,
          apkUrl:
            "https://pub.example.r2.dev/releases/1.0.0/2015/app-release.apk",
          releaseNotes: "Stale R2 manifest",
          publishedAt: "2026-06-08T16:36:52Z",
        },
      } as never)
      .mockResolvedValueOnce({
        data: [
          {
            tag_name: "v1.0.14-2017",
            name: "Axon POS Android 1.0.14+2017",
            body: "Automated Android build from main.",
            published_at: "2026-06-08T17:47:35Z",
            assets: [
              {
                name: "app-release.apk",
                browser_download_url:
                  "https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.14-2017/app-release.apk",
              },
            ],
          },
        ],
      } as never);

    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_MANIFEST_URL:
          "https://pub.example.r2.dev/android/latest.json",
        ANDROID_APP_GITHUB_RELEASES_URL:
          "https://api.github.com/repos/JohnHika/Jawaki-pos/releases",
        ANDROID_APP_LATEST_VERSION: "1.0.13",
        ANDROID_APP_RELEASE_NAME: "Axon POS 1.0",
        ANDROID_APP_BUILD_NUMBER: "2015",
        ANDROID_APP_MIN_SUPPORTED_VERSION: "0.0.0",
        ANDROID_APP_FORCE_UPDATE: "false",
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toMatchObject({
      platform: "android",
      latestVersion: "1.0.14",
      releaseName: "Axon POS Android 1.0.14+2017",
      buildNumber: 2017,
      apkUrl:
        "https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.14-2017/app-release.apk",
      releaseNotes: "Automated Android build from main.",
      publishedAt: "2026-06-08T17:47:35Z",
    });
  });

  it("ignores draft and prerelease GitHub releases", async () => {
    jest
      .spyOn(axios, "get")
      .mockResolvedValueOnce({
        data: {
          latestVersion: "1.0.13",
          releaseName: "Axon POS 1.0",
          buildNumber: 2016,
          apkUrl:
            "https://pub.example.r2.dev/releases/1.0.0/2016/app-release.apk",
          releaseNotes: "Stale R2 manifest",
          publishedAt: "2026-06-08T16:36:52Z",
        },
      } as never)
      .mockResolvedValueOnce({
        data: [
          {
            tag_name: "v1.0.14-2017",
            name: "Unsafe debug-signed release",
            prerelease: true,
            published_at: "2026-06-08T17:47:35Z",
            assets: [
              {
                name: "app-release.apk",
                browser_download_url:
                  "https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.14-2017/app-release.apk",
              },
            ],
          },
          {
            tag_name: "v1.0.15-2018",
            name: "Draft release",
            draft: true,
            published_at: "2026-06-08T18:47:35Z",
            assets: [
              {
                name: "app-release.apk",
                browser_download_url:
                  "https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.15-2018/app-release.apk",
              },
            ],
          },
        ],
      } as never);

    const service = new AppUpdatesService(
      createConfigService({
        ANDROID_APP_MANIFEST_URL:
          "https://pub.example.r2.dev/android/latest.json",
        ANDROID_APP_GITHUB_RELEASES_URL:
          "https://api.github.com/repos/JohnHika/Jawaki-pos/releases",
        ANDROID_APP_LATEST_VERSION: "1.0.13",
        ANDROID_APP_RELEASE_NAME: "Axon POS 1.0",
        ANDROID_APP_BUILD_NUMBER: "2015",
        ANDROID_APP_MIN_SUPPORTED_VERSION: "0.0.0",
        ANDROID_APP_FORCE_UPDATE: "false",
      }),
    );

    await expect(service.getLatestAndroidUpdate()).resolves.toMatchObject({
      buildNumber: 2016,
      apkUrl:
        "https://pub.example.r2.dev/releases/1.0.0/2016/app-release.apk",
    });
  });
});

function createConfigService(values: Record<string, string>): ConfigService {
  return {
    get: jest.fn(
      (key: string, defaultValue?: string) => values[key] ?? defaultValue,
    ),
  } as unknown as ConfigService;
}
