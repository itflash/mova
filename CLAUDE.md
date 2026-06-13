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

APK output:

```bash
build/app/outputs/flutter-apk/
```

## Scope Discipline

- Default to the `mova` repo for all active work
- Do not package from `if-movia` unless the user explicitly asks
- Re-check environment on every new chat, even if these notes seem up to date
