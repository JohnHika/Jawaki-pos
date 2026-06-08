import axios from "axios";
import { Injectable, Logger, NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { existsSync } from "fs";
import { isAbsolute, resolve } from "path";

type UpdateSource = {
  name: string;
  url: string;
  priority: "primary" | "secondary";
};

type AndroidUpdateManifest = {
  platform: "android";
  latestVersion: string;
  releaseName: string;
  buildNumber: number | null;
  minSupportedVersion: string;
  minSupportedBuildNumber: number | null;
  forceUpdate: boolean;
  apkUrl: string;
  releaseNotes: string;
  publishedAt: string | null;
  updateSources?: UpdateSource[];
};

@Injectable()
export class AppUpdatesService {
  private readonly logger = new Logger(AppUpdatesService.name);

  constructor(private readonly config: ConfigService) {}

  async getLatestAndroidUpdate(): Promise<AndroidUpdateManifest> {
    const fallbackManifest = this.buildLocalAndroidManifest();
    const manifestUrl = this.config
      .get<string>("ANDROID_APP_MANIFEST_URL", "")
      .trim();
    const candidates: AndroidUpdateManifest[] = [fallbackManifest];

    if (manifestUrl) {
      try {
        const response = await axios.get<Record<string, unknown>>(manifestUrl, {
          timeout: this.getManifestTimeoutMs(),
        });

        candidates.push(
          this.mergeRemoteManifest(response.data, fallbackManifest),
        );
      } catch (error) {
        const message =
          error instanceof Error ? error.message : "Unknown error";
        this.logger.warn(
          `Failed to load Android app manifest from ${manifestUrl}. Falling back to local env configuration. ${message}`,
        );
      }
    }

    const githubManifest =
      await this.getLatestGitHubReleaseManifest(fallbackManifest);
    if (githubManifest) {
      candidates.push(githubManifest);
    }

    return candidates.reduce((newest, candidate) =>
      this.isManifestNewer(candidate, newest) ? candidate : newest,
    );
  }

  getAndroidApkDownload() {
    const filePath = this.resolveAndroidApkFilePath();
    if (!filePath) {
      throw new NotFoundException(
        "Android update APK was not found on the server. Build the mobile app or set ANDROID_APP_APK_FILE_PATH.",
      );
    }

    const latestVersion = this.config.get<string>(
      "ANDROID_APP_LATEST_VERSION",
      "1.0.13",
    );
    const releaseName = this.config.get<string>(
      "ANDROID_APP_RELEASE_NAME",
      "Axon POS 1.0",
    );
    const buildNumber = this.readNumber(
      this.config.get<string>("ANDROID_APP_BUILD_NUMBER"),
    );

    return {
      filePath,
      fileName: `pos-${this.safeFileVersion(releaseName, latestVersion, buildNumber)}.apk`,
    };
  }

  private buildLocalAndroidManifest(): AndroidUpdateManifest {
    const latestVersion = this.config.get<string>(
      "ANDROID_APP_LATEST_VERSION",
      "1.0.13",
    );
    const releaseName = this.config.get<string>(
      "ANDROID_APP_RELEASE_NAME",
      "Axon POS 1.0",
    );
    const buildNumber = this.readNumber(
      this.config.get<string>("ANDROID_APP_BUILD_NUMBER"),
    );
    const manifestUrl = this.config
      .get<string>("ANDROID_APP_MANIFEST_URL", "")
      .trim();

    return {
      platform: "android",
      latestVersion,
      releaseName,
      buildNumber,
      minSupportedVersion: this.config.get<string>(
        "ANDROID_APP_MIN_SUPPORTED_VERSION",
        latestVersion,
      ),
      minSupportedBuildNumber: this.readNumber(
        this.config.get<string>("ANDROID_APP_MIN_SUPPORTED_BUILD_NUMBER"),
      ),
      forceUpdate: this.parseBoolean(
        this.config.get<string>("ANDROID_APP_FORCE_UPDATE", "true"),
      ),
      apkUrl: this.config.get<string>(
        "ANDROID_APP_APK_URL",
        "/api/v1/app-updates/android/download",
      ),
      releaseNotes: this.config.get<string>("ANDROID_APP_RELEASE_NOTES", ""),
      publishedAt: this.config.get<string>("ANDROID_APP_PUBLISHED_AT") || null,
      updateSources: manifestUrl
        ? [
            {
              name: "Cloudflare R2",
              url: manifestUrl,
              priority: "primary",
            },
          ]
        : undefined,
    };
  }

  private mergeRemoteManifest(
    remoteManifest: Record<string, unknown>,
    fallbackManifest: AndroidUpdateManifest,
  ): AndroidUpdateManifest {
    const latestVersion =
      this.readString(remoteManifest.latestVersion) ||
      fallbackManifest.latestVersion;
    const releaseName =
      this.readString(remoteManifest.releaseName) ||
      this.readString(remoteManifest.displayVersion) ||
      fallbackManifest.releaseName;
    const buildNumber =
      this.readNumber(remoteManifest.buildNumber) ??
      fallbackManifest.buildNumber;

    return {
      platform: "android",
      latestVersion,
      releaseName,
      buildNumber,
      minSupportedVersion:
        this.readString(remoteManifest.minSupportedVersion) ||
        fallbackManifest.minSupportedVersion,
      minSupportedBuildNumber:
        this.readNumber(remoteManifest.minSupportedBuildNumber) ||
        fallbackManifest.minSupportedBuildNumber,
      forceUpdate: this.parseBoolean(
        remoteManifest.forceUpdate,
        fallbackManifest.forceUpdate,
      ),
      apkUrl: this.readString(remoteManifest.apkUrl) || fallbackManifest.apkUrl,
      releaseNotes:
        this.readString(remoteManifest.releaseNotes) ||
        fallbackManifest.releaseNotes,
      publishedAt:
        this.readString(remoteManifest.publishedAt) ||
        fallbackManifest.publishedAt,
      updateSources: this.buildUpdateSources(
        this.readString(remoteManifest.apkUrl),
        fallbackManifest.apkUrl,
      ),
    };
  }

  private buildUpdateSources(
    primaryApkUrl: string | null,
    fallbackApkUrl: string,
  ): UpdateSource[] {
    const manifestUrl = this.config
      .get<string>("ANDROID_APP_MANIFEST_URL", "")
      .trim();
    const githubRepo = this.config.get<string>(
      "GITHUB_REPO",
      "JohnHika/Jawaki-pos",
    );

    const sources: UpdateSource[] = [];

    if (manifestUrl) {
      sources.push({
        name: "Cloudflare R2",
        url: manifestUrl,
        priority: "primary",
      });
    }

    // Add GitHub Packages as secondary source
    sources.push({
      name: "GitHub Packages",
      url: `https://github.com/${githubRepo}/releases`,
      priority: "secondary",
    });

    return sources;
  }

  private async getLatestGitHubReleaseManifest(
    fallbackManifest: AndroidUpdateManifest,
  ): Promise<AndroidUpdateManifest | null> {
    const releasesUrl = this.getGitHubReleasesApiUrl();
    if (!releasesUrl) {
      return null;
    }

    try {
      const response = await axios.get<unknown[]>(releasesUrl, {
        timeout: this.getManifestTimeoutMs(),
        headers: { Accept: "application/vnd.github+json" },
      });
      const releases = Array.isArray(response.data) ? response.data : [];

      for (const release of releases) {
        const manifest = this.githubReleaseToManifest(
          release as Record<string, unknown>,
          fallbackManifest,
        );
        if (manifest) {
          return manifest;
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      this.logger.warn(
        `Failed to load GitHub Android releases from ${releasesUrl}. ${message}`,
      );
    }

    return null;
  }

  private githubReleaseToManifest(
    release: Record<string, unknown>,
    fallbackManifest: AndroidUpdateManifest,
  ): AndroidUpdateManifest | null {
    const assets = Array.isArray(release.assets) ? release.assets : [];
    const apkAsset = assets
      .filter((asset): asset is Record<string, unknown> => Boolean(asset))
      .find((asset) => this.readString(asset.name)?.endsWith(".apk"));

    if (!apkAsset) {
      return null;
    }

    const tagName = this.readString(release.tag_name);
    const parsed = this.parseReleaseVersion(tagName || "");
    const apkUrl = this.readString(apkAsset.browser_download_url);

    if (!parsed.latestVersion || !apkUrl) {
      return null;
    }

    return {
      platform: "android",
      latestVersion: parsed.latestVersion,
      releaseName:
        this.readString(release.name) ||
        fallbackManifest.releaseName ||
        parsed.latestVersion,
      buildNumber: parsed.buildNumber,
      minSupportedVersion: fallbackManifest.minSupportedVersion,
      minSupportedBuildNumber: fallbackManifest.minSupportedBuildNumber,
      forceUpdate: fallbackManifest.forceUpdate,
      apkUrl,
      releaseNotes:
        this.readString(release.body) || fallbackManifest.releaseNotes,
      publishedAt:
        this.readString(release.published_at) || fallbackManifest.publishedAt,
      updateSources: this.buildUpdateSources(null, apkUrl),
    };
  }

  private getGitHubReleasesApiUrl(): string | null {
    const configured = this.config
      .get<string>("ANDROID_APP_GITHUB_RELEASES_URL", "")
      .trim();
    if (
      ["false", "none", "off", "disabled"].includes(configured.toLowerCase())
    ) {
      return null;
    }

    if (configured) {
      return configured;
    }

    const githubRepo = this.config.get<string>(
      "GITHUB_REPO",
      "JohnHika/Jawaki-pos",
    );

    return `https://api.github.com/repos/${githubRepo}/releases`;
  }

  private parseReleaseVersion(tagName: string): {
    latestVersion: string | null;
    buildNumber: number | null;
  } {
    const normalized = tagName.trim().replace(/^v/i, "");
    const match = normalized.match(/^(\d+\.\d+\.\d+)(?:[+-](\d+))?$/);
    if (!match) {
      return { latestVersion: null, buildNumber: null };
    }

    return {
      latestVersion: match[1],
      buildNumber: this.readNumber(match[2]),
    };
  }

  private isManifestNewer(
    candidate: AndroidUpdateManifest,
    current: AndroidUpdateManifest,
  ): boolean {
    if (candidate.buildNumber && current.buildNumber) {
      return candidate.buildNumber > current.buildNumber;
    }

    return this.isVersionNewer(candidate.latestVersion, current.latestVersion);
  }

  private isVersionNewer(candidate: string, current: string): boolean {
    const candidateParts = this.versionParts(candidate);
    const currentParts = this.versionParts(current);
    const length = Math.max(candidateParts.length, currentParts.length);

    for (let index = 0; index < length; index += 1) {
      const candidatePart = candidateParts[index] || 0;
      const currentPart = currentParts[index] || 0;
      if (candidatePart > currentPart) return true;
      if (candidatePart < currentPart) return false;
    }

    return false;
  }

  private versionParts(version: string): number[] {
    return version
      .trim()
      .replace(/^v/i, "")
      .replace(/[+-]/g, ".")
      .split(".")
      .map((part) => Number.parseInt(part, 10))
      .filter((part) => Number.isFinite(part));
  }

  private resolveAndroidApkFilePath(): string | null {
    const configuredPath = this.config
      .get<string>("ANDROID_APP_APK_FILE_PATH")
      ?.trim();

    const candidates = [
      configuredPath
        ? isAbsolute(configuredPath)
          ? configuredPath
          : resolve(process.cwd(), configuredPath)
        : null,
      resolve(process.cwd(), "public", "downloads", "pos-latest.apk"),
      resolve(
        process.cwd(),
        "..",
        "mobile",
        "build",
        "app",
        "outputs",
        "flutter-apk",
        "app-release.apk",
      ),
    ].filter((value): value is string => Boolean(value));

    return candidates.find((candidate) => existsSync(candidate)) ?? null;
  }

  private getManifestTimeoutMs(): number {
    const value = this.config.get<string>(
      "ANDROID_APP_MANIFEST_TIMEOUT_MS",
      "5000",
    );
    const parsed = Number.parseInt(value, 10);

    return Number.isFinite(parsed) && parsed > 0 ? parsed : 5000;
  }

  private readString(value: unknown): string | null {
    return typeof value === "string" && value.trim().length > 0
      ? value.trim()
      : null;
  }

  private readNumber(value: unknown): number | null {
    if (value === null || value === undefined || value === "") {
      return null;
    }

    const parsed = Number.parseInt(String(value).trim(), 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  }

  private safeFileVersion(
    releaseName: string,
    latestVersion: string,
    buildNumber: number | null,
  ): string {
    const base = releaseName || latestVersion;
    const suffix = buildNumber ? `-${buildNumber}` : "";
    return `${base}${suffix}`
      .replace(/[^a-zA-Z0-9._-]+/g, "-")
      .replace(/^-|-$/g, "");
  }

  private parseBoolean(value: unknown, fallback = false): boolean {
    if (typeof value === "boolean") {
      return value;
    }

    if (typeof value === "number") {
      return value !== 0;
    }

    if (typeof value === "string") {
      return ["true", "1", "yes", "on"].includes(value.toLowerCase().trim());
    }

    return fallback;
  }
}
