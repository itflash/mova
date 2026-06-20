import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';
import 'package:mova/app/composition_models.dart';
import 'package:mova/services/video_composition_service.dart';

void main() {
  late Directory fixturesDir;
  late File clipA;
  late File clipB;

  setUp(() {
    fixturesDir = Directory.systemTemp.createTempSync('mova-svc-test-');
    clipA = File('${fixturesDir.path}/a.mp4')..writeAsBytesSync([0]);
    clipB = File('${fixturesDir.path}/b.mp4')..writeAsBytesSync([0]);
  });

  tearDown(() {
    if (fixturesDir.existsSync()) {
      fixturesDir.deleteSync(recursive: true);
    }
  });

  test('export maps a multi-clip project to ffmpeg arguments', () async {
    List<String>? capturedArguments;
    final service = VideoCompositionService(
      runner: (arguments) async {
        capturedArguments = arguments;
        return const FfmpegRunResult(success: true, message: '');
      },
      prober: (_) async => null,
    );

    final result = await service.export(
      VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file://${clipA.path}',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
          CompositionClip.local(
            id: 'clip-2',
            label: 'B.mp4',
            localUri: 'file://${clipB.path}',
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
    expect(capturedArguments, contains(clipA.path));
    expect(capturedArguments, contains(clipB.path));
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
      prober: (_) async => null,
    );

    await service.export(
      VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file://${clipA.path}',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 5000,
            transitionType: CompositionTransitionType.crossDissolve,
            transitionDurationMs: 1000,
          ),
          CompositionClip.local(
            id: 'clip-2',
            label: 'B.mp4',
            localUri: 'file://${clipB.path}',
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
      prober: (_) async => null,
    );

    expect(
      () => service.export(
        VideoCompositionProject(
          clips: [
            CompositionClip.local(
              id: 'clip-1',
              label: 'A.mp4',
              localUri: 'file://${clipA.path}',
              fileName: 'A.mp4',
              startMs: 0,
              endMs: 1000,
            ),
            CompositionClip.local(
              id: 'clip-2',
              label: 'B.mp4',
              localUri: 'file://${clipB.path}',
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

  test('throws a friendly error when a source file is missing', () async {
    final service = VideoCompositionService(
      runner: (_) async => const FfmpegRunResult(success: true, message: ''),
      prober: (_) async => null,
    );

    expect(
      () => service.export(
        const VideoCompositionProject(
          clips: [
            CompositionClip.local(
              id: 'clip-1',
              label: '镜头一',
              localUri: 'file:///tmp/does-not-exist-mova.mp4',
              fileName: 'A.mp4',
              startMs: 0,
              endMs: 1000,
            ),
            CompositionClip.local(
              id: 'clip-2',
              label: '镜头二',
              localUri: 'file:///tmp/also-missing-mova.mp4',
              fileName: 'B.mp4',
              startMs: 0,
              endMs: 1000,
            ),
          ],
          output: CompositionOutputSettings.defaults,
          audio: CompositionAudioSettings.defaults,
        ),
      ),
      throwsA(predicate((error) => error.toString().contains('镜头一'))),
    );
  });

  test('explicit 1080p resolution normalizes every clip to 1920:1080', () async {
    List<String>? capturedArguments;
    final service = VideoCompositionService(
      runner: (arguments) async {
        capturedArguments = arguments;
        return const FfmpegRunResult(success: true, message: '');
      },
      prober: (_) async => null,
    );

    await service.export(
      VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file://${clipA.path}',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
          CompositionClip.local(
            id: 'clip-2',
            label: 'B.mp4',
            localUri: 'file://${clipB.path}',
            fileName: 'B.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults.copyWith(
          resolution: '1080p',
        ),
        audio: const CompositionAudioSettings(mode: CompositionAudioMode.muted),
      ),
    );

    final filterIndex = capturedArguments!.indexOf('-filter_complex');
    expect(filterIndex, isNonNegative);
    final filter = capturedArguments![filterIndex + 1];
    expect(filter, contains('scale=1920:1080'));
    expect(filter, contains('pad=1920:1080'));
  });

  test('follow-first probes the first clip and locks every clip to it', () async {
    final probedPaths = <String>[];
    List<String>? capturedArguments;
    final service = VideoCompositionService(
      runner: (arguments) async {
        capturedArguments = arguments;
        return const FfmpegRunResult(success: true, message: '');
      },
      prober: (path) async {
        probedPaths.add(path);
        if (path == clipA.path) {
          return _FakeMediaInformation(width: 1280, height: 720);
        }
        return _FakeMediaInformation(width: 640, height: 480);
      },
    );

    await service.export(
      VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file://${clipA.path}',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
          CompositionClip.local(
            id: 'clip-2',
            label: 'B.mp4',
            localUri: 'file://${clipB.path}',
            fileName: 'B.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        audio: const CompositionAudioSettings(mode: CompositionAudioMode.muted),
      ),
    );

    expect(probedPaths, contains(clipA.path));
    final filter = capturedArguments![capturedArguments!.indexOf('-filter_complex') + 1];
    expect(filter, contains('scale=1280:720'));
  });

  test('skips clip audio inputs when a clip has no audio stream', () async {
    List<String>? capturedArguments;
    final service = VideoCompositionService(
      runner: (arguments) async {
        capturedArguments = arguments;
        return const FfmpegRunResult(success: true, message: '');
      },
      prober: (path) async {
        if (path == clipA.path) {
          return _FakeMediaInformation(width: 1920, height: 1080);
        }
        // clipB has no audio stream
        return _FakeMediaInformation(
          width: 1920,
          height: 1080,
          includeAudio: false,
        );
      },
    );

    await service.export(
      VideoCompositionProject(
        clips: [
          CompositionClip.local(
            id: 'clip-1',
            label: 'A.mp4',
            localUri: 'file://${clipA.path}',
            fileName: 'A.mp4',
            startMs: 0,
            endMs: 1000,
          ),
          CompositionClip.local(
            id: 'clip-2',
            label: 'B.mp4',
            localUri: 'file://${clipB.path}',
            fileName: 'B.mp4',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        output: CompositionOutputSettings.defaults,
        // keepOriginal but a clip is silent -> graph should fall back to v-only
        audio: CompositionAudioSettings.defaults,
      ),
    );

    final filter = capturedArguments![capturedArguments!.indexOf('-filter_complex') + 1];
    expect(filter, isNot(contains('[0:a:0]')));
    expect(filter, isNot(contains('[1:a:0]')));
    // Output mapping should not include [aout] when there is no audio.
    expect(capturedArguments, isNot(contains('[aout]')));
  });
}

/// Fake MediaInformation backed by a synthetic property map matching the
/// shape ffprobe returns: {streams: [{codec_type, width, height}, ...]}.
class _FakeMediaInformation implements MediaInformation {
  _FakeMediaInformation({
    required this.width,
    required this.height,
    this.includeAudio = true,
  });

  final int width;
  final int height;
  final bool includeAudio;

  @override
  List<StreamInformation> getStreams() {
    return [
      StreamInformation({
        'codec_type': 'video',
        'width': width,
        'height': height,
      }),
      if (includeAudio)
        StreamInformation({
          'codec_type': 'audio',
          'sample_rate': '44100',
        }),
    ];
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
