# CLAUDE.md

## First Rule For Any New Chat

Re-scan the local environment first. Do not trust prior session memory.

This project has already hit issues where:

- `flutter` was not in `PATH`
- the wrong repo was used for packaging
- previous build assumptions were stale

So every new conversation should start with environment discovery.

## Quick Start

Project root:

```bash
/Users/jbrains/projects/apps/mova
```

Required first checks:

```bash
pwd
git status --short --branch
git remote -v
command -v flutter || find /Users/jbrains -path '*/bin/flutter' -type f 2>/dev/null | head -n 5
sed -n '1,80p' pubspec.yaml
```

If needed, verify toolchain and devices:

```bash
<FLUTTER_BIN> doctor -v
<FLUTTER_BIN> devices
```

## Known Current Project Facts

- Flutter app name: `mova`
- Android application id: `com.jbrains.mova`
- iOS bundle id: `com.jbrains.mova`
- Git remote: `git@github.com:itflash/mova.git`
- Current version: `1.0.0+1`

Known last working Flutter binary:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter
```

Treat that as a hint, not a guarantee.

## Build / Verify

Analyze:

```bash
<FLUTTER_BIN> dart analyze
```

Run:

```bash
<FLUTTER_BIN> run
```

Release package:

```bash
<FLUTTER_BIN> build apk --release --split-per-abi
```

ARM64-only release package:

```bash
<FLUTTER_BIN> build apk --release --split-per-abi --target-platform android-arm64
```

APK output:

```bash
build/app/outputs/flutter-apk/
```

## Android Release Signing

- Release signing is configured in `android/app/build.gradle.kts`
- Preferred signing source is `android/key.properties`
- If signing files are missing, release builds fall back to debug signing

Local signing files:

```bash
android/release.keystore
android/key.properties
android/key.properties.example
```

Expected `android/key.properties` shape:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=release.keystore
```

GitHub Actions uses these secrets for Android release signing:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

- The workflow reconstructs `android/release.keystore` and `android/key.properties` during CI
- Matching local and GitHub release signatures require using the same keystore material in both places
- Never commit real `key.properties`, `.jks`, or `.keystore` files

## Scope Discipline

- Default to the `mova` repo for all active work
- Do not package from `if-movia` unless the user explicitly asks
- Re-check environment on every new chat, even if these notes seem up to date
