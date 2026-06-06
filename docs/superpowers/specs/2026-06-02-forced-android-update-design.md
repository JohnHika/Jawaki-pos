# Forced Android APK Update Design

Date: 2026-06-02

## Goal

Provide a required remote update flow for client phones that receive the POS app as a direct APK, not through Google Play.

## Constraints

- Client phones are already in the field.
- Distribution is direct APK.
- Updates must be required when the installed version is below the configured minimum supported version.
- The client can do a one-time Android setup to allow installing unknown apps.
- Android still requires the user to confirm the package installer; true silent install is out of scope for unmanaged phones.

## Recommended approach

Implement a forced in-app updater backed by a backend-managed Android update manifest.

## Backend design

Expose a public versioned endpoint:

- `GET /api/v1/app-updates/android/latest`

Response fields:

- `latestVersion`
- `minSupportedVersion`
- `forceUpdate`
- `apkUrl`
- `releaseNotes`
- `publishedAt`

These values are provided through backend environment variables so releases can be changed without mobile code edits.

## Mobile design

Replace the current GitHub-release-only update check with a service that:

1. fetches the update manifest from the backend,
2. compares the installed version with `latestVersion` and `minSupportedVersion`,
3. raises a blocking state when the app is below the minimum supported version,
4. downloads the APK locally,
5. launches the Android installer,
6. re-checks on resume or app relaunch.

The required update is shown as a full-screen blocking gate overlay, not a dismissible dialog.

## Android support

Android manifest must allow package installs:

- `android.permission.REQUEST_INSTALL_PACKAGES`

The app must expose installer helpers through the Android activity:

- check whether the app can request package installs,
- open the Android "Install unknown apps" settings page for this package.

## UX

The forced update gate must show:

- current version
- required/latest version
- release notes
- download/install progress
- clear instructions when Android install permission is missing

There is no "Later" action for required updates.

## Data flow

1. App starts.
2. Mobile service requests update manifest from backend.
3. If current version is unsupported, the app overlays a required-update screen.
4. User enables install permission if needed.
5. App downloads APK from `apkUrl`.
6. App opens Android installer.
7. Updated app relaunches and passes the version check.

## Error handling

- If the manifest request fails and there is no existing forced-update state, the app continues normally.
- If a forced update is already active and download fails, the gate stays visible and offers retry.
- If installer permission is missing, the gate explains the issue and opens Android settings.
- If the installer cannot be opened, the gate shows an actionable error.

## Testing

- Backend endpoint returns configured values correctly.
- Version comparison handles semantic tags with or without `v` prefix.
- Optional update still works from settings.
- Required update blocks app usage.
- APK download progress is shown.
- Installer permission flow opens Android settings.
- Installer launch works with a downloaded APK.
