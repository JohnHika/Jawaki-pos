# Cloudflare R2 Android Update Automation

This repo now supports automatic Android update publishing to Cloudflare R2.

## What happens now

- Every push to `main` builds the Android APK.
- The workflow uploads the APK to Cloudflare R2.
- The workflow generates and uploads `android/latest.json`.
- The backend reads that manifest through `ANDROID_APP_MANIFEST_URL`.
- Mobile clients keep calling the same backend endpoint: `GET /api/v1/app-updates/android/latest`.

That means you no longer need to:

- manually upload each APK to R2
- manually change Render env vars for each release
- publish GitHub Releases just for the updater

## One-time setup

### 0. Where to put these values in GitHub

In your GitHub repo, go to:

- `Settings`
- `Secrets and variables`
- `Actions`

Use **repository-level** secrets and variables here.

Do **not** use GitHub Environment secrets for this setup unless the workflow is explicitly changed to target a GitHub environment.

Then add the values in these two places:

- **Secrets**
  - `CF_ACCOUNT_ID`
  - `CF_R2_ACCESS_KEY_ID`
  - `CF_R2_SECRET_ACCESS_KEY`
- **Variables**
  - `CF_R2_BUCKET`
  - `R2_PUBLIC_BASE_URL`

## Exact values to add

### GitHub Secrets

#### `CF_ACCOUNT_ID`

Where to get it in Cloudflare:

1. Open the Cloudflare dashboard.
2. Make sure you are inside the correct Cloudflare account.
3. Go to the account home / overview area.
4. Copy the **Account ID** shown in the dashboard sidebar/account details area.

Use that full value as:

- `CF_ACCOUNT_ID=<your-cloudflare-account-id>`

#### `CF_R2_ACCESS_KEY_ID`

Where to get it in Cloudflare:

1. Open Cloudflare.
2. Go to `R2`.
3. Open the R2 API token / API keys area.
4. Create an API token for R2 object storage access if you have not created one yet.
5. Copy the **Access Key ID**.

Use that as:

- `CF_R2_ACCESS_KEY_ID=<access-key-id>`

#### `CF_R2_SECRET_ACCESS_KEY`

Where to get it in Cloudflare:

1. In the same R2 API token creation screen, copy the **Secret Access Key**.
2. Save it immediately.

Important:

- Cloudflare typically shows the secret only once when the token is created.
- If you lose it, create a new key pair.

Use that as:

- `CF_R2_SECRET_ACCESS_KEY=<secret-access-key>`

### GitHub Variables

#### `CF_R2_BUCKET`

Use your bucket name.

For this repo, the bucket is:

- `CF_R2_BUCKET=pos-updates`

#### `R2_PUBLIC_BASE_URL`

Where to get it in Cloudflare:

1. Open Cloudflare.
2. Go to `R2`.
3. Open your bucket: `pos-updates`.
4. Open the bucket settings/details page.
5. Copy the public `r2.dev` URL for the bucket.

For your current setup, use:

- `R2_PUBLIC_BASE_URL=https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev`

### 1. Render backend env

Set this in the backend environment:

- `ANDROID_APP_MANIFEST_URL=https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/android/latest.json`

Optional:

- `ANDROID_APP_MANIFEST_TIMEOUT_MS=5000`

The older `ANDROID_APP_*` env vars still work as a fallback if the remote manifest is unavailable.

### 2. GitHub repository secrets

Add these repository secrets:

- `CF_ACCOUNT_ID`
- `CF_R2_ACCESS_KEY_ID`
- `CF_R2_SECRET_ACCESS_KEY`

Quick summary:

- `CF_ACCOUNT_ID` = your Cloudflare account ID
- `CF_R2_ACCESS_KEY_ID` = R2 API Access Key ID
- `CF_R2_SECRET_ACCESS_KEY` = R2 API Secret Access Key

### 3. GitHub repository variables

Add these repository variables:

- `CF_R2_BUCKET=pos-updates`
- `R2_PUBLIC_BASE_URL=https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev`

Quick summary:

- `CF_R2_BUCKET` = your R2 bucket name
- `R2_PUBLIC_BASE_URL` = the public base URL of that bucket

## Copy/paste checklist

### GitHub → Secrets → Actions

Add:

- `CF_ACCOUNT_ID`
- `CF_R2_ACCESS_KEY_ID`
- `CF_R2_SECRET_ACCESS_KEY`

### GitHub → Variables → Actions

Add:

- `CF_R2_BUCKET=pos-updates`
- `R2_PUBLIC_BASE_URL=https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev`

### Render backend env

Add:

- `ANDROID_APP_MANIFEST_URL=https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/android/latest.json`

## Publish behavior

### Automatic publish

- Trigger: push to `main`
- Result: publishes an optional update automatically
- APK path pattern:
  - `https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/releases/<semantic-version>/<build-number>/app-release.apk`
- Manifest path:
  - `https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/android/latest.json`

### Manual publish with force-update options

You can also run the workflow manually and optionally provide:

- `release_notes`
- `force_update=true`
- `min_supported_version`

Use manual dispatch when you want to force a rollout without changing the workflow itself.

## Important versioning note

The updater now compares both:

- semantic version
- build number

So a build like `1.0.2+2004` is treated as newer than `1.0.2+2003`.

Because of that, automatic publishing works for every new build as long as your Flutter build number increases.

## Recommended release habit

For each client-facing Android release:

1. bump the Flutter version/build in `mobile/pubspec.yaml`
2. merge or push to `main`
3. let GitHub Actions publish the APK + manifest
4. users receive the new update through the existing in-app updater

## Rollback

If you need to roll back fast:

1. re-run the workflow from an older commit or branch state, or
2. upload an older APK/manifest pair to the same R2 paths

Because clients resolve updates through `android/latest.json`, whichever manifest is currently there becomes the active release channel.
