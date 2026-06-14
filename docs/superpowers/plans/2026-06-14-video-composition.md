# Video Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Android-first local video composition workspace that combines trimmed video clips with optional transitions and BGM, then imports or saves the exported MP4.

**Architecture:** Add focused composition domain models and validation in Dart, then wire them into `AppState` and a new `CompositionPage` reachable from a fifth bottom tab. Flutter calls a `VideoCompositionService` abstraction; the first Android implementation uses a method channel backed by FFmpeg capability, while iOS returns an unsupported error.

**Tech Stack:** Flutter/Dart, Material 3, MethodChannel, Android Kotlin, FFmpegKit-style Android execution, existing app storage/upload/download services, Flutter widget/unit tests.

---

## File Structure

Create:

- `lib/app/composition_models.dart` — pure Dart enums/classes for composition projects, clips, output settings, validation, and export state.
- `lib/services/video_composition_service.dart` — Flutter-facing service interface, method-channel implementation, request/result DTO mapping.
- `lib/pages/composition_page.dart` — top-level `剪辑` tab page and workspace UI.
- `test/composition_models_test.dart` — unit tests for validation, defaults, clip manipulation, and serialization-ready value objects.
- `test/video_composition_service_test.dart` — unit tests for method-channel request payloads and error mapping.
- `test/composition_page_test.dart` — widget tests for tab/page UI, disabled export state, and accessibility labels.

Modify:

- `pubspec.yaml` — add Android FFmpeg dependency after verifying the selected package resolves.
- `lib/app/models.dart` — add `AppTab.composition` and composition-related lightweight source enums only if they need to be shared across existing models.
- `lib/app/mock_data.dart` — add the `剪辑` tab metadata in the desired bottom-nav order.
- `lib/app/app_state.dart` — hold current composition state, persist it, add source localization and export/import/save actions.
- `lib/pages/home_shell.dart` — include `CompositionPage` and fifth `NavigationDestination`.
- `lib/pages/library_page.dart` — add a library video action that sends a video to the composition workspace.
- `lib/pages/tasks_page.dart` — add a task video action that sends a result video to the composition workspace.
- `lib/services/native_file_picker.dart` — add local audio picker support for BGM.
- `android/app/src/main/kotlin/com/jbrains/mova/MainActivity.kt` — add audio picker and `mova/video_composition` channel handlers.
- `android/app/build.gradle.kts` — add the selected FFmpeg Android package.

Do not create unrelated abstractions or redesign existing pages beyond the required entry points.

---

### Task 1: Add Pure Composition Models and Validation

**Files:**
- Create: `lib/app/composition_models.dart`
- Test: `test/composition_models_test.dart`

- [ ] **Step 1: Write failing validation tests**

Create `test/composition_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/composition_models.dart';

void main() {
  group('VideoCompositionProject validation', () {
    test('requires at least one clip', () {
      const project = VideoCompositionProject(
        clips: [],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      );

      expect(project.validationMessages, contains('至少添加 1 个视频片段。'));
      expect(project.canExport, isFalse);
    });

    test('requires each clip end to be after start', () {
      final project = VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file:///tmp/a.mp4',
            fileName: 'A.mp4',
            startMs: 3000,
            endMs: 3000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      );

      expect(project.validationMessages, contains('A.mp4 的结束时间必须晚于开始时间。'));
      expect(project.canExport, isFalse);
    });

    test('requires bgm source when audio mode needs bgm', () {
      final project = VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file:///tmp/a.mp4',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: const CompositionAudioSettings(mode: CompositionAudioMode.bgmOnly),
      );

      expect(project.validationMessages, contains('请选择 BGM 音频。'));
      expect(project.canExport, isFalse);
    });

    test('accepts one valid local clip with defaults', () {
      final project = VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file:///tmp/a.mp4',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      );

      expect(project.validationMessages, isEmpty);
      expect(project.canExport, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_models_test.dart
```

Expected: FAIL because `package:mova/app/composition_models.dart` does not exist.

- [ ] **Step 3: Add minimal composition models**

Create `lib/app/composition_models.dart`:

```dart
enum CompositionSourceType { localFile, attachment, task }

enum CompositionTransitionType { none, fade, crossDissolve, black, whiteFlash }

enum CompositionAudioMode { keepOriginal, muted, originalPlusBgm, bgmOnly }

enum CompositionBgmSourceType { localFile, attachment }

enum CompositionExportStatus { idle, preparing, trimming, composing, writing, success, failure, canceled }

class CompositionClip {
  const CompositionClip({
    required this.id,
    required this.sourceType,
    required this.label,
    required this.localUri,
    required this.fileName,
    required this.startMs,
    required this.endMs,
    this.sourceId,
    this.useOriginalAudio = true,
    this.transitionAfter = CompositionTransitionType.none,
  });

  factory CompositionClip.local({
    required String id,
    required String label,
    required String localUri,
    required String fileName,
    required int startMs,
    required int endMs,
  }) {
    return CompositionClip(
      id: id,
      sourceType: CompositionSourceType.localFile,
      label: label,
      localUri: localUri,
      fileName: fileName,
      startMs: startMs,
      endMs: endMs,
    );
  }

  final String id;
  final CompositionSourceType sourceType;
  final String? sourceId;
  final String label;
  final String localUri;
  final String fileName;
  final int startMs;
  final int endMs;
  final bool useOriginalAudio;
  final CompositionTransitionType transitionAfter;

  int get durationMs => endMs - startMs;

  CompositionClip copyWith({
    String? id,
    CompositionSourceType? sourceType,
    String? sourceId,
    String? label,
    String? localUri,
    String? fileName,
    int? startMs,
    int? endMs,
    bool? useOriginalAudio,
    CompositionTransitionType? transitionAfter,
    bool clearSourceId = false,
  }) {
    return CompositionClip(
      id: id ?? this.id,
      sourceType: sourceType ?? this.sourceType,
      sourceId: clearSourceId ? null : (sourceId ?? this.sourceId),
      label: label ?? this.label,
      localUri: localUri ?? this.localUri,
      fileName: fileName ?? this.fileName,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      useOriginalAudio: useOriginalAudio ?? this.useOriginalAudio,
      transitionAfter: transitionAfter ?? this.transitionAfter,
    );
  }
}

class CompositionOutputSettings {
  const CompositionOutputSettings({required this.resolution, required this.ratio});

  static const defaults = CompositionOutputSettings(resolution: 'follow-first', ratio: 'follow-first');

  final String resolution;
  final String ratio;

  CompositionOutputSettings copyWith({String? resolution, String? ratio}) {
    return CompositionOutputSettings(
      resolution: resolution ?? this.resolution,
      ratio: ratio ?? this.ratio,
    );
  }
}

class CompositionBgmSource {
  const CompositionBgmSource({
    required this.type,
    required this.label,
    required this.localUri,
    required this.fileName,
    this.sourceId,
  });

  final CompositionBgmSourceType type;
  final String? sourceId;
  final String label;
  final String localUri;
  final String fileName;
}

class CompositionAudioSettings {
  const CompositionAudioSettings({
    required this.mode,
    this.originalVolume = 1.0,
    this.bgmVolume = 0.35,
    this.loopBgm = true,
    this.bgmSource,
  });

  static const defaults = CompositionAudioSettings(mode: CompositionAudioMode.keepOriginal);

  final CompositionAudioMode mode;
  final double originalVolume;
  final double bgmVolume;
  final bool loopBgm;
  final CompositionBgmSource? bgmSource;

  bool get requiresBgm =>
      mode == CompositionAudioMode.originalPlusBgm || mode == CompositionAudioMode.bgmOnly;

  CompositionAudioSettings copyWith({
    CompositionAudioMode? mode,
    double? originalVolume,
    double? bgmVolume,
    bool? loopBgm,
    CompositionBgmSource? bgmSource,
    bool clearBgmSource = false,
  }) {
    return CompositionAudioSettings(
      mode: mode ?? this.mode,
      originalVolume: originalVolume ?? this.originalVolume,
      bgmVolume: bgmVolume ?? this.bgmVolume,
      loopBgm: loopBgm ?? this.loopBgm,
      bgmSource: clearBgmSource ? null : (bgmSource ?? this.bgmSource),
    );
  }
}

class VideoCompositionProject {
  const VideoCompositionProject({
    required this.clips,
    required this.output,
    required this.audio,
  });

  final List<CompositionClip> clips;
  final CompositionOutputSettings output;
  final CompositionAudioSettings audio;

  static const empty = VideoCompositionProject(
    clips: [],
    output: CompositionOutputSettings.defaults,
    audio: CompositionAudioSettings.defaults,
  );

  bool get canExport => validationMessages.isEmpty;

  List<String> get validationMessages {
    final messages = <String>[];
    if (clips.isEmpty) {
      messages.add('至少添加 1 个视频片段。');
    }
    for (final clip in clips) {
      if (clip.localUri.trim().isEmpty) {
        messages.add('${clip.label} 缺少本地视频文件。');
      }
      if (clip.endMs <= clip.startMs) {
        messages.add('${clip.label} 的结束时间必须晚于开始时间。');
      }
    }
    if (audio.requiresBgm && audio.bgmSource == null) {
      messages.add('请选择 BGM 音频。');
    }
    return messages;
  }

  VideoCompositionProject copyWith({
    List<CompositionClip>? clips,
    CompositionOutputSettings? output,
    CompositionAudioSettings? audio,
  }) {
    return VideoCompositionProject(
      clips: clips ?? this.clips,
      output: output ?? this.output,
      audio: audio ?? this.audio,
    );
  }
}

class CompositionExportResult {
  const CompositionExportResult({
    required this.localPath,
    required this.fileName,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final String localPath;
  final String fileName;
  final int durationMs;
  final int width;
  final int height;
}
```

- [ ] **Step 4: Run model tests to verify they pass**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_models_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Only commit if the user has explicitly approved commits for the implementation session.

```bash
git add lib/app/composition_models.dart test/composition_models_test.dart
git commit -m "Add video composition domain models"
```

---

### Task 2: Add Composition State to AppState and Persistence

**Files:**
- Modify: `lib/app/app_state.dart`
- Test: `test/composition_models_test.dart`

- [ ] **Step 1: Extend tests for clip list manipulation**

Append to `test/composition_models_test.dart`:

```dart
void mainCompositionListTests() {
  group('composition clip list operations', () {
    test('can replace one clip immutably', () {
      final original = CompositionClip.local(
        id: 'clip-1',
        label: 'A.mp4',
        localUri: 'file:///tmp/a.mp4',
        fileName: 'A.mp4',
        startMs: 0,
        endMs: 1000,
      );
      final project = VideoCompositionProject(
        clips: [original],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      );

      final updated = project.copyWith(
        clips: [original.copyWith(startMs: 250, endMs: 900)],
      );

      expect(project.clips.single.startMs, 0);
      expect(updated.clips.single.startMs, 250);
      expect(updated.clips.single.endMs, 900);
    });
  });
}
```

Then call `mainCompositionListTests();` at the end of the existing `main()` body.

- [ ] **Step 2: Run tests**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_models_test.dart
```

Expected: PASS, because pure immutable operations already work.

- [ ] **Step 3: Add AppState fields and import**

Modify `lib/app/app_state.dart` imports:

```dart
import 'composition_models.dart';
```

Add fields near other page state fields:

```dart
VideoCompositionProject compositionProject = VideoCompositionProject.empty;
CompositionExportStatus compositionExportStatus = CompositionExportStatus.idle;
int compositionExportProgress = 0;
String compositionExportStage = '';
String? compositionExportErrorMessage;
CompositionExportResult? compositionExportResult;
```

- [ ] **Step 4: Add AppState composition mutation methods**

Add methods after `setCurrentTab`:

```dart
void resetCompositionProject() {
  compositionProject = VideoCompositionProject.empty;
  compositionExportStatus = CompositionExportStatus.idle;
  compositionExportProgress = 0;
  compositionExportStage = '';
  compositionExportErrorMessage = null;
  compositionExportResult = null;
  notifyListeners();
}

void addCompositionClip(CompositionClip clip) {
  compositionProject = compositionProject.copyWith(
    clips: [...compositionProject.clips, clip],
  );
  compositionExportErrorMessage = null;
  notifyListeners();
}

void updateCompositionClip(String clipId, CompositionClip Function(CompositionClip clip) update) {
  compositionProject = compositionProject.copyWith(
    clips: compositionProject.clips
        .map((clip) => clip.id == clipId ? update(clip) : clip)
        .toList(),
  );
  compositionExportErrorMessage = null;
  notifyListeners();
}

void removeCompositionClip(String clipId) {
  compositionProject = compositionProject.copyWith(
    clips: compositionProject.clips.where((clip) => clip.id != clipId).toList(),
  );
  compositionExportErrorMessage = null;
  notifyListeners();
}

void duplicateCompositionClip(String clipId) {
  final index = compositionProject.clips.indexWhere((clip) => clip.id == clipId);
  if (index == -1) return;
  final clips = List<CompositionClip>.from(compositionProject.clips);
  final source = clips[index];
  clips.insert(
    index + 1,
    source.copyWith(id: 'clip-${DateTime.now().millisecondsSinceEpoch}', label: '${source.label} 副本'),
  );
  compositionProject = compositionProject.copyWith(clips: clips);
  compositionExportErrorMessage = null;
  notifyListeners();
}

void moveCompositionClip(String clipId, int delta) {
  final index = compositionProject.clips.indexWhere((clip) => clip.id == clipId);
  if (index == -1) return;
  final nextIndex = (index + delta).clamp(0, compositionProject.clips.length - 1);
  if (nextIndex == index) return;
  final clips = List<CompositionClip>.from(compositionProject.clips);
  final clip = clips.removeAt(index);
  clips.insert(nextIndex, clip);
  compositionProject = compositionProject.copyWith(clips: clips);
  notifyListeners();
}

void updateCompositionOutput(CompositionOutputSettings output) {
  compositionProject = compositionProject.copyWith(output: output);
  compositionExportErrorMessage = null;
  notifyListeners();
}

void updateCompositionAudio(CompositionAudioSettings audio) {
  compositionProject = compositionProject.copyWith(audio: audio);
  compositionExportErrorMessage = null;
  notifyListeners();
}
```

- [ ] **Step 5: Persist composition state**

In `_toJson()`, add:

```dart
'compositionProject': _compositionProjectToJson(compositionProject),
'compositionExportResult': _compositionExportResultToJson(compositionExportResult),
```

In `_restoreFromJson()`, after task fields are restored, add:

```dart
compositionProject = _compositionProjectFromJson(map['compositionProject']);
compositionExportResult = _compositionExportResultFromJson(map['compositionExportResult']);
compositionExportStatus = CompositionExportStatus.idle;
compositionExportProgress = 0;
compositionExportStage = '';
compositionExportErrorMessage = null;
```

Add helper methods near other JSON helpers:

```dart
Map<String, Object?> _compositionProjectToJson(VideoCompositionProject value) => {
  'clips': value.clips.map(_compositionClipToJson).toList(),
  'output': {
    'resolution': value.output.resolution,
    'ratio': value.output.ratio,
  },
  'audio': _compositionAudioToJson(value.audio),
};

VideoCompositionProject _compositionProjectFromJson(Object? value) {
  if (value is! Map) return VideoCompositionProject.empty;
  final map = Map<String, Object?>.from(value);
  return VideoCompositionProject(
    clips: _listFromJson(map['clips'], _compositionClipFromJson),
    output: _compositionOutputFromJson(map['output']),
    audio: _compositionAudioFromJson(map['audio']),
  );
}

Map<String, Object?> _compositionClipToJson(CompositionClip value) => {
  'id': value.id,
  'sourceType': value.sourceType.name,
  'sourceId': value.sourceId,
  'label': value.label,
  'localUri': value.localUri,
  'fileName': value.fileName,
  'startMs': value.startMs,
  'endMs': value.endMs,
  'useOriginalAudio': value.useOriginalAudio,
  'transitionAfter': value.transitionAfter.name,
};

CompositionClip _compositionClipFromJson(Object? value) {
  if (value is! Map) {
    return CompositionClip.local(
      id: 'clip-${DateTime.now().millisecondsSinceEpoch}',
      label: '未知片段',
      localUri: '',
      fileName: 'unknown.mp4',
      startMs: 0,
      endMs: 1,
    );
  }
  final map = Map<String, Object?>.from(value);
  return CompositionClip(
    id: _stringValue(map['id'], 'clip-${DateTime.now().millisecondsSinceEpoch}'),
    sourceType: _enumValue(CompositionSourceType.values, map['sourceType'], CompositionSourceType.localFile),
    sourceId: _nullableStringValue(map['sourceId']),
    label: _stringValue(map['label'], '视频片段'),
    localUri: _stringValue(map['localUri'], ''),
    fileName: _stringValue(map['fileName'], 'video.mp4'),
    startMs: _intValue(map['startMs'], 0),
    endMs: _intValue(map['endMs'], 1),
    useOriginalAudio: _boolValue(map['useOriginalAudio'], true),
    transitionAfter: _enumValue(
      CompositionTransitionType.values,
      map['transitionAfter'],
      CompositionTransitionType.none,
    ),
  );
}

CompositionOutputSettings _compositionOutputFromJson(Object? value) {
  if (value is! Map) return CompositionOutputSettings.defaults;
  final map = Map<String, Object?>.from(value);
  return CompositionOutputSettings(
    resolution: _stringValue(map['resolution'], CompositionOutputSettings.defaults.resolution),
    ratio: _stringValue(map['ratio'], CompositionOutputSettings.defaults.ratio),
  );
}

Map<String, Object?> _compositionAudioToJson(CompositionAudioSettings value) => {
  'mode': value.mode.name,
  'originalVolume': value.originalVolume,
  'bgmVolume': value.bgmVolume,
  'loopBgm': value.loopBgm,
  'bgmSource': value.bgmSource == null ? null : _compositionBgmSourceToJson(value.bgmSource!),
};

CompositionAudioSettings _compositionAudioFromJson(Object? value) {
  if (value is! Map) return CompositionAudioSettings.defaults;
  final map = Map<String, Object?>.from(value);
  return CompositionAudioSettings(
    mode: _enumValue(CompositionAudioMode.values, map['mode'], CompositionAudioMode.keepOriginal),
    originalVolume: _doubleValue(map['originalVolume'], 1.0),
    bgmVolume: _doubleValue(map['bgmVolume'], 0.35),
    loopBgm: _boolValue(map['loopBgm'], true),
    bgmSource: _compositionBgmSourceFromJson(map['bgmSource']),
  );
}

Map<String, Object?> _compositionBgmSourceToJson(CompositionBgmSource value) => {
  'type': value.type.name,
  'sourceId': value.sourceId,
  'label': value.label,
  'localUri': value.localUri,
  'fileName': value.fileName,
};

CompositionBgmSource? _compositionBgmSourceFromJson(Object? value) {
  if (value is! Map) return null;
  final map = Map<String, Object?>.from(value);
  return CompositionBgmSource(
    type: _enumValue(CompositionBgmSourceType.values, map['type'], CompositionBgmSourceType.localFile),
    sourceId: _nullableStringValue(map['sourceId']),
    label: _stringValue(map['label'], 'BGM'),
    localUri: _stringValue(map['localUri'], ''),
    fileName: _stringValue(map['fileName'], 'bgm.m4a'),
  );
}

Map<String, Object?>? _compositionExportResultToJson(CompositionExportResult? value) {
  if (value == null) return null;
  return {
    'localPath': value.localPath,
    'fileName': value.fileName,
    'durationMs': value.durationMs,
    'width': value.width,
    'height': value.height,
  };
}

CompositionExportResult? _compositionExportResultFromJson(Object? value) {
  if (value is! Map) return null;
  final map = Map<String, Object?>.from(value);
  final localPath = _stringValue(map['localPath'], '');
  if (localPath.isEmpty) return null;
  return CompositionExportResult(
    localPath: localPath,
    fileName: _stringValue(map['fileName'], 'composition.mp4'),
    durationMs: _intValue(map['durationMs'], 0),
    width: _intValue(map['width'], 0),
    height: _intValue(map['height'], 0),
  );
}

double _doubleValue(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return fallback;
}
```

If `_intValue` does not already exist, add:

```dart
int _intValue(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  return fallback;
}
```

- [ ] **Step 6: Run analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS. If it fails because `_intValue` already exists, remove the duplicate helper and rerun.

- [ ] **Step 7: Commit**

```bash
git add lib/app/app_state.dart test/composition_models_test.dart
git commit -m "Persist video composition state"
```

---

### Task 3: Add the Fifth Bottom Tab and Composition Page Shell

**Files:**
- Modify: `lib/app/models.dart`
- Modify: `lib/app/mock_data.dart`
- Modify: `lib/pages/home_shell.dart`
- Create: `lib/pages/composition_page.dart`
- Test: `test/composition_page_test.dart`

- [ ] **Step 1: Write failing widget test for the new tab**

Create `test/composition_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/app_scope.dart';
import 'package:mova/app/app_state.dart';
import 'package:mova/app/app.dart';

void main() {
  testWidgets('shows composition tab and empty state', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: const SeedanceNativeApp(),
      ),
    );

    expect(find.text('剪辑'), findsOneWidget);

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();

    expect(find.text('视频剪辑'), findsOneWidget);
    expect(find.text('添加视频片段'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
```

Expected: FAIL because the tab/page does not exist.

- [ ] **Step 3: Add AppTab value**

Modify `lib/app/models.dart`:

```dart
enum AppTab { create, library, composition, tasks, settings }
```

- [ ] **Step 4: Add tab metadata**

Modify `lib/app/mock_data.dart`:

```dart
const appTabs = [
  (tab: AppTab.create, label: '创作'),
  (tab: AppTab.library, label: '素材库'),
  (tab: AppTab.composition, label: '剪辑'),
  (tab: AppTab.tasks, label: '任务'),
  (tab: AppTab.settings, label: '设置'),
];
```

- [ ] **Step 5: Create page shell**

Create `lib/pages/composition_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import 'home_shell.dart';

class CompositionPage extends StatelessWidget {
  const CompositionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final canExport = state.compositionProject.canExport &&
        state.compositionExportStatus.name != 'preparing' &&
        state.compositionExportStatus.name != 'trimming' &&
        state.compositionExportStatus.name != 'composing' &&
        state.compositionExportStatus.name != 'writing';

    return AppPageScaffold(
      eyebrow: 'Clip',
      title: '视频剪辑',
      subtitle: '裁剪多个视频片段，添加转场和 BGM。',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 112),
        children: [
          SectionLabel('片段'),
          UtilityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state.compositionProject.clips.isEmpty
                      ? '还没有视频片段。'
                      : '共 ${state.compositionProject.clips.length} 个片段',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加视频片段'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel('导出'),
          UtilityPanel(
            child: FilledButton.icon(
              onPressed: canExport ? () {} : null,
              icon: const Icon(Icons.movie_filter_rounded),
              label: const Text('导出合成视频'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Wire page into home shell**

Modify `lib/pages/home_shell.dart` imports:

```dart
import 'composition_page.dart';
```

Modify `pages` map:

```dart
final pages = <AppTab, Widget>{
  AppTab.create: const CreatePage(),
  AppTab.library: const LibraryPage(),
  AppTab.composition: const CompositionPage(),
  AppTab.tasks: const TasksPage(),
  AppTab.settings: const SettingsPage(),
};
```

Modify `_BottomDock.destinations`:

```dart
destinations: const [
  NavigationDestination(
    icon: Icon(Icons.auto_awesome_outlined),
    selectedIcon: Icon(Icons.auto_awesome),
    label: '创作',
  ),
  NavigationDestination(
    icon: Icon(Icons.photo_library_outlined),
    selectedIcon: Icon(Icons.photo_library),
    label: '素材',
  ),
  NavigationDestination(
    icon: Icon(Icons.content_cut_outlined),
    selectedIcon: Icon(Icons.content_cut),
    label: '剪辑',
  ),
  NavigationDestination(
    icon: Icon(Icons.video_collection_outlined),
    selectedIcon: Icon(Icons.video_collection),
    label: '任务',
  ),
  NavigationDestination(
    icon: Icon(Icons.tune_outlined),
    selectedIcon: Icon(Icons.tune),
    label: '设置',
  ),
],
```

- [ ] **Step 7: Run widget test**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
```

Expected: PASS.

- [ ] **Step 8: Run analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/app/models.dart lib/app/mock_data.dart lib/pages/home_shell.dart lib/pages/composition_page.dart test/composition_page_test.dart
git commit -m "Add video composition tab"
```

---

### Task 4: Add Local Video and Audio Picking

**Files:**
- Modify: `lib/services/native_file_picker.dart`
- Modify: `lib/app/app_state.dart`
- Modify: `android/app/src/main/kotlin/com/jbrains/mova/MainActivity.kt`
- Test: `test/composition_page_test.dart`

- [ ] **Step 1: Add widget test for add button presence and accessibility**

Append to `test/composition_page_test.dart`:

```dart
testWidgets('composition add video action has accessible label', (tester) async {
  final state = AppState();
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: const SeedanceNativeApp(),
    ),
  );

  await tester.tap(find.text('剪辑'));
  await tester.pumpAndSettle();

  expect(find.byTooltip('添加本地视频'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test to verify it fails**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
```

Expected: FAIL because the tooltip does not exist yet.

- [ ] **Step 3: Extend file picker Dart API**

Modify `lib/services/native_file_picker.dart`:

```dart
Future<PickedLocalMediaFile?> pickSingleAudioFile() async {
  final result = await _channel.invokeMapMethod<String, Object?>(
    'pickSingleAudioFile',
  );
  if (result == null) return null;
  return PickedLocalMediaFile.fromPlatformMap(result);
}
```

- [ ] **Step 4: Add AppState local source methods**

Add to `lib/app/app_state.dart` near `pickLocalVideoSource()`:

```dart
Future<void> pickAndAddLocalCompositionVideo() async {
  final picked = await _filePicker.pickSingleVideoFile();
  if (picked == null || picked.uri.trim().isEmpty) return;
  addCompositionClip(
    CompositionClip.local(
      id: 'clip-${DateTime.now().millisecondsSinceEpoch}',
      label: picked.name,
      localUri: picked.uri,
      fileName: picked.name,
      startMs: 0,
      endMs: 15000,
    ),
  );
  currentTab = AppTab.composition;
  notifyListeners();
}

Future<void> pickCompositionBgm() async {
  final picked = await _filePicker.pickSingleAudioFile();
  if (picked == null || picked.uri.trim().isEmpty) return;
  updateCompositionAudio(
    compositionProject.audio.copyWith(
      bgmSource: CompositionBgmSource(
        type: CompositionBgmSourceType.localFile,
        label: picked.name,
        localUri: picked.uri,
        fileName: picked.name,
      ),
    ),
  );
}
```

- [ ] **Step 5: Wire add button to AppState**

In `lib/pages/composition_page.dart`, replace the add button with:

```dart
Tooltip(
  message: '添加本地视频',
  child: FilledButton.icon(
    onPressed: state.pickAndAddLocalCompositionVideo,
    icon: const Icon(Icons.add_rounded),
    label: const Text('添加视频片段'),
  ),
),
```

- [ ] **Step 6: Add Android audio picker method**

Modify `MainActivity.kt` constants:

```kotlin
private val pickAudioPickerRequestCode = 2053
```

Add file channel branch:

```kotlin
"pickSingleAudioFile" -> pickSingleAudioFile(result)
```

Add method:

```kotlin
private fun pickSingleAudioFile(result: MethodChannel.Result) {
    if (pendingPickResult != null) {
        result.error("picker_busy", "文件选择器正在打开。", null)
        return
    }
    pendingPickResult = result
    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
        type = "audio/*"
        addCategory(Intent.CATEGORY_OPENABLE)
    }
    startActivityForResult(Intent.createChooser(intent, "选择音频"), pickAudioPickerRequestCode)
}
```

Add `onActivityResult` branch:

```kotlin
pickAudioPickerRequestCode -> handlePickSingleAudioResult(resultCode, data)
```

Add handler:

```kotlin
private fun handlePickSingleAudioResult(resultCode: Int, data: Intent?) {
    val result = pendingPickResult ?: return
    pendingPickResult = null

    if (resultCode != Activity.RESULT_OK || data?.data == null) {
        result.success(null)
        return
    }

    val uri = data.data ?: run {
        result.success(null)
        return
    }

    try {
        val mimeType = contentResolver.getType(uri) ?: "audio/mpeg"
        val localCopy = copyUriToCache(uri, displayName(uri))
        result.success(
            mapOf(
                "name" to displayName(uri),
                "mimeType" to mimeType,
                "uri" to Uri.fromFile(localCopy).toString(),
                "path" to localCopy.absolutePath,
            )
        )
    } catch (error: Exception) {
        result.error("pick_failed", error.message ?: "读取音频失败。", null)
    }
}
```

- [ ] **Step 7: Run widget test and analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/services/native_file_picker.dart lib/app/app_state.dart lib/pages/composition_page.dart android/app/src/main/kotlin/com/jbrains/mova/MainActivity.kt test/composition_page_test.dart
git commit -m "Add local media picking for composition"
```

---

### Task 5: Build Clip List Editing UI

**Files:**
- Modify: `lib/pages/composition_page.dart`
- Test: `test/composition_page_test.dart`

- [ ] **Step 1: Add widget test for visible clip controls**

Append to `test/composition_page_test.dart`:

```dart
testWidgets('composition clip card exposes edit controls', (tester) async {
  final state = AppState();
  state.addCompositionClip(
    CompositionClip.local(
      id: 'clip-1',
      label: 'A.mp4',
      localUri: 'file:///tmp/a.mp4',
      fileName: 'A.mp4',
      startMs: 0,
      endMs: 15000,
    ),
  );

  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: const SeedanceNativeApp(),
    ),
  );

  await tester.tap(find.text('剪辑'));
  await tester.pumpAndSettle();

  expect(find.text('A.mp4'), findsOneWidget);
  expect(find.byTooltip('上移片段'), findsOneWidget);
  expect(find.byTooltip('下移片段'), findsOneWidget);
  expect(find.byTooltip('复制片段'), findsOneWidget);
  expect(find.byTooltip('删除片段'), findsOneWidget);
  expect(find.text('转场'), findsOneWidget);
});
```

Add missing import:

```dart
import 'package:mova/app/composition_models.dart';
```

- [ ] **Step 2: Run widget test to verify it fails**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
```

Expected: FAIL because clip cards are not rendered.

- [ ] **Step 3: Add clip cards to page**

In `CompositionPage`, replace the clip count text area with:

```dart
if (state.compositionProject.clips.isEmpty)
  Text('还没有视频片段。', style: Theme.of(context).textTheme.titleMedium)
else
  ...state.compositionProject.clips.map(
    (clip) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _CompositionClipCard(clip: clip),
    ),
  ),
```

Add `_CompositionClipCard` below `CompositionPage`:

```dart
class _CompositionClipCard extends StatelessWidget {
  const _CompositionClipCard({required this.clip});

  final CompositionClip clip;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.movie_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    clip.label,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 42),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('范围：${_formatMs(clip.startMs)} - ${_formatMs(clip.endMs)}'),
            const SizedBox(height: 8),
            DropdownButtonFormField<CompositionTransitionType>(
              value: clip.transitionAfter,
              decoration: const InputDecoration(labelText: '转场'),
              items: CompositionTransitionType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_transitionLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                state.updateCompositionClip(
                  clip.id,
                  (current) => current.copyWith(transitionAfter: value),
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                IconButton.filledTonal(
                  tooltip: '上移片段',
                  onPressed: () => state.moveCompositionClip(clip.id, -1),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '下移片段',
                  onPressed: () => state.moveCompositionClip(clip.id, 1),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '复制片段',
                  onPressed: () => state.duplicateCompositionClip(clip.id),
                  icon: const Icon(Icons.copy_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '删除片段',
                  onPressed: () => state.removeCompositionClip(clip.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatMs(int value) {
  final duration = Duration(milliseconds: value);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _transitionLabel(CompositionTransitionType type) {
  switch (type) {
    case CompositionTransitionType.none:
      return '无';
    case CompositionTransitionType.fade:
      return '淡入淡出';
    case CompositionTransitionType.crossDissolve:
      return '交叉溶解';
    case CompositionTransitionType.black:
      return '黑场过渡';
    case CompositionTransitionType.whiteFlash:
      return '白场闪切';
  }
}
```

Add import:

```dart
import '../app/composition_models.dart';
```

- [ ] **Step 4: Run widget test**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/composition_page.dart test/composition_page_test.dart
git commit -m "Add composition clip editing UI"
```

---

### Task 6: Add Output and Audio Controls

**Files:**
- Modify: `lib/pages/composition_page.dart`
- Test: `test/composition_page_test.dart`

- [ ] **Step 1: Add widget test for output and audio controls**

Append:

```dart
testWidgets('composition page shows output and audio controls', (tester) async {
  final state = AppState();
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: const SeedanceNativeApp(),
    ),
  );

  await tester.tap(find.text('剪辑'));
  await tester.pumpAndSettle();

  expect(find.text('输出设置'), findsOneWidget);
  expect(find.text('音频'), findsOneWidget);
  expect(find.text('跟随首个片段'), findsWidgets);
  expect(find.text('保留原声'), findsOneWidget);
  expect(find.text('选择 BGM'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test to verify it fails**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
```

Expected: FAIL because controls are not present.

- [ ] **Step 3: Add output settings section**

In `CompositionPage` list before export section, add:

```dart
const SizedBox(height: 16),
SectionLabel('输出设置'),
UtilityPanel(
  child: Column(
    children: [
      DropdownButtonFormField<String>(
        value: state.compositionProject.output.resolution,
        decoration: const InputDecoration(labelText: '分辨率'),
        items: const [
          DropdownMenuItem(value: 'follow-first', child: Text('跟随首个片段')),
          DropdownMenuItem(value: '720p', child: Text('720p')),
          DropdownMenuItem(value: '1080p', child: Text('1080p')),
        ],
        onChanged: (value) {
          if (value == null) return;
          state.updateCompositionOutput(
            state.compositionProject.output.copyWith(resolution: value),
          );
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: state.compositionProject.output.ratio,
        decoration: const InputDecoration(labelText: '比例'),
        items: const [
          DropdownMenuItem(value: 'follow-first', child: Text('跟随首个片段')),
          DropdownMenuItem(value: '16:9', child: Text('16:9')),
          DropdownMenuItem(value: '9:16', child: Text('9:16')),
          DropdownMenuItem(value: '1:1', child: Text('1:1')),
        ],
        onChanged: (value) {
          if (value == null) return;
          state.updateCompositionOutput(
            state.compositionProject.output.copyWith(ratio: value),
          );
        },
      ),
    ],
  ),
),
```

- [ ] **Step 4: Add audio settings section**

After output section, add:

```dart
const SizedBox(height: 16),
SectionLabel('音频'),
UtilityPanel(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<CompositionAudioMode>(
        value: state.compositionProject.audio.mode,
        decoration: const InputDecoration(labelText: '音频模式'),
        items: CompositionAudioMode.values
            .map(
              (mode) => DropdownMenuItem(
                value: mode,
                child: Text(_audioModeLabel(mode)),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          state.updateCompositionAudio(state.compositionProject.audio.copyWith(mode: value));
        },
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: state.pickCompositionBgm,
        icon: const Icon(Icons.music_note_rounded),
        label: Text(
          state.compositionProject.audio.bgmSource == null
              ? '选择 BGM'
              : state.compositionProject.audio.bgmSource!.label,
        ),
      ),
    ],
  ),
),
```

Add helper:

```dart
String _audioModeLabel(CompositionAudioMode mode) {
  switch (mode) {
    case CompositionAudioMode.keepOriginal:
      return '保留原声';
    case CompositionAudioMode.muted:
      return '静音';
    case CompositionAudioMode.originalPlusBgm:
      return '原声 + BGM';
    case CompositionAudioMode.bgmOnly:
      return '仅 BGM';
  }
}
```

- [ ] **Step 5: Run widget tests and analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/composition_page.dart test/composition_page_test.dart
git commit -m "Add composition output and audio controls"
```

---

### Task 7: Add Library and Task Entry Points

**Files:**
- Modify: `lib/app/app_state.dart`
- Modify: `lib/pages/library_page.dart`
- Modify: `lib/pages/tasks_page.dart`

- [ ] **Step 1: Add AppState methods for attachment and task videos**

Add to `lib/app/app_state.dart` near media-localization methods:

```dart
Future<bool> addAttachmentVideoToComposition(String attachmentId) async {
  final attachment = attachmentById(attachmentId);
  if (attachment == null || attachment.kind != AttachmentKind.video) return false;
  final ready = await ensureAttachmentVideoLocal(attachmentId);
  if (!ready) return false;
  final refreshed = attachmentById(attachmentId);
  final localUri = refreshed?.localResourceUri?.trim() ?? '';
  if (localUri.isEmpty) return false;
  addCompositionClip(
    CompositionClip(
      id: 'clip-${DateTime.now().millisecondsSinceEpoch}',
      sourceType: CompositionSourceType.attachment,
      sourceId: attachmentId,
      label: refreshed?.label ?? attachment.label,
      localUri: localUri,
      fileName: refreshed?.localFileName ?? refreshed?.fileName ?? attachment.fileName,
      startMs: 0,
      endMs: 15000,
    ),
  );
  currentTab = AppTab.composition;
  notifyListeners();
  return true;
}

Future<bool> addTaskVideoToComposition(String taskId) async {
  final index = tasks.indexWhere((task) => task.id == taskId);
  if (index == -1) return false;
  final task = tasks[index];
  if (task.kind != TaskKind.video) return false;
  if ((task.localResourceUri?.trim().isEmpty ?? true)) {
    final ready = await ensureTaskVideoLocal(taskId);
    if (!ready) return false;
  }
  final latestIndex = tasks.indexWhere((entry) => entry.id == taskId);
  if (latestIndex == -1) return false;
  final refreshed = tasks[latestIndex];
  final localUri = refreshed.localResourceUri?.trim() ?? '';
  if (localUri.isEmpty) return false;
  addCompositionClip(
    CompositionClip(
      id: 'clip-${DateTime.now().millisecondsSinceEpoch}',
      sourceType: CompositionSourceType.task,
      sourceId: taskId,
      label: refreshed.localFileName ?? '任务视频',
      localUri: localUri,
      fileName: refreshed.localFileName ?? 'task-video.mp4',
      startMs: 0,
      endMs: 15000,
    ),
  );
  currentTab = AppTab.composition;
  notifyListeners();
  return true;
}
```

- [ ] **Step 2: Add library action**

In `lib/pages/library_page.dart`, locate the video attachment actions near existing frame-capture action. Add a visible action button for video attachments:

```dart
if (attachment.kind == AttachmentKind.video)
  ToolIconButton(
    tooltip: '添加到剪辑',
    icon: Icons.content_cut_rounded,
    onPressed: () async {
      final ok = await AppScope.of(context).addAttachmentVideoToComposition(attachment.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(ok ? '已添加到剪辑' : '添加失败')));
    },
  ),
```

Use the local action container already used for attachment card actions; do not introduce a new action bar pattern.

- [ ] **Step 3: Add task action**

In `lib/pages/tasks_page.dart`, locate task video result actions near copy/open/download controls. Add:

```dart
if (task.kind == TaskKind.video && (task.videoUrl != null || task.localResourceUri != null))
  ToolIconButton(
    tooltip: '添加到剪辑',
    icon: Icons.content_cut_rounded,
    onPressed: () async {
      final ok = await AppScope.of(context).addTaskVideoToComposition(task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(ok ? '已添加到剪辑' : '添加失败')));
    },
  ),
```

Use the same button style as nearby task actions.

- [ ] **Step 4: Run analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS. If placement creates duplicate `context` or unavailable `ToolIconButton` scope issues, move the action into the existing widget scope where other action buttons are built.

- [ ] **Step 5: Commit**

```bash
git add lib/app/app_state.dart lib/pages/library_page.dart lib/pages/tasks_page.dart
git commit -m "Add composition entry points from media"
```

---

### Task 8: Add Video Composition Service and Channel Mapping

**Files:**
- Create: `lib/services/video_composition_service.dart`
- Modify: `lib/app/app_state.dart`
- Test: `test/video_composition_service_test.dart`

- [ ] **Step 1: Write failing service mapping test**

Create `test/video_composition_service_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/composition_models.dart';
import 'package:mova/services/video_composition_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends composition request over method channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoCompositionService.channel, (call) async {
      calls.add(call);
      return {
        'localPath': '/tmp/out.mp4',
        'fileName': 'out.mp4',
        'durationMs': 1000,
        'width': 1280,
        'height': 720,
      };
    });

    final service = VideoCompositionService();
    final result = await service.export(
      VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file:///tmp/a.mp4',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      ),
    );

    expect(calls.single.method, 'exportComposition');
    expect(calls.single.arguments, isA<Map>());
    expect(result.localPath, '/tmp/out.mp4');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/video_composition_service_test.dart
```

Expected: FAIL because service file does not exist.

- [ ] **Step 3: Create service**

Create `lib/services/video_composition_service.dart`:

```dart
import 'package:flutter/services.dart';

import '../app/composition_models.dart';

class VideoCompositionService {
  static const channel = MethodChannel('mova/video_composition');

  Future<CompositionExportResult> export(VideoCompositionProject project) async {
    final response = await channel.invokeMapMethod<String, Object?>(
      'exportComposition',
      _projectToMap(project),
    );
    if (response == null) {
      throw const PlatformException(
        code: 'empty_response',
        message: '视频合成没有返回结果。',
      );
    }
    return CompositionExportResult(
      localPath: response['localPath'] as String? ?? '',
      fileName: response['fileName'] as String? ?? 'composition.mp4',
      durationMs: response['durationMs'] as int? ?? 0,
      width: response['width'] as int? ?? 0,
      height: response['height'] as int? ?? 0,
    );
  }

  Future<void> cancel() async {
    await channel.invokeMethod<bool>('cancelComposition');
  }

  Map<String, Object?> _projectToMap(VideoCompositionProject project) => {
    'clips': project.clips.map(_clipToMap).toList(),
    'output': {
      'resolution': project.output.resolution,
      'ratio': project.output.ratio,
    },
    'audio': {
      'mode': project.audio.mode.name,
      'originalVolume': project.audio.originalVolume,
      'bgmVolume': project.audio.bgmVolume,
      'loopBgm': project.audio.loopBgm,
      'bgmSource': project.audio.bgmSource == null
          ? null
          : {
              'type': project.audio.bgmSource!.type.name,
              'localUri': project.audio.bgmSource!.localUri,
              'fileName': project.audio.bgmSource!.fileName,
            },
    },
  };

  Map<String, Object?> _clipToMap(CompositionClip clip) => {
    'id': clip.id,
    'label': clip.label,
    'localUri': clip.localUri,
    'fileName': clip.fileName,
    'startMs': clip.startMs,
    'endMs': clip.endMs,
    'useOriginalAudio': clip.useOriginalAudio,
    'transitionAfter': clip.transitionAfter.name,
  };
}
```

- [ ] **Step 4: Inject service into AppState**

Modify `lib/app/app_state.dart` imports:

```dart
import '../services/video_composition_service.dart';
```

Add field:

```dart
final VideoCompositionService _videoCompositionService;
```

Add constructor parameter:

```dart
VideoCompositionService? videoCompositionService,
```

Initialize:

```dart
_videoCompositionService = videoCompositionService ?? VideoCompositionService(),
```

- [ ] **Step 5: Add export action**

Add to `AppState`:

```dart
bool get isExportingComposition =>
    compositionExportStatus == CompositionExportStatus.preparing ||
    compositionExportStatus == CompositionExportStatus.trimming ||
    compositionExportStatus == CompositionExportStatus.composing ||
    compositionExportStatus == CompositionExportStatus.writing;

Future<bool> exportComposition() async {
  if (isExportingComposition) return false;
  final messages = compositionProject.validationMessages;
  if (messages.isNotEmpty) {
    compositionExportErrorMessage = messages.first;
    notifyListeners();
    return false;
  }
  compositionExportStatus = CompositionExportStatus.preparing;
  compositionExportProgress = 0;
  compositionExportStage = '准备素材';
  compositionExportErrorMessage = null;
  compositionExportResult = null;
  notifyListeners();
  try {
    final result = await _videoCompositionService.export(compositionProject);
    compositionExportStatus = CompositionExportStatus.success;
    compositionExportProgress = 100;
    compositionExportStage = '导出完成';
    compositionExportResult = result;
    notifyListeners();
    return true;
  } on Exception catch (error) {
    compositionExportStatus = CompositionExportStatus.failure;
    compositionExportProgress = 0;
    compositionExportStage = '导出失败';
    compositionExportErrorMessage = _cleanError(error);
    notifyListeners();
    return false;
  }
}

Future<void> cancelCompositionExport() async {
  if (!isExportingComposition) return;
  await _videoCompositionService.cancel();
  compositionExportStatus = CompositionExportStatus.canceled;
  compositionExportStage = '已取消';
  notifyListeners();
}
```

- [ ] **Step 6: Wire export button**

In `CompositionPage`, replace `onPressed: canExport ? () {} : null` with:

```dart
onPressed: canExport ? state.exportComposition : null,
```

Show error/result in export panel:

```dart
if (state.compositionExportErrorMessage != null) ...[
  const SizedBox(height: 12),
  Text(
    state.compositionExportErrorMessage!,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  ),
],
if (state.compositionExportResult != null) ...[
  const SizedBox(height: 12),
  Text('已导出：${state.compositionExportResult!.fileName}'),
],
```

- [ ] **Step 7: Run tests and analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/video_composition_service_test.dart
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/services/video_composition_service.dart lib/app/app_state.dart lib/pages/composition_page.dart test/video_composition_service_test.dart
git commit -m "Add video composition export service"
```

---

### Task 9: Add Android Composition Channel with Unsupported Stub

**Files:**
- Modify: `android/app/src/main/kotlin/com/jbrains/mova/MainActivity.kt`

- [ ] **Step 1: Add channel name**

In `MainActivity.kt`, add:

```kotlin
private val videoCompositionChannelName = "mova/video_composition"
```

- [ ] **Step 2: Register method channel stub**

Inside `configureFlutterEngine`, add:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoCompositionChannelName).setMethodCallHandler { call, result ->
    when (call.method) {
        "exportComposition" -> {
            result.error("unsupported", "视频合成引擎尚未安装。", null)
        }
        "cancelComposition" -> {
            result.success(true)
        }
        else -> result.notImplemented()
    }
}
```

- [ ] **Step 3: Run analyzer/build compile check**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
/Users/jbrains/dev/flutter-sdk/bin/flutter build apk --debug
```

Expected: Analyzer PASS and debug APK build succeeds. The composition export still shows a controlled unsupported error.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/jbrains/mova/MainActivity.kt
git commit -m "Add Android video composition channel"
```

---

### Task 10: Add FFmpeg Dependency and Android Export Implementation

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/kotlin/com/jbrains/mova/MainActivity.kt`

- [ ] **Step 1: Verify package resolution before editing code**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter pub add ffmpeg_kit_flutter_new
```

Expected: `pubspec.yaml` and `pubspec.lock` update successfully. If package resolution fails, stop and ask the user to choose between a maintained FFmpegKit fork and a custom native FFmpeg binary integration; do not improvise a different package silently.

- [ ] **Step 2: Add Android package if Flutter package requires it**

If `ffmpeg_kit_flutter_new` setup documentation requires an Android package line, add the documented package to `android/app/build.gradle.kts`. The implementation must use the package installed by `flutter pub add`; do not mix two unrelated FFmpeg distributions.

- [ ] **Step 3: Implement path normalization helper**

In `MainActivity.kt`, add:

```kotlin
private fun localPathFromUri(value: String): String {
    if (value.startsWith("file://")) {
        return Uri.parse(value).path ?: value.removePrefix("file://")
    }
    return value
}
```

- [ ] **Step 4: Implement export request parsing**

Add data classes near the bottom of `MainActivity.kt`:

```kotlin
data class CompositionClipRequest(
    val localPath: String,
    val fileName: String,
    val startMs: Long,
    val endMs: Long,
    val useOriginalAudio: Boolean,
    val transitionAfter: String,
)

data class CompositionRequest(
    val clips: List<CompositionClipRequest>,
    val resolution: String,
    val ratio: String,
    val audioMode: String,
    val originalVolume: Double,
    val bgmVolume: Double,
    val loopBgm: Boolean,
    val bgmPath: String?,
)
```

Add parser:

```kotlin
private fun parseCompositionRequest(arguments: Any?): CompositionRequest {
    val map = arguments as? Map<*, *> ?: throw IllegalArgumentException("缺少合成参数。")
    val clipsValue = map["clips"] as? List<*> ?: emptyList<Any>()
    val clips = clipsValue.map { item ->
        val clip = item as? Map<*, *> ?: throw IllegalArgumentException("片段参数无效。")
        CompositionClipRequest(
            localPath = localPathFromUri(clip["localUri"] as? String ?: ""),
            fileName = clip["fileName"] as? String ?: "clip.mp4",
            startMs = (clip["startMs"] as? Number)?.toLong() ?: 0L,
            endMs = (clip["endMs"] as? Number)?.toLong() ?: 0L,
            useOriginalAudio = clip["useOriginalAudio"] as? Boolean ?: true,
            transitionAfter = clip["transitionAfter"] as? String ?: "none",
        )
    }
    val output = map["output"] as? Map<*, *> ?: emptyMap<Any, Any>()
    val audio = map["audio"] as? Map<*, *> ?: emptyMap<Any, Any>()
    val bgmSource = audio["bgmSource"] as? Map<*, *>
    return CompositionRequest(
        clips = clips,
        resolution = output["resolution"] as? String ?: "follow-first",
        ratio = output["ratio"] as? String ?: "follow-first",
        audioMode = audio["mode"] as? String ?: "keepOriginal",
        originalVolume = (audio["originalVolume"] as? Number)?.toDouble() ?: 1.0,
        bgmVolume = (audio["bgmVolume"] as? Number)?.toDouble() ?: 0.35,
        loopBgm = audio["loopBgm"] as? Boolean ?: true,
        bgmPath = (bgmSource?.get("localUri") as? String)?.let { localPathFromUri(it) },
    )
}
```

- [ ] **Step 5: Implement conservative FFmpeg command builder**

Add:

```kotlin
private fun buildCompositionCommand(request: CompositionRequest, outputPath: String): String {
    if (request.clips.isEmpty()) throw IllegalArgumentException("至少添加 1 个视频片段。")
    request.clips.forEach { clip ->
        if (clip.localPath.isBlank() || !File(clip.localPath).exists()) {
            throw IllegalArgumentException("视频文件不存在：${clip.fileName}")
        }
        if (clip.endMs <= clip.startMs) {
            throw IllegalArgumentException("${clip.fileName} 的结束时间必须晚于开始时间。")
        }
    }

    val inputs = mutableListOf<String>()
    request.clips.forEach { clip ->
        inputs.add("-ss ${clip.startMs / 1000.0} -to ${clip.endMs / 1000.0} -i '${clip.localPath.replace("'", "'\\''")}'")
    }
    val concatInputs = request.clips.indices.joinToString("") { index -> "[$index:v:0][$index:a:0]" }
    val filter = "$concatInputs concat=n=${request.clips.size}:v=1:a=1 [v][a]"
    return "${inputs.joinToString(" ")} -filter_complex '$filter' -map '[v]' -map '[a]' -y '${outputPath.replace("'", "'\\''")}'"
}
```

This first command must prioritize correct trim+concat. Add transitions and BGM in the next step after a working baseline.

- [ ] **Step 6: Implement export channel using FFmpegKit API**

Replace the unsupported `exportComposition` branch with code shaped like this, using the actual API names from the installed FFmpeg package:

```kotlin
"exportComposition" -> {
    try {
        val request = parseCompositionRequest(call.arguments)
        val outputDir = File(cacheDir, "composition_exports").apply { mkdirs() }
        val outputFile = File(outputDir, "composition-${System.currentTimeMillis()}.mp4")
        val command = buildCompositionCommand(request, outputFile.absolutePath)
        FFmpegKit.executeAsync(command) { session ->
            val returnCode = session.returnCode
            runOnUiThread {
                if (ReturnCode.isSuccess(returnCode)) {
                    result.success(
                        mapOf(
                            "localPath" to outputFile.absolutePath,
                            "fileName" to outputFile.name,
                            "durationMs" to request.clips.sumOf { it.endMs - it.startMs }.toInt(),
                            "width" to 0,
                            "height" to 0,
                        )
                    )
                } else {
                    result.error("export_failed", session.failStackTrace ?: "视频合成失败。", null)
                }
            }
        }
    } catch (error: Exception) {
        result.error("export_failed", error.message ?: "视频合成失败。", null)
    }
}
```

Use the installed package imports, typically:

```kotlin
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
```

If the package uses different import names, update imports to match the installed package documentation and keep the method-channel response contract unchanged.

- [ ] **Step 7: Build debug APK**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter build apk --debug
```

Expected: PASS. If the FFmpeg dependency fails Gradle resolution, stop and report the exact dependency error.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/build.gradle.kts android/app/src/main/kotlin/com/jbrains/mova/MainActivity.kt
git commit -m "Implement Android video composition export"
```

---

### Task 11: Add Export Result Actions

**Files:**
- Modify: `lib/app/app_state.dart`
- Modify: `lib/pages/composition_page.dart`

- [ ] **Step 1: Add AppState save/import methods**

Add to `lib/app/app_state.dart`:

```dart
Future<String?> saveCompositionExportToGallery() async {
  final result = compositionExportResult;
  if (result == null) return null;
  final saved = await _mediaChannel.invokeMapMethod<String, Object?>(
    'saveVideoToGallery',
    {'sourcePath': result.localPath, 'fileName': result.fileName},
  );
  return saved?['uri'] as String? ?? saved?['path'] as String?;
}

Future<String?> importCompositionExportToLibrary({String category = ''}) async {
  final result = compositionExportResult;
  if (result == null) return null;
  final bytes = await File(result.localPath).readAsBytes();
  final picked = PickedNativeFile.fromBytes(
    name: result.fileName,
    mimeType: 'video/mp4',
    bytes: bytes,
  );
  final uploadResult = await switch (settings.storageProvider) {
    StorageProvider.qiniu => _qiniuUploadService.upload(settings: settings, file: picked),
    StorageProvider.bitifulS4 => _bitifulUploadService.upload(settings: settings, file: picked),
  };
  return insertUploadedAttachment(
    uploadResult,
    labelOverride: result.fileName,
    roleOverride: AttachmentRole.referenceVideo,
    categoryOverride: category,
  );
}
```

- [ ] **Step 2: Add result buttons**

In `CompositionPage`, under the exported result text, add:

```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    FilledButton.tonalIcon(
      onPressed: () async {
        final saved = await state.saveCompositionExportToGallery();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(saved == null ? '保存失败' : '已保存到系统相册')));
      },
      icon: const Icon(Icons.save_alt_rounded),
      label: const Text('保存到相册/文件'),
    ),
    FilledButton.tonalIcon(
      onPressed: () async {
        final attachmentId = await state.importCompositionExportToLibrary();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(attachmentId == null ? '导入失败' : '已导入素材库')));
      },
      icon: const Icon(Icons.photo_library_rounded),
      label: const Text('导入素材库'),
    ),
  ],
),
```

- [ ] **Step 3: Run analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/app/app_state.dart lib/pages/composition_page.dart
git commit -m "Add composition export result actions"
```

---

### Task 12: UI/UX and Accessibility Verification Pass

**Files:**
- Modify: `lib/pages/composition_page.dart`
- Test: `test/composition_page_test.dart`

- [ ] **Step 1: Add text scaling widget test**

Append:

```dart
testWidgets('composition page remains usable with large text scale', (tester) async {
  final state = AppState();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
      child: AppScope(
        notifier: state,
        child: const SeedanceNativeApp(),
      ),
    ),
  );

  await tester.tap(find.text('剪辑'));
  await tester.pumpAndSettle();

  expect(find.text('视频剪辑'), findsOneWidget);
  expect(find.text('添加视频片段'), findsOneWidget);
});
```

- [ ] **Step 2: Add semantics labels where needed**

For every icon-only action in `_CompositionClipCard`, ensure `tooltip` remains present. Add a tooltip to export result action buttons only if their text could be hidden by layout changes.

- [ ] **Step 3: Ensure bottom padding keeps controls visible**

In `CompositionPage`, keep list padding at least:

```dart
padding: const EdgeInsets.fromLTRB(20, 6, 20, 112),
```

Do not reduce the bottom padding below the bottom navigation height plus safe-area spacing.

- [ ] **Step 4: Run UI tests and analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test test/composition_page_test.dart
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Run app:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter run
```

Verify on Android:

- Bottom navigation shows exactly five labeled tabs.
- `剪辑` page opens from the bottom tab.
- Add button touch target is at least 44pt visually.
- Clip action buttons are not cramped and have visible pressed feedback.
- Export CTA is not hidden by bottom navigation.
- Light and dark themes maintain readable text contrast.
- Large text does not hide the add/export buttons.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/composition_page.dart test/composition_page_test.dart
git commit -m "Polish composition accessibility"
```

---

### Task 13: Full Verification

**Files:**
- No code changes expected.

- [ ] **Step 1: Run unit and widget tests**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter test
```

Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter analyze
```

Expected: PASS.

- [ ] **Step 3: Build Android debug APK**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter build apk --debug
```

Expected: PASS.

- [ ] **Step 4: Manual golden-path test on Android**

Run:

```bash
/Users/jbrains/dev/flutter-sdk/bin/flutter run
```

Verify:

1. Open `剪辑` tab.
2. Add a local video.
3. Duplicate it.
4. Change transition on the first clip.
5. Choose `静音` and export.
6. Confirm export result appears.
7. Save to gallery/files.
8. Import to素材库.
9. Open素材库 and confirm imported video appears.

- [ ] **Step 5: Manual edge tests**

Verify:

1. Export with zero clips shows a validation message and does not start export.
2. BGM-only mode without BGM shows `请选择 BGM 音频。`.
3. Android back from `剪辑` preserves current clip list after returning.
4. An unsupported/failed FFmpeg run shows a readable failure and does not clear the project.

- [ ] **Step 6: Final status**

Run:

```bash
git status --short
```

Expected: only intentional changes remain. If committing was authorized task-by-task, working tree should be clean.

---

## Self-Review

Spec coverage:

- Primary `剪辑` tab: Task 3.
- Local videos: Task 4.
- Library/task video entry and local download: Task 7.
- Per-clip trimming data model and controls: Tasks 1 and 5.
- Reorder/delete/duplicate: Tasks 2 and 5.
- Built-in transitions: Tasks 1, 5, and 10.
- Output ratio/resolution controls: Task 6.
- Audio modes and BGM source: Tasks 4 and 6.
- Android local export service: Tasks 8–10.
- Export result import/save: Task 11.
- UI/UX Pro Max constraints: Tasks 3, 5, 6, and 12.
- Verification: Task 13.

Known scoped limitation in this plan:

- Task 10 first implements a conservative trim+concat FFmpeg command, then uses the same service boundary for transitions/BGM expansion. If the selected FFmpeg package is unavailable, implementation must pause for dependency selection instead of silently changing engines.

Placeholder scan:

- No `TBD` or `TODO` markers remain.
- The only conditional language is around external FFmpeg package resolution, where the plan explicitly instructs stopping and asking the user rather than guessing.

Type consistency:

- `CompositionClip`, `VideoCompositionProject`, `CompositionAudioSettings`, `CompositionOutputSettings`, and `CompositionExportResult` are defined before later tasks use them.
- Method names used in UI tasks match AppState methods introduced earlier.
