# AGENTS.md

## Project Identity

- Canonical project: `/Users/jbrains/projects/apps/mova`
- Project type: Flutter mobile app
- Git remote: `git@github.com:itflash/mova.git`
- Current app/package id:
  - Android: `com.jbrains.mova`
  - iOS bundle id: `com.jbrains.mova`
- App version in `pubspec.yaml`: `1.0.0+1`

## Important Working Rule

Every new conversation must re-discover the local development environment before making assumptions.

Do not assume:

- `flutter` is available in `PATH`
- `dart` is available in `PATH`
- emulator/device state is unchanged
- build artifacts from a previous session are still valid
- the active repo is still the old `if-movia` project

Always verify the environment again at the start of a new session.

## Canonical Repo Choice

- Build, run, package, and submit changes in `apps/mova`
- Do not default to `apps/if-movia`
- Only touch the old repo when the user explicitly asks

## New Session Bootstrap Checklist

Run these checks at the beginning of every new conversation:

```bash
pwd
git status --short --branch
git remote -v
```

Verify Flutter/Dart instead of assuming:

```bash
command -v flutter || find /Users/jbrains -path '*/bin/flutter' -type f 2>/dev/null | head -n 5
command -v dart || true
```

Last known Flutter SDK path was:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter
```

But this path must still be re-checked in each new session.

If Flutter is not in `PATH`, use the discovered absolute path for all commands.

Confirm project metadata:

```bash
sed -n '1,80p' pubspec.yaml
```

If runtime/device validation is needed, also check:

```bash
<FLUTTER_BIN> doctor -v
<FLUTTER_BIN> devices
```

## Common Commands

Analyze:

```bash
<FLUTTER_BIN> dart analyze
```

Run app:

```bash
<FLUTTER_BIN> run
```

Build Android release APKs:

```bash
<FLUTTER_BIN> build apk --release --split-per-abi
```

Build Android release APK for ARM64 only:

```bash
<FLUTTER_BIN> build apk --release --split-per-abi --target-platform android-arm64
```

Common output directory:

```bash
build/app/outputs/flutter-apk/
```

## Android Release Signing

- `android/app/build.gradle.kts` now prefers release signing from `android/key.properties`
- If `android/key.properties` or the referenced keystore is missing, release builds fall back to debug signing
- Local release keystore path:

```bash
android/release.keystore
```

- Local signing config path:

```bash
android/key.properties
```

- Example config template:

```bash
android/key.properties.example
```

- `android/key.properties`, `android/*.jks`, and `android/*.keystore` are gitignored and must not be committed

Expected `android/key.properties` format:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=release.keystore
```

GitHub Actions Android release signing secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

- GitHub workflow writes `android/release.keystore` and `android/key.properties` at build time from those secrets
- If the same keystore is used locally and in GitHub Actions, release APK signatures will match

## Repo Notes

- The repo may contain generated folders like `.dart_tool/` and `build/`
- There is a local `.claude/` folder in the repo, but session instructions should live in root-level docs too
- Use `apply_patch` for manual edits
- Prefer `rg` for file/text search

## Change Safety

- Never assume the worktree is clean
- Do not revert unrelated user changes
- Before commit/push, verify:

```bash
git status --short
git diff --stat
```

## Packaging Reminder

When the user says “打包”, package from:

```bash
/Users/jbrains/projects/apps/mova
```

not from the legacy `if-movia` repo.
