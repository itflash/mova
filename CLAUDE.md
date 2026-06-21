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
- Current version: `1.0.4+2005`

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
- Release builds currently keep `isMinifyEnabled = false` and `isShrinkResources = false`
- Reason: the clip-page video preview once lost the `video_player_android` Pigeon channel under release + R8; debug playback was normal but release playback failed
- If you ever re-enable R8, verify keep rules and test a real Android release APK on-device before shipping

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

## Packaging (打包)

用户说“打包”时，从 `mova` 仓库根目录执行 release 构建：

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter build apk --release --split-per-abi
```

- 产物目录：`build/app/outputs/flutter-apk/`
- 主流手机装 `app-arm64-v8a-release.apk`，老设备装 `app-armeabi-v7a-release.apk`，模拟器装 `app-x86_64-release.apk`
- 构建前确认 `android/key.properties` 与 `android/release.keystore` 存在，否则会回退到 debug 签名
- 升版本号时同步改 `pubspec.yaml` 的 `version: x.y.z+N`，打 tag 用 `git tag vx.y.z`

## Scope Discipline

- Default to the `mova` repo for all active work
- Do not package from `if-movia` unless the user explicitly asks
- Re-check environment on every new chat, even if these notes seem up to date

## iOS Device Launch & Install

iPad/iPhone 连接后，先确认设备被识别：

```bash
<FLUTTER_BIN> devices
```

### Debug 模式（开发调试，需要 flutter tooling 连着）

```bash
<FLUTTER_BIN> run -d <device-id>
```

- iOS 14+ 的 debug 包是 JIT 模式，必须从 flutter tooling 启动，不能在 Xcode 里直接 Run，也不能从主屏图标点开
- 首次冷启动可能白屏（Flutter 3.44 implicit engine + scene-based 配置在部分设备上首次 attach 较慢），按 `R` 热重启即可恢复
- `r` 热重载，`R` 热重启，`d` detach（app 留在设备上运行），`q` 退出

### Release 模式（独立运行，iPad 上点图标就能开）

构建：

```bash
<FLUTTER_BIN> build ios --release
```

手动安装到设备（不走 flutter run 的 install 管道，避免 devicectl hang）：

```bash
xcrun devicectl device install app --device <device-id> build/ios/iphoneos/Runner.app
```

装完直接在 iPad 主屏点图标启动，不依赖电脑连接。

### Profile 模式（接近 release 性能，保留调试能力）

```bash
<FLUTTER_BIN> run --profile -d <device-id>
```

### 常见问题

- **设备未配对**：Xcode → Window → Devices and Simulators，选设备，iPad 上点「信任」并输配对码
- **No development certificates**：Xcode → Runner target → Signing & Capabilities，Team 选个人免费团队，勾 Automatically manage signing，⌘R 跑一次让 Xcode 自动注册设备
- **Podfile.lock not in sync**：`cd ios && pod install`
- **devicectl install hang**：杀掉残留的 `devicectl` 进程后单独执行安装命令
- 当前 iPad UDID：`00008020-00041CAC11F9002E`（iPad mini 5, iOS 26.5）
- 签名团队 ID：`TJCWGB5D2K`（个人免费团队，Apple ID: 609086479@qq.com）

### iOS 签名注意事项

- 免费个人团队即可安装到自己设备，不需要付费 Apple Developer Program
- 免费账号每 7 天签名过期，过期后需重新 build+install
- 免费账号同时在 `developer.apple.com/account` 没有 Devices 注册入口，设备注册由 Xcode 首次运行自动完成
- 首次安装后在 iPad 上：设置 → 通用 → VPN与设备管理 → 信任开发者证书
