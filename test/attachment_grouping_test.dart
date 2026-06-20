import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/app_state.dart';
import 'package:mova/app/models.dart';

void main() {
  group('groupAttachmentsByTask', () {
    test('keeps single attachments flat as non-task groups', () {
      final attachments = [_attachment(id: 'a1', sourceTaskId: null)];
      final groups = groupAttachmentsByTask(attachments);
      expect(groups.length, 1);
      expect(groups.single.isTaskGroup, isFalse);
      expect(groups.single.items, [attachments.first]);
    });

    test('collapses same-task attachments into one task group', () {
      final attachments = [
        _attachment(id: 'a1', sourceTaskId: 'task-1'),
        _attachment(id: 'a2', sourceTaskId: 'task-1'),
        _attachment(id: 'a3', sourceTaskId: 'task-1'),
      ];
      final groups = groupAttachmentsByTask(attachments);
      expect(groups.length, 1);
      expect(groups.single.isTaskGroup, isTrue);
      expect(groups.single.count, 3);
      expect(groups.single.representative.id, 'a1');
      expect(groups.single.taskId, 'task-1');
    });

    test('keeps group position at the first occurrence of each task', () {
      final attachments = [
        _attachment(id: 'solo', sourceTaskId: null),
        _attachment(id: 'a1', sourceTaskId: 'task-1'),
        _attachment(id: 'b1', sourceTaskId: 'task-2'),
        _attachment(id: 'a2', sourceTaskId: 'task-1'),
      ];
      final groups = groupAttachmentsByTask(attachments);
      expect(groups.length, 3);
      expect(groups[0].isTaskGroup, isFalse);
      expect(groups[0].representative.id, 'solo');
      expect(groups[1].isTaskGroup, isTrue);
      expect(groups[1].taskId, 'task-1');
      expect(groups[1].count, 2);
      expect(groups[2].isTaskGroup, isFalse);
      expect(groups[2].representative.id, 'b1');
    });

    test('treats attachments without sourceTaskId independently', () {
      final attachments = [
        _attachment(id: 'a1', sourceTaskId: null),
        _attachment(id: 'a2', sourceTaskId: null),
      ];
      final groups = groupAttachmentsByTask(attachments);
      expect(groups.length, 2);
      expect(groups.every((g) => !g.isTaskGroup), isTrue);
    });

    test('handles an empty list', () {
      expect(groupAttachmentsByTask([]), isEmpty);
    });
  });

  group('buildAttachmentTaskIdIndex', () {
    test('maps image result attachment ids to their task id', () {
      final tasks = [
        _imageTask(
          id: 'task-1',
          resultAttachmentIds: const ['a1', 'a2'],
        ),
        _imageTask(
          id: 'task-2',
          resultAttachmentIds: const ['b1'],
        ),
      ];
      final index = AppState.buildAttachmentTaskIdIndex(tasks);
      expect(index, {
        'a1': 'task-1',
        'a2': 'task-1',
        'b1': 'task-2',
      });
    });

    test('ignores non-image tasks', () {
      final tasks = [
        _imageTask(id: 'img-1', resultAttachmentIds: const ['a1']),
        _videoTask(id: 'vid-1'),
      ];
      final index = AppState.buildAttachmentTaskIdIndex(tasks);
      expect(index, {'a1': 'img-1'});
    });

    test('keeps the first task when an attachment id repeats', () {
      final tasks = [
        _imageTask(id: 'task-1', resultAttachmentIds: const ['a1']),
        _imageTask(id: 'task-2', resultAttachmentIds: const ['a1']),
      ];
      final index = AppState.buildAttachmentTaskIdIndex(tasks);
      expect(index['a1'], 'task-1');
    });

    test('skips image results without an attachment id', () {
      final tasks = [
        _imageTask(id: 'task-1', resultAttachmentIds: const ['a1', null]),
      ];
      final index = AppState.buildAttachmentTaskIdIndex(tasks);
      expect(index, {'a1': 'task-1'});
    });
  });

  group('backfill + grouping integration', () {
    test('backfilled taskId lets historical attachments group by task', () {
      // 模拟历史素材：sourceTaskId 为 null，但任务记录里有 attachmentId 反查关系。
      final tasks = [
        _imageTask(id: 'task-1', resultAttachmentIds: const ['a1', 'a2']),
      ];
      final index = AppState.buildAttachmentTaskIdIndex(tasks);

      final attachments = [
        _attachment(id: 'a1', sourceTaskId: null),
        _attachment(id: 'a2', sourceTaskId: null),
        _attachment(id: 'solo', sourceTaskId: null),
      ];

      // 回填前：全是单素材组
      expect(groupAttachmentsByTask(attachments).length, 3);

      // 模拟回填
      final backfilled = attachments
          .map((a) => a.sourceTaskId == null
              ? a.copyWith(sourceTaskId: index[a.id])
              : a)
          .toList();

      // 回填后：task-1 的两张合成一组，solo 保持单卡
      final groups = groupAttachmentsByTask(backfilled);
      expect(groups.length, 2);
      expect(groups[0].isTaskGroup, isTrue);
      expect(groups[0].taskId, 'task-1');
      expect(groups[0].count, 2);
      expect(groups[1].isTaskGroup, isFalse);
      expect(groups[1].representative.id, 'solo');
    });
  });
}

Attachment _attachment({
  required String id,
  String? sourceTaskId,
}) {
  return Attachment(
    id: id,
    label: id,
    role: AttachmentRole.referenceImage,
    kind: AttachmentKind.image,
    fileName: '$id.png',
    category: '',
    createdAt: DateTime(2024, 1, 1),
    status: AttachmentStatus.uploaded,
    url: 'https://example.com/$id.png',
    sourceTaskId: sourceTaskId,
  );
}

TaskRecord _imageTask({
  required String id,
  required List<String?> resultAttachmentIds,
}) {
  final now = DateTime(2024, 1, 1);
  return TaskRecord(
    id: id,
    kind: TaskKind.image,
    mode: ModeId.text,
    prompt: 'image task',
    status: TaskStatus.success,
    pollingStatus: PollingStatus.idle,
    downloadStatus: DownloadStatus.idle,
    progress: 100,
    createdAt: now,
    updatedAt: now,
    estimatedCredit: 1,
    attachments: const [],
    requestPreview: '{}',
    responsePreview: '{}',
    imageResults: [
      for (var i = 0; i < resultAttachmentIds.length; i++)
        ImageTaskResultItem(
          id: '$id-result-$i',
          status: ImageResultStatus.imported,
          attachmentId: resultAttachmentIds[i],
        ),
    ],
  );
}

TaskRecord _videoTask({required String id}) {
  final now = DateTime(2024, 1, 1);
  return TaskRecord(
    id: id,
    kind: TaskKind.video,
    mode: ModeId.text,
    prompt: 'video task',
    status: TaskStatus.success,
    pollingStatus: PollingStatus.idle,
    downloadStatus: DownloadStatus.idle,
    progress: 100,
    createdAt: now,
    updatedAt: now,
    estimatedCredit: 1,
    attachments: const [],
    requestPreview: '{}',
    responsePreview: '{}',
  );
}
