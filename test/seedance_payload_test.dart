import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/mock_data.dart';
import 'package:mova/app/models.dart';
import 'package:mova/services/seedance_service.dart';

void main() {
  test('replaces prompt mention placeholders with ordered image tokens', () {
    final first = Attachment(
      id: 'first',
      label: 'storyboard-a.png',
      role: AttachmentRole.referenceImage,
      kind: AttachmentKind.image,
      fileName: 'storyboard-a.png',
      category: '分镜',
      createdAt: DateTime(2026),
      status: AttachmentStatus.uploaded,
      url: 'https://cdn.example.com/a.png',
    );
    final second = Attachment(
      id: 'second',
      label: 'storyboard-b.png',
      role: AttachmentRole.referenceImage,
      kind: AttachmentKind.image,
      fileName: 'storyboard-b.png',
      category: '分镜',
      createdAt: DateTime(2026),
      status: AttachmentStatus.uploaded,
      url: 'https://cdn.example.com/b.png',
    );

    final params = buildExecuteParams(
      prompt: '先参考 @{storyboard-b.png}，再转到 @{storyboard-a.png}',
      metadata: metadataDefaults,
      attachments: [first, second],
      inputProperties: fallbackToolForMode(ModeId.reference).inputProperties,
    );

    expect(params['prompt'], '先参考 @Image1，再转到 @Image2');
    expect(params['image_urls'], [
      'https://cdn.example.com/b.png',
      'https://cdn.example.com/a.png',
    ]);
  });
}
