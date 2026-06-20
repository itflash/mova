import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/models.dart';

void main() {
  group('groupAttachmentsByTask', () {
    test('keeps single attachments flat as non-task groups', () {
      final attachments = [
        _attachment(id: 'a1', sourceTaskId: null),
      ];
      final groups = groupAttachmentsByTask(attachments);
      expect(groups.length, 1);
      expect(groups.single.isTaskGroup, isFalse);
      expect(groups.single.items, [attachments.first]);
      expect(groups.single.representative, attachments.first);
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
      expect(groups.single.items.map((a) => a.id), ['a1', 'a2', 'a3']);
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
      expect(groups[1].items.map((a) => a.id), ['a1', 'a2']);
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
