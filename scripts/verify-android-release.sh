#!/usr/bin/env bash
set -euo pipefail

apk_path="${APK_PATH:-}"
expected_package="${EXPECTED_ANDROID_PACKAGE:-com.archeaxon.axonpos}"
expected_cert_sha256="${EXPECTED_ANDROID_CERT_SHA256:-0289d757a110883956bc03faeedc3c281d1eb685b98d9bfbad533a9b0d340393}"
min_version_code="${MIN_ANDROID_VERSION_CODE:-}"

fail() {
  echo "::error::$1" >&2
  exit 1
}

find_android_tool() {
  local tool_name="$1"
  local override="${2:-}"

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return
  fi

  if command -v "$tool_name" >/dev/null 2>&1; then
    command -v "$tool_name"
    return
  fi

  local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -n "$sdk_root" ]]; then
    local match
    match="$(find "$sdk_root/build-tools" -type f \( -name "$tool_name" -o -name "$tool_name.bat" -o -name "$tool_name.exe" \) 2>/dev/null | sort -V | tail -n 1 || true)"
    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return
    fi
  fi

  fail "Could not find Android build tool: $tool_name"
}

[[ -n "$apk_path" ]] || fail "APK_PATH is required"
[[ -f "$apk_path" ]] || fail "APK file was not found: $apk_path"

aapt_bin="$(find_android_tool aapt "${AAPT_BIN:-}")"
apksigner_bin="$(find_android_tool apksigner "${APKSIGNER_BIN:-}")"

badging="$("$aapt_bin" dump badging "$apk_path")"
package_name="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging")"
version_code="$(sed -n "s/^package:.* versionCode='\([^']*\)'.*/\1/p" <<<"$badging")"
version_name="$(sed -n "s/^package:.* versionName='\([^']*\)'.*/\1/p" <<<"$badging")"

[[ "$package_name" == "$expected_package" ]] || fail "Package mismatch. Expected $expected_package, got ${package_name:-unknown}"
[[ "$version_code" =~ ^[0-9]+$ ]] || fail "Could not read a numeric versionCode from $apk_path"
[[ -n "$version_name" ]] || fail "Could not read versionName from $apk_path"

if [[ -n "$min_version_code" ]]; then
  [[ "$min_version_code" =~ ^[0-9]+$ ]] || fail "MIN_ANDROID_VERSION_CODE must be numeric when provided"
  if (( version_code <= min_version_code )); then
    fail "versionCode $version_code must be greater than the current published build $min_version_code"
  fi
fi

certs="$("$apksigner_bin" verify --print-certs "$apk_path")"
cert_sha256="$(
  grep -Eio 'SHA-256 digest:[[:space:]]*[a-f0-9:]+' <<<"$certs" \
    | head -n 1 \
    | sed -E 's/.*SHA-256 digest:[[:space:]]*//I; s/://g' \
    | tr '[:upper:]' '[:lower:]'
)"
expected_cert_sha256="$(tr '[:upper:]' '[:lower:]' <<<"$expected_cert_sha256")"

[[ -n "$cert_sha256" ]] || fail "Could not read signing certificate SHA-256 digest from apksigner output"
[[ "$cert_sha256" == "$expected_cert_sha256" ]] || fail "Signing certificate mismatch. Expected $expected_cert_sha256, got ${cert_sha256:-unknown}"

if grep -qi "Android Debug" <<<"$certs"; then
  fail "Release APK is signed with an Android Debug certificate"
fi

echo "Android release verified:"
echo "- package: $package_name"
echo "- versionName: $version_name"
echo "- versionCode: $version_code"
echo "- certificate SHA-256: $cert_sha256"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "package_name=$package_name"
    echo "version_name=$version_name"
    echo "version_code=$version_code"
    echo "certificate_sha256=$cert_sha256"
  } >> "$GITHUB_OUTPUT"
fi
