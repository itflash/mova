import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/app_state.dart';
import 'package:mova/app/composition_models.dart';
import 'package:mova/app/models.dart';
import 'package:mova/services/video_composition_service.dart';

void main() {
  group('Composition model spec', () {
    test('defines source types in spec order', () {
      expect(CompositionSourceType.values, [
        CompositionSourceType.localFile,
        CompositionSourceType.attachment,
        CompositionSourceType.task,
      ]);
    });

    test('defines transition types in spec order', () {
      expect(CompositionTransitionType.values, [
        CompositionTransitionType.none,
        CompositionTransitionType.fade,
        CompositionTransitionType.crossDissolve,
        CompositionTransitionType.black,
        CompositionTransitionType.whiteFlash,
      ]);
    });

    test('defines audio modes in spec order', () {
      expect(CompositionAudioMode.values, [
        CompositionAudioMode.keepOriginal,
        CompositionAudioMode.muted,
        CompositionAudioMode.originalPlusBgm,
        CompositionAudioMode.bgmOnly,
      ]);
    });

    test('defines bgm source types in spec order', () {
      expect(CompositionBgmSourceType.values, [
        CompositionBgmSourceType.localFile,
        CompositionBgmSourceType.attachment,
      ]);
    });

    test('defines export statuses in spec order', () {
      expect(CompositionExportStatus.values, [
        CompositionExportStatus.idle,
        CompositionExportStatus.preparing,
        CompositionExportStatus.trimming,
        CompositionExportStatus.composing,
        CompositionExportStatus.writing,
        CompositionExportStatus.success,
        CompositionExportStatus.failure,
        CompositionExportStatus.canceled,
      ]);
    });

    test('local clip factory uses local file source type', () {
      final clip = CompositionClip.local(
        id: 'clip-1',
        label: 'A.mp4',
        localUri: 'file:///tmp/a.mp4',
        fileName: 'A.mp4',
        startMs: 0,
        endMs: 1000,
      );

      expect(clip.sourceType, CompositionSourceType.localFile);
    });

    test('output defaults follow first clip resolution and ratio', () {
      expect(CompositionOutputSettings.defaults.resolution, 'follow-first');
      expect(CompositionOutputSettings.defaults.ratio, 'follow-first');
    });

    test('empty project uses default output and audio settings', () {
      expect(VideoCompositionProject.empty.clips, isEmpty);
      expect(
        VideoCompositionProject.empty.output,
        CompositionOutputSettings.defaults,
      );
      expect(
        VideoCompositionProject.empty.audio,
        CompositionAudioSettings.defaults,
      );
    });

    test('project copyWith updates a clip without mutating the original', () {
      final originalClip = CompositionClip.local(
        id: 'clip-1',
        label: 'A.mp4',
        localUri: 'file:///tmp/a.mp4',
        fileName: 'A.mp4',
        startMs: 0,
        endMs: 1000,
      );
      final project = VideoCompositionProject(
        clips: [originalClip],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      );

      final updatedProject = project.copyWith(
        clips: project.clips
            .map(
              (clip) => clip.id == 'clip-1'
                  ? clip.copyWith(startMs: 250, endMs: 1250)
                  : clip,
            )
            .toList(),
      );

      expect(project.clips.single.startMs, 0);
      expect(project.clips.single.endMs, 1000);
      expect(updatedProject.clips.single.startMs, 250);
      expect(updatedProject.clips.single.endMs, 1250);
      expect(updatedProject.clips.single, isNot(same(project.clips.single)));
    });

    test('original plus bgm and bgm only modes require bgm', () {
      expect(
        const CompositionAudioSettings(
          mode: CompositionAudioMode.originalPlusBgm,
        ).requiresBgm,
        isTrue,
      );
      expect(
        const CompositionAudioSettings(
          mode: CompositionAudioMode.bgmOnly,
        ).requiresBgm,
        isTrue,
      );
    });
  });

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
        audio: const CompositionAudioSettings(
          mode: CompositionAudioMode.bgmOnly,
        ),
      );

      expect(project.validationMessages, contains('请选择 BGM 音频。'));
      expect(project.canExport, isFalse);
    });

    test('requires local clips to have a local uri', () {
      final project = VideoCompositionProject(
        clips: const [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: '',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      );

      expect(project.validationMessages, contains('A.mp4 缺少本地视频文件。'));
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

  group('AppState composition clip operations', () {
    test('addCompositionClip appends a clip to the project', () {
      final state = AppState();
      final clip = _localClip('clip-1', 'A.mp4');

      state.addCompositionClip(clip);

      expect(state.compositionProject.clips, [clip]);
    });

    test('updateCompositionClip replaces the matching clip', () {
      final state = AppState();
      state.addCompositionClip(_localClip('clip-1', 'A.mp4'));

      state.updateCompositionClip(
        'clip-1',
        (clip) => clip.copyWith(startMs: 250, endMs: 1250),
      );

      final updatedClip = state.compositionProject.clips.single;
      expect(updatedClip.id, 'clip-1');
      expect(updatedClip.startMs, 250);
      expect(updatedClip.endMs, 1250);
    });

    test('removeCompositionClip removes the matching clip', () {
      final state = AppState();
      final firstClip = _localClip('clip-1', 'A.mp4');
      final secondClip = _localClip('clip-2', 'B.mp4');
      state.addCompositionClip(firstClip);
      state.addCompositionClip(secondClip);

      state.removeCompositionClip('clip-1');

      expect(state.compositionProject.clips, [secondClip]);
    });

    test(
      'duplicateCompositionClip inserts a labeled copy after the original',
      () {
        final state = AppState();
        final clip = _localClip('clip-1', 'A.mp4');
        state.addCompositionClip(clip);

        state.duplicateCompositionClip('clip-1');

        final clips = state.compositionProject.clips;
        expect(clips, hasLength(2));
        expect(clips.first, clip);
        expect(clips.last.label, 'A.mp4 副本');
        expect(clips.last.id, isNot(clip.id));
      },
    );

    test('moveCompositionClip moves the second clip up', () {
      final state = AppState();
      final firstClip = _localClip('clip-1', 'A.mp4');
      final secondClip = _localClip('clip-2', 'B.mp4');
      state.addCompositionClip(firstClip);
      state.addCompositionClip(secondClip);

      state.moveCompositionClip('clip-2', -1);

      expect(state.compositionProject.clips, [secondClip, firstClip]);
    });

    test(
      'addAttachmentVideoToComposition adds a local-ready library video',
      () async {
        final state = AppState();
        state.library
          ..clear()
          ..add(
            _attachment(
              id: 'asset-video-1',
              label: '素材视频',
              fileName: 'remote-name.mp4',
              localResourceUri: 'content://media/video/1',
              localFileName: 'local-name.mp4',
            ),
          );

        final added = await state.addAttachmentVideoToComposition(
          'asset-video-1',
        );

        expect(added, isTrue);
        expect(state.currentTab, AppTab.composition);
        final clip = state.compositionProject.clips.single;
        expect(clip.sourceType, CompositionSourceType.attachment);
        expect(clip.id, isNot('asset-video-1'));
        expect(clip.sourceId, 'asset-video-1');
        expect(clip.label, '素材视频');
        expect(clip.sourceUri, 'content://media/video/1');
        expect(clip.fileName, 'local-name.mp4');
        expect(clip.startMs, 0);
        expect(clip.endMs, 15000);
      },
    );

    test(
      'addTaskVideoToComposition adds a task video that is already local',
      () async {
        final now = DateTime(2026, 6, 14);
        final state = AppState();
        state.tasks
          ..clear()
          ..add(
            _task(
              id: 'task-video-1',
              createdAt: now,
              localResourceUri: 'content://media/video/task-1',
              localFileName: 'task-local.mp4',
              videoUrl: 'https://example.test/task.mp4',
            ),
          );

        final added = await state.addTaskVideoToComposition('task-video-1');

        expect(added, isTrue);
        expect(state.currentTab, AppTab.composition);
        final clip = state.compositionProject.clips.single;
        expect(clip.sourceType, CompositionSourceType.task);
        expect(clip.id, isNot('task-video-1'));
        expect(clip.sourceId, 'task-video-1');
        expect(clip.label, 'task-local.mp4');
        expect(clip.sourceUri, 'content://media/video/task-1');
        expect(clip.fileName, 'task-local.mp4');
        expect(clip.startMs, 0);
        expect(clip.endMs, 15000);
      },
    );
    test(
      'adding the same attachment video twice creates independently addressable clips',
      () async {
        final state = AppState();
        state.library
          ..clear()
          ..add(
            _attachment(
              id: 'asset-video-1',
              label: '素材视频',
              fileName: 'remote-name.mp4',
              localResourceUri: 'content://media/video/1',
              localFileName: 'local-name.mp4',
            ),
          );

        expect(
          await state.addAttachmentVideoToComposition('asset-video-1'),
          isTrue,
        );
        expect(
          await state.addAttachmentVideoToComposition('asset-video-1'),
          isTrue,
        );

        final clips = state.compositionProject.clips;
        expect(clips, hasLength(2));
        expect(clips.first.sourceId, 'asset-video-1');
        expect(clips.last.sourceId, 'asset-video-1');
        expect(clips.first.id, isNot(clips.last.id));

        state.removeCompositionClip(clips.first.id);

        expect(state.compositionProject.clips, [clips.last]);
      },
    );

    test(
      'adding the same task video twice creates independently addressable clips',
      () async {
        final now = DateTime(2026, 6, 14);
        final state = AppState();
        state.tasks
          ..clear()
          ..add(
            _task(
              id: 'task-video-1',
              createdAt: now,
              localResourceUri: 'content://media/video/task-1',
              localFileName: 'task-local.mp4',
              videoUrl: 'https://example.test/task.mp4',
            ),
          );

        expect(await state.addTaskVideoToComposition('task-video-1'), isTrue);
        expect(await state.addTaskVideoToComposition('task-video-1'), isTrue);

        final clips = state.compositionProject.clips;
        expect(clips, hasLength(2));
        expect(clips.first.sourceId, 'task-video-1');
        expect(clips.last.sourceId, 'task-video-1');
        expect(clips.first.id, isNot(clips.last.id));

        state.removeCompositionClip(clips.first.id);

        expect(state.compositionProject.clips, [clips.last]);
      },
    );

    test('exportComposition stores a successful native export result', () async {
      final service = _FakeVideoCompositionService(
        result: const CompositionExportResult(
          localPath: '/tmp/out.mp4',
          fileName: 'out.mp4',
          durationMs: 1000,
          width: 1920,
          height: 1080,
        ),
      );
      final state = AppState(videoCompositionService: service)
        ..addCompositionClip(_localClip('clip-1', 'A.mp4'));

      final exported = await state.exportComposition();

      expect(exported, isTrue);
      expect(service.exportedProject, state.compositionProject);
      expect(state.compositionExportStatus, CompositionExportStatus.success);
      expect(state.compositionExportProgress, 100);
      expect(state.compositionExportStage, '导出完成');
      expect(state.compositionExportResult?.localPath, '/tmp/out.mp4');
      expect(state.compositionExportErrorMessage, isNull);
    });

    test('exportComposition reports the first validation message', () async {
      final service = _FakeVideoCompositionService();
      final state = AppState(videoCompositionService: service);

      final exported = await state.exportComposition();

      expect(exported, isFalse);
      expect(service.exportedProject, isNull);
      expect(state.compositionExportErrorMessage, '至少添加 1 个视频片段。');
    });

    test('cancelCompositionExport cancels an in-progress export', () async {
      final service = _FakeVideoCompositionService();
      final state = AppState(videoCompositionService: service)
        ..compositionExportStatus = CompositionExportStatus.composing;

      await state.cancelCompositionExport();

      expect(service.cancelCount, 1);
      expect(state.compositionExportStatus, CompositionExportStatus.canceled);
      expect(state.compositionExportStage, '已取消');
    });
  });
}

class _FakeVideoCompositionService extends VideoCompositionService {
  _FakeVideoCompositionService({
    this.result = const CompositionExportResult(
      localPath: '/tmp/out.mp4',
      fileName: 'out.mp4',
      durationMs: 1000,
      width: 1920,
      height: 1080,
    ),
  });

  final CompositionExportResult result;
  VideoCompositionProject? exportedProject;
  int cancelCount = 0;

  @override
  Future<CompositionExportResult> export(VideoCompositionProject project) async {
    exportedProject = project;
    return result;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}

CompositionClip _localClip(String id, String label) {
  return CompositionClip.local(
    id: id,
    label: label,
    localUri: 'file:///tmp/$label',
    fileName: label,
    startMs: 0,
    endMs: 1000,
  );
}

Attachment _attachment({
  required String id,
  required String label,
  required String fileName,
  String? localResourceUri,
  String? localFileName,
  AttachmentKind kind = AttachmentKind.video,
}) {
  return Attachment(
    id: id,
    label: label,
    role: AttachmentRole.referenceVideo,
    kind: kind,
    fileName: fileName,
    category: '',
    createdAt: DateTime(2026, 6, 14),
    status: AttachmentStatus.uploaded,
    url: 'https://example.test/$fileName',
    localStatus: localResourceUri == null
        ? AttachmentLocalStatus.none
        : AttachmentLocalStatus.ready,
    localResourceUri: localResourceUri,
    localFileName: localFileName,
  );
}

TaskRecord _task({
  required String id,
  required DateTime createdAt,
  String? videoUrl,
  String? localResourceUri,
  String? localFileName,
  TaskKind kind = TaskKind.video,
}) {
  return TaskRecord(
    id: id,
    kind: kind,
    mode: ModeId.text,
    prompt: 'Task prompt',
    status: TaskStatus.success,
    pollingStatus: PollingStatus.idle,
    downloadStatus: localResourceUri == null
        ? DownloadStatus.idle
        : DownloadStatus.success,
    progress: 100,
    downloadProgress: localResourceUri == null ? 0 : 100,
    createdAt: createdAt,
    updatedAt: createdAt,
    estimatedCredit: 1,
    attachments: const [],
    requestPreview: '{}',
    responsePreview: '{}',
    videoUrl: videoUrl,
    localResourceUri: localResourceUri,
    localFileName: localFileName,
  );
}
