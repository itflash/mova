import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/composition_models.dart';
import 'package:mova/services/video_composition_service.dart';

void main() {
  test('export maps a multi-clip project to ffmpeg arguments', () async {
    List<String>? capturedArguments;
    final service = VideoCompositionService(
      runner: (arguments) async {
        capturedArguments = arguments;
        return const FfmpegRunResult(success: true, message: '');
      },
    );

    final result = await service.export(
      VideoCompositionProject(
        clips: const [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file:///tmp/a.mp4',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
          CompositionClip.local(
            id: 'clip-2',
            label: 'B.mp4',
            localUri: 'file:///tmp/b.mp4',
            fileName: 'B.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: CompositionAudioSettings.defaults,
      ),
    );

    expect(capturedArguments, isNotNull);
    expect(capturedArguments, containsAll(['-ss', '0.000', '-to', '1.000']));
    expect(capturedArguments, contains('/tmp/a.mp4'));
    expect(capturedArguments, contains('/tmp/b.mp4'));
    expect(capturedArguments!.last, endsWith('mova-composition.mp4'));
    expect(result.fileName, 'mova-composition.mp4');
    expect(result.durationMs, 2000);
  });

  test('uses xfade when a clip has a transition', () async {
    List<String>? capturedArguments;
    final service = VideoCompositionService(
      runner: (arguments) async {
        capturedArguments = arguments;
        return const FfmpegRunResult(success: true, message: '');
      },
    );

    await service.export(
      VideoCompositionProject(
        clips: const [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file:///tmp/a.mp4',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 5000,
            transitionType: CompositionTransitionType.crossDissolve,
            transitionDurationMs: 1000,
          ),
          CompositionClip.local(
            id: 'clip-2',
            label: 'B.mp4',
            localUri: 'file:///tmp/b.mp4',
            fileName: 'B.mp4',
            startMs: 0,
            endMs: 5000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: const CompositionAudioSettings(mode: CompositionAudioMode.muted),
      ),
    );

    final filter = capturedArguments![capturedArguments!.indexOf('-filter_complex') + 1];
    expect(filter, contains('xfade=transition=fade'));
    expect(filter, contains('duration=1.000'));
    expect(filter, contains('offset=4.000'));
  });

  test('throws platform exception when ffmpeg fails', () async {
    final service = VideoCompositionService(
      runner: (_) async => const FfmpegRunResult(
        success: false,
        message: 'bad input',
      ),
    );

    expect(
      () => service.export(
        VideoCompositionProject(
          clips: const [
            CompositionClip.local(
              id: 'clip-1',
              label: 'A.mp4',
              localUri: 'file:///tmp/a.mp4',
              fileName: 'A.mp4',
              startMs: 0,
              endMs: 1000,
            ),
            CompositionClip.local(
              id: 'clip-2',
              label: 'B.mp4',
              localUri: 'file:///tmp/b.mp4',
              fileName: 'B.mp4',
              startMs: 0,
              endMs: 1000,
            ),
          ],
          output: CompositionOutputSettings.defaults,
          audio: CompositionAudioSettings.defaults,
        ),
      ),
      throwsA(predicate((error) => error.toString().contains('bad input'))),
    );
  });
}
