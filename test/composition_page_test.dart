import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/app.dart';
import 'package:mova/app/app_scope.dart';
import 'package:mova/app/app_state.dart';
import 'package:mova/app/composition_models.dart';
import 'package:mova/app/models.dart';
import 'package:mova/pages/home_shell.dart';
import 'package:mova/pages/library_page.dart';
import 'package:mova/services/video_composition_service.dart';

void main() {
  testWidgets('opens the composition page from the bottom navigation', (
    tester,
  ) async {
    final state = AppState();

    await tester.pumpWidget(
      AppScope(state: state, child: const SeedanceNativeApp()),
    );

    expect(find.text('剪辑'), findsOneWidget);

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();

    expect(find.text('视频剪辑'), findsOneWidget);
    expect(find.text('添加视频片段'), findsOneWidget);
  });

  testWidgets('shows clip editing controls for local composition clips', (
    tester,
  ) async {
    final state = AppState()
      ..addCompositionClip(
        const CompositionClip.local(
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
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();

    expect(find.text('A.mp4'), findsOneWidget);
    expect(find.byTooltip('裁剪片段'), findsOneWidget);
    expect(find.byTooltip('上移片段'), findsOneWidget);
    expect(find.byTooltip('下移片段'), findsOneWidget);
    expect(find.byTooltip('删除片段'), findsOneWidget);
    expect(find.text('转场'), findsOneWidget);
  });

  testWidgets('opens clip trim sheet with start and end controls', (
    tester,
  ) async {
    final state = AppState()
      ..addCompositionClip(
        const CompositionClip.local(
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
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('裁剪片段'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('裁剪片段'));
    await tester.pumpAndSettle();

    expect(find.text('裁剪片段'), findsOneWidget);
    expect(find.text('设为开始'), findsOneWidget);
    expect(find.text('设为结束'), findsOneWidget);
    expect(find.text('保存裁剪'), findsOneWidget);
  });

  testWidgets('exposes accessible add local video action', (tester) async {
    final state = AppState();

    await tester.pumpWidget(
      AppScope(state: state, child: const SeedanceNativeApp()),
    );

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('添加本地视频'), findsOneWidget);
  });

  testWidgets('exposes tooltip on library video add to composition action', (
    tester,
  ) async {
    final state = AppState()
      ..library.add(
        Attachment(
          id: 'video-1',
          label: 'Demo video',
          role: AttachmentRole.referenceVideo,
          kind: AttachmentKind.video,
          fileName: 'demo.mp4',
          category: '',
          createdAt: DateTime(2026),
          status: AttachmentStatus.uploaded,
          url: 'file:///tmp/demo.mp4',
          localStatus: AttachmentLocalStatus.ready,
          localResourceUri: 'file:///tmp/demo.mp4',
        ),
      );

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('添加到剪辑'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('添加到剪辑'), findsOneWidget);
    expect(find.byTooltip('添加到剪辑'), findsOneWidget);
  });

  testWidgets('shows output and audio controls on the composition page', (
    tester,
  ) async {
    final state = AppState();

    await tester.pumpWidget(
      AppScope(state: state, child: const SeedanceNativeApp()),
    );

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();

    expect(find.text('输出设置'), findsOneWidget);
    expect(find.text('跟随首个片段'), findsAtLeastNWidgets(1));

    await tester.ensureVisible(find.text('音频'));
    await tester.pumpAndSettle();

    expect(find.text('音频'), findsOneWidget);
    expect(find.text('保留原声'), findsOneWidget);
    expect(find.text('选择 BGM'), findsOneWidget);
  });

  testWidgets('export button exports composition and shows result', (
    tester,
  ) async {
    final state =
        AppState(
          videoCompositionService: _FakeVideoCompositionService(
            result: const CompositionExportResult(
              localPath: '/tmp/out.mp4',
              fileName: 'out.mp4',
              durationMs: 1000,
              width: 1920,
              height: 1080,
            ),
          ),
        )..addCompositionClip(
          const CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file:///tmp/a.mp4',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        );

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('导出合成视频'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出合成视频'));
    await tester.pumpAndSettle();

    expect(state.compositionExportResult?.fileName, 'out.mp4');
    expect(find.text('已导出：out.mp4'), findsOneWidget);
    expect(find.text('保存到相册/文件'), findsOneWidget);
    expect(find.text('导入素材库'), findsOneWidget);
  });

  testWidgets('composition page remains usable with large text scale', (
    tester,
  ) async {
    final state = AppState();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: AppScope(state: state, child: const SeedanceNativeApp()),
      ),
    );

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();

    expect(find.text('视频剪辑'), findsOneWidget);
    expect(find.text('添加视频片段'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('导出合成视频'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('导出合成视频'), findsOneWidget);
  });
}

class _FakeVideoCompositionService extends VideoCompositionService {
  _FakeVideoCompositionService({required this.result});

  final CompositionExportResult result;

  @override
  Future<CompositionExportResult> export(
    VideoCompositionProject project,
  ) async {
    return result;
  }
}
