# AGENTS.md

## Project Identity

- Canonical project: `/Users/jbrains/projects/apps/mova`
- Project type: Flutter mobile app
- Git remote: `git@github.com:itflash/mova.git`
- Current app/package id:
  - Android: `com.jbrains.mova`
  - iOS bundle id: `com.jbrains.mova`
- App version in `pubspec.yaml`: `1.0.4+2005`

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

打包前先确认签名文件就位（缺失会回退 debug 签名）：

```bash
ls -l android/key.properties android/release.keystore
```

完整打包流程（实际使用的 Flutter 绝对路径，若 `flutter` 不在 `PATH`）：

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter build apk --release --split-per-abi
```

产物（正式签名）：

- `app-arm64-v8a-release.apk`（主流手机，约 65MB）
- `app-armeabi-v7a-release.apk`（老设备，约 98MB）
- `app-x86_64-release.apk`（模拟器，约 72MB）

版本升级与 tag（升级时同步更新 `pubspec.yaml` 的 `version` 与 build number，例如 `1.0.4+2005`）：

```bash
git commit -am "chore: 版本升级到 1.0.4"
git tag v1.0.4
git push origin codex/perf-and-leak-fixes
git push origin v1.0.4
```

## Android Release Signing

- `android/app/build.gradle.kts` now prefers release signing from `android/key.properties`
- If `android/key.properties` or the referenced keystore is missing, release builds fall back to debug signing
- Release build types currently disable `isMinifyEnabled` and `isShrinkResources`
- Keep that in mind before changing Android release optimization settings: the clip-page video preview once failed only in release because `video_player_android` lost its Pigeon channel after R8
- If release optimization is reintroduced, verify the clip page on a real Android release APK, not only with `flutter run`
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

## iOS Device Run & Install

iPad mini 5 (UDID: `00008020-00041CAC11F9002E`) 已注册到个人开发者团队 `TJCWGB5D2K` (Apple ID: 609086479@qq.com)。签名走免费个人团队（Personal Team），不需要付费 Apple Developer Program。

### Debug 模式（开发调试，支持热重载）

iOS 14+ 的 debug 包是 JIT 模式，必须从 flutter tooling 启动，不能直接在 Xcode 或 iPad 主屏点图标开：

```bash
<FLUTTER_BIN> run -d 00008020-00041CAC11F9002E
```

热重载 `r`，热重启 `R`。首次冷启如果白屏，按 `R` 热重启即可恢复（Flutter 3.44 implicit engine + scene-based 配置在较老设备上的已知现象）。

### Release / Profile 模式（独立运行，不依赖电脑）

AOT 编译，装完直接在 iPad 主屏点图标启动：

```bash
# 构建
<FLUTTER_BIN> build ios --release

# 手动安装到设备
xcrun devicectl device install app --device 00008020-00041CAC11F9002E build/ios/iphoneos/Runner.app
```

也可以用 `flutter run --release` 装完按 `d` detach，app 会继续跑。

### 注意事项

- `devicectl device install app` 在 flutter run 管道里偶尔会 hang；单独在终端跑该命令更稳
- 首次安装需在 iPad 上信任开发者证书：设置 → 通用 → VPN与设备管理 → 609086479@qq.com → 信任
- 免费个人团队的签名 7 天后会过期，过期后需重新 build+install
- 若报 "No valid code signing certificates"，在 Xcode → Signing & Capabilities 确认 Team 选了 Personal Team，用 Xcode 跑一次让它自动生成证书和描述文件
- `pod install` 需在 `ios/` 目录下执行，CocoaPods 路径 `/opt/homebrew/bin/pod`
