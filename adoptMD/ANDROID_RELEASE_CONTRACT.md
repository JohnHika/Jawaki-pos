# Android Release Contract

This contract protects installed customer devices from APKs that cannot update in place. Any release automation or AI coding agent must treat these rules as blocking requirements.

## Canonical Customer Line

- Package id: `com.archeaxon.axonpos`
- Production signing certificate SHA-256: `0289d757a110883956bc03faeedc3c281d1eb685b98d9bfbad533a9b0d340393`
- Certificate owner: `CN=Axon POS, OU=Mobile, O=Arche Axon Intelligence, L=Nairobi, ST=Nairobi, C=KE`
- Legacy package line: `com.levisaadventures.pos` through the pre-2021 builds;
  those installations cannot update in place to the Axon package.
- Axon package migration boundary: `versionName=1.0.16`, `versionCode=2021`.
- Axon customer baseline: package `com.archeaxon.axonpos`, build `2021` or newer.
- Current safe successor: `versionName=1.0.49`, `versionCode=2059`
- Unsafe quarantined release: `v1.0.14-2017` was debug-signed and must stay prerelease/not-latest.

## Required Successor Rules

1. Every production APK must keep package id `com.archeaxon.axonpos`.
2. Every production APK must be signed by the production certificate above.
3. Never publish an APK signed by the Android Debug certificate.
4. Every successor must use a `versionCode` greater than the currently published build number.
5. Never recreate or publish an older build number as latest, even if the visible `versionName` is lower.
6. Cloudflare R2 publish and manifest validation must succeed before a GitHub Release is created or marked latest.
7. Draft and prerelease GitHub releases are not valid update candidates.

## Version Naming

The visible release line may remain clean, for example `Axon POS 1.0.1`, while older clients may receive a compatibility `latestVersion` that is only used for comparison. The Android `versionCode` is the real release lineage lock.

## Required Verification

Before publish, run:

```bash
APK_PATH=mobile/build/app/outputs/flutter-apk/app-release.apk \
MIN_ANDROID_VERSION_CODE=<current-published-build> \
scripts/verify-android-release.sh
```

The verifier fails if the package id, signing certificate, debug-signing state, or versionCode lineage is wrong.

## Agent Instruction

If a proposed change would publish a release that violates this contract, stop the release, do not push release tags, and report the exact failed rule.
