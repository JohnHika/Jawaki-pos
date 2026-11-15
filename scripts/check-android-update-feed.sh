#!/usr/bin/env bash
# Checks the Android update feed exactly the way an installed phone uses it:
# read the manifest, download the APK it points at, and prove that file is the
# one the manifest promises and that an installed Counterbase can update to it.
#
# A phone only refuses or silently fails an update for a handful of reasons:
# the download 404s or is cut short, the file is not the expected build, or the
# signature differs from the installed app. This script fails on each of them
# before (publish) or after (scheduled health check) customers can hit them.
#
# Inputs (environment):
#   MANIFEST_URL           manifest to read (default: the public R2 latest.json)
#   MANIFEST_FILE          read this local manifest instead of MANIFEST_URL
#   EXPECTED_BUILD_NUMBER  fail unless the manifest/APK is exactly this build
#   MIN_BUILD_NUMBER       fail unless the build is at least this (health check)
#   DOWNLOAD_ATTEMPTS      tries for the APK download (default 6, 10 s apart:
#                          a release asset can take a few seconds to appear)
#   KEEP_DIR               keep the downloaded files here (default: temp dir)
set -euo pipefail

manifest_url="${MANIFEST_URL:-https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/android/latest.json}"
attempts="${DOWNLOAD_ATTEMPTS:-6}"
work="${KEEP_DIR:-$(mktemp -d)}"
mkdir -p "$work"

fail() {
  echo "::error::Update feed check failed: $1" >&2
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "### Update feed check failed" >> "$GITHUB_STEP_SUMMARY"
    echo "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
}

manifest="$work/latest.json"
if [[ -n "${MANIFEST_FILE:-}" ]]; then
  cp "$MANIFEST_FILE" "$manifest"
else
  curl -fsSL --retry 3 --retry-delay 3 -H 'Cache-Control: no-cache' "$manifest_url" -o "$manifest" \
    || fail "could not read the manifest at $manifest_url"
fi

read_field() {
  python3 - "$manifest" "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
value = data.get(sys.argv[2])
print("" if value is None else value)
PY
}

platform="$(read_field platform)"
build="$(read_field buildNumber)"
apk_url="$(read_field apkUrl)"
sha256_expected="$(read_field apkSha256 | tr '[:upper:]' '[:lower:]')"
size_expected="$(read_field apkSizeBytes)"
force_update="$(read_field forceUpdate)"

[[ "$platform" == "android" ]] || fail "manifest platform is '$platform', expected android"
[[ "$build" =~ ^[0-9]+$ ]] || fail "manifest has no numeric buildNumber"
[[ -n "$apk_url" ]] || fail "manifest has no apkUrl"

# Phones accept only this app's versioned GitHub release asset
# (UpdateCheckService._isTrustedGitHubReleaseAsset): anything else is ignored,
# which looks to a customer like an update that "does nothing".
if ! [[ "$apk_url" =~ ^https://github\.com/[^/]+/[^/]+/releases/download/[^/]+/app-release\.apk$ ]]; then
  fail "apkUrl '$apk_url' is not a GitHub release asset named app-release.apk, so phones would ignore it"
fi

if [[ -n "${EXPECTED_BUILD_NUMBER:-}" && "$build" != "$EXPECTED_BUILD_NUMBER" ]]; then
  fail "manifest build is $build but this release is $EXPECTED_BUILD_NUMBER"
fi
if [[ -n "${MIN_BUILD_NUMBER:-}" ]] && (( build < MIN_BUILD_NUMBER )); then
  fail "manifest build $build is older than the minimum $MIN_BUILD_NUMBER"
fi

apk="$work/app-release.apk"
ok=""
for ((try = 1; try <= attempts; try++)); do
  rm -f "$apk"
  if curl -fsSL --connect-timeout 20 --max-time 600 "$apk_url" -o "$apk" 2>"$work/curl.err"; then
    ok=1
    break
  fi
  echo "download attempt $try/$attempts failed: $(tr -d '\r\n' < "$work/curl.err")" >&2
  sleep 10
done
[[ -n "$ok" ]] || fail "the APK could not be downloaded from $apk_url after $attempts tries"

actual_size="$(wc -c < "$apk" | tr -d ' ')"
actual_sha="$(sha256sum "$apk" | cut -d' ' -f1)"
(( actual_size > 1000000 )) || fail "the downloaded APK is only $actual_size bytes"

if [[ -n "$size_expected" && "$actual_size" != "$size_expected" ]]; then
  fail "downloaded $actual_size bytes but the manifest promises $size_expected"
fi
if [[ -n "$sha256_expected" && "$actual_sha" != "$sha256_expected" ]]; then
  fail "downloaded file checksum $actual_sha does not match the manifest $sha256_expected"
fi

# Package id, production signing certificate, no debug signature, and the
# versionCode must be exactly the build the manifest announces.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_PATH="$apk" MIN_ANDROID_VERSION_CODE="$((build - 1))" bash "$script_dir/verify-android-release.sh" \
  > "$work/verify.out" 2>&1 || { cat "$work/verify.out" >&2; fail "the APK is not a valid production build"; }
code="$(sed -n 's/^- versionCode: //p' "$work/verify.out")"
[[ "$code" == "$build" ]] || fail "the APK is build $code but the manifest says $build"

echo "Update feed healthy:"
echo "- manifest: ${MANIFEST_FILE:-$manifest_url}"
echo "- build: $build (forceUpdate=$force_update)"
echo "- apk: $apk_url"
echo "- size: $actual_size bytes, sha256 $actual_sha"
cat "$work/verify.out"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Update feed healthy"
    echo "- build \`$build\`, $actual_size bytes"
    echo "- sha256 \`$actual_sha\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
