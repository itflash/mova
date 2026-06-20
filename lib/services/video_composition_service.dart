import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';

import '../app/composition_models.dart';

typedef FfmpegRunner = Future<FfmpegRunResult> Function(List<String> arguments);
typedef FfmpegCancel = Future<void> Function();
typedef FfmpegProbe = Future<MediaInformation?> Function(String path);

class FfmpegRunResult {
  const FfmpegRunResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class VideoCompositionService {
  VideoCompositionService({
    FfmpegRunner? runner,
    FfmpegCancel? cancel,
    FfmpegProbe? prober,
  })  : _runner = runner ?? _runFfmpeg,
        _cancel = cancel ?? FFmpegKit.cancel,
        _prober = prober ?? _probeMedia;

  static const channel = MethodChannel('mova/video_composition');

  final FfmpegRunner _runner;
  final FfmpegCancel _cancel;
  final FfmpegProbe _prober;

  Future<CompositionExportResult> export(VideoCompositionProject project) async {
    _ensureSourcesExist(project);
    final outputDirectory = await Directory.systemTemp.createTemp(
      'mova-composition-',
    );
    final outputFileName = project.output.fileName.trim().isEmpty
        ? 'mova-composition.mp4'
        : project.output.fileName.trim();
    final outputPath = '${outputDirectory.path}/$outputFileName';
    final targetSize = await _resolveTargetSize(project);
    if (project.clips.length == 1 &&
        project.clips.single.startMs == 0 &&
        project.audio.mode == CompositionAudioMode.keepOriginal) {
      final sourcePath = _localPathFromUri(project.clips.single.sourceUri);
      final clipSize = await _probeDimensions(sourcePath);
      final needsScale = targetSize != null &&
          clipSize != null &&
          (clipSize.$1 != _widthFromTarget(targetSize) ||
              clipSize.$2 != _heightFromTarget(targetSize));
      if (targetSize == null || !needsScale) {
        await File(sourcePath).copy(outputPath);
      } else {
        final scaleArgs = [
          '-y',
          '-i',
          sourcePath,
          '-vf',
          _scalePadFilter(targetSize),
          '-c:v',
          'libx264',
          '-c:a',
          'aac',
          '-r',
          project.output.fps.toString(),
          '-b:v',
          '${project.output.bitrateKbps}k',
          outputPath,
        ];
        final scaleResult = await _runner(scaleArgs);
        if (!scaleResult.success) {
          throw PlatformException(
            code: 'export_failed',
            message: _friendlyFfmpegError(scaleResult.message),
          );
        }
      }
      final dims = await _probeDimensions(outputPath);
      return CompositionExportResult(
        localPath: outputPath,
        fileName: outputFileName,
        durationMs: project.durationMs,
        width: dims?.$1 ?? clipSize?.$1 ?? 0,
        height: dims?.$2 ?? clipSize?.$2 ?? 0,
      );
    }
    final arguments = await _buildArguments(project, outputPath, targetSize);
    final result = await _runner(arguments);
    if (!result.success) {
      throw PlatformException(
        code: 'export_failed',
        message: _friendlyFfmpegError(result.message),
      );
    }
    final dims = await _probeDimensions(outputPath);
    return CompositionExportResult(
      localPath: outputPath,
      fileName: outputFileName,
      durationMs: project.durationMs,
      width: dims?.$1 ?? 0,
      height: dims?.$2 ?? 0,
    );
  }

  Future<void> cancel() => _cancel();

  Future<List<String>> _buildArguments(
    VideoCompositionProject project,
    String outputPath,
    String? targetSize,
  ) async {
    final clips = project.clips;
    if (clips.isEmpty) {
      throw PlatformException(code: 'invalid_project', message: '至少添加 1 个视频片段。');
    }

    final hasAudioPerClip = await Future.wait(
      clips.map((clip) => _hasAudioStream(_localPathFromUri(clip.sourceUri))),
    );
    final wantsClipAudio =
        project.audio.mode != CompositionAudioMode.muted &&
            project.audio.mode != CompositionAudioMode.bgmOnly;
    final clipAudioReady = wantsClipAudio && hasAudioPerClip.every((b) => b);
    // keepOriginal + 无任何片段音轨 -> 视为 muted，避免 -map [aout] 失败。
    final hasOutputAudio =
        (project.audio.mode == CompositionAudioMode.keepOriginal && clipAudioReady) ||
            project.audio.mode == CompositionAudioMode.originalPlusBgm ||
            project.audio.mode == CompositionAudioMode.bgmOnly;

    final args = <String>['-y'];
    for (final clip in clips) {
      final sourcePath = _localPathFromUri(clip.sourceUri);
      if (sourcePath.trim().isEmpty) {
        throw PlatformException(
          code: 'invalid_clip',
          message: '${clip.label} 缺少本地视频文件。',
        );
      }
      args.addAll([
        '-ss',
        _seconds(clip.startMs),
        '-to',
        _seconds(clip.endMs),
        '-i',
        sourcePath,
      ]);
    }

    final bgm = project.audio.bgmSource;
    if (project.audio.requiresBgm && bgm != null) {
      args.addAll(['-i', _localPathFromUri(bgm.sourceUri)]);
    }

    if (clips.length == 1 && project.audio.mode == CompositionAudioMode.keepOriginal) {
      args.addAll(['-c:v', 'libx264', '-c:a', 'aac']);
    } else {
      final filter = _buildFilterGraph(
        project,
        targetSize: targetSize,
        clipAudioReady: clipAudioReady,
      );
      args.addAll(['-filter_complex', filter, '-map', '[vout]']);
      if (hasOutputAudio) {
        args.addAll(['-map', '[aout]']);
      }
      args.addAll(['-c:v', 'libx264']);
      if (hasOutputAudio) {
        args.addAll(['-c:a', 'aac']);
      }
    }

    args.addAll([
      '-r',
      project.output.fps.toString(),
      '-b:v',
      '${project.output.bitrateKbps}k',
      outputPath,
    ]);
    return args;
  }

  String _buildFilterGraph(
    VideoCompositionProject project, {
    required String? targetSize,
    required bool clipAudioReady,
  }) {
    final clips = project.clips;
    final parts = <String>[];
    final normalizeScale = _normalizeScaleFilterWith(project.output, targetSize);
    final useClipAudio = clipAudioReady &&
        project.audio.mode != CompositionAudioMode.muted &&
        project.audio.mode != CompositionAudioMode.bgmOnly;
    for (var i = 0; i < clips.length; i++) {
      parts.add('[$i:v:0]setpts=PTS-STARTPTS$normalizeScale[v$i]');
      if (useClipAudio) {
        parts.add(
          '[$i:a:0]asetpts=PTS-STARTPTS,volume=${project.audio.originalVolume}[a$i]',
        );
      }
    }

    final outputScale = _scaleFilterWith(targetSize);
    final hasVideoTransition = clips
        .take(clips.length - 1)
        .any((clip) => clip.transitionType != CompositionTransitionType.none);

    if (hasVideoTransition) {
      var currentLabel = 'v0';
      var elapsedSeconds = clips.first.durationMs / 1000;
      for (var i = 1; i < clips.length; i++) {
        final previous = clips[i - 1];
        final durationSeconds = _transitionDurationSeconds(previous);
        final transition = _xfadeTransition(previous.transitionType);
        final nextLabel = i == clips.length - 1 ? 'vbase' : 'vx$i';
        final offsetSeconds = (elapsedSeconds - durationSeconds).clamp(
          0,
          double.infinity,
        );
        parts.add(
          '[$currentLabel][v$i]xfade=transition=$transition:duration=${durationSeconds.toStringAsFixed(3)}:offset=${offsetSeconds.toStringAsFixed(3)}[$nextLabel]',
        );
        currentLabel = nextLabel;
        elapsedSeconds += clips[i].durationMs / 1000 - durationSeconds;
      }
      parts.add('[vbase]$outputScale[vout]');
      if (useClipAudio) {
        final audioInputs = List.generate(clips.length, (index) => '[a$index]').join();
        parts.add('${audioInputs}concat=n=${clips.length}:v=0:a=1[abase]');
      }
    } else {
      final concatInputs = List.generate(clips.length, (index) {
        if (!useClipAudio) {
          return '[v$index]';
        }
        return '[v$index][a$index]';
      }).join();
      if (!useClipAudio) {
        parts.add('${concatInputs}concat=n=${clips.length}:v=1:a=0[vbase]');
      } else {
        parts.add('${concatInputs}concat=n=${clips.length}:v=1:a=1[vbase][abase]');
      }
      parts.add('[vbase]$outputScale[vout]');
    }

    switch (project.audio.mode) {
      case CompositionAudioMode.keepOriginal:
        if (useClipAudio) {
          parts.add('[abase]anull[aout]');
        }
      case CompositionAudioMode.muted:
        break;
      case CompositionAudioMode.originalPlusBgm:
        final bgmIndex = clips.length;
        parts.add('[$bgmIndex:a:0]volume=${project.audio.bgmVolume}[bgm]');
        if (useClipAudio) {
          parts.add('[abase][bgm]amix=inputs=2:duration=first:dropout_transition=2[aout]');
        } else {
          // 没有片段音轨可混音，直接把 BGM 当主音轨。
          parts.removeLast();
          parts.add('[$bgmIndex:a:0]volume=${project.audio.bgmVolume}[aout]');
        }
      case CompositionAudioMode.bgmOnly:
        final bgmIndex = clips.length;
        parts.add('[$bgmIndex:a:0]volume=${project.audio.bgmVolume}[aout]');
    }

    return parts.join(';');
  }

  double _transitionDurationSeconds(CompositionClip clip) {
    final requested = clip.transitionDurationMs > 0 ? clip.transitionDurationMs : 800;
    final maxForClip = (clip.durationMs / 2).floor();
    return (requested.clamp(1, maxForClip) / 1000).toDouble();
  }

  String _xfadeTransition(CompositionTransitionType type) {
    return switch (type) {
      CompositionTransitionType.none => 'fade',
      CompositionTransitionType.fade => 'fade',
      CompositionTransitionType.crossDissolve => 'fade',
      CompositionTransitionType.black => 'fadeblack',
      CompositionTransitionType.whiteFlash => 'fadewhite',
    };
  }

  /// Final post-concat scale used on `[vbase]`. Once every clip has been
  /// normalized to the same size in `_normalizeScaleFilterWith`, this just
  /// preserves the working size and the pixel format.
  String _scaleFilterWith(String? targetSize) {
    if (targetSize == null) return 'format=yuv420p';
    return 'scale=$targetSize:force_original_aspect_ratio=decrease,'
        'pad=$targetSize:(ow-iw)/2:(oh-ih)/2,format=yuv420p';
  }

  /// Per-clip normalization filter (prepended with a leading comma so it can
  /// chain after `setpts=PTS-STARTPTS`).
  String _normalizeScaleFilterWith(
    CompositionOutputSettings output,
    String? targetSize,
  ) {
    if (targetSize != null) {
      return ',scale=$targetSize:force_original_aspect_ratio=decrease,'
          'pad=$targetSize:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p';
    }
    return ',scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1,format=yuv420p';
  }

  String _scalePadFilter(String size) {
    return 'scale=$size:force_original_aspect_ratio=decrease,'
        'pad=$size:(ow-iw)/2:(oh-ih)/2,format=yuv420p';
  }

  String? _ratioSize(String ratio) {
    return switch (ratio) {
      '16:9' => '1920:1080',
      '9:16' => '1080:1920',
      '1:1' => '1080:1080',
      '4:3' => '1440:1080',
      _ => null,
    };
  }

  String? _resolutionSize(String resolution) {
    return switch (resolution) {
      '1080p' => '1920:1080',
      '720p' => '1280:720',
      '480p' => '854:480',
      _ => null,
    };
  }

  /// Resolves the concrete `W:H` size used for normalization & output.
  /// Priority: explicit resolution -> explicit ratio -> probed first clip
  /// (so `follow-first` produces a consistent box across all clips).
  Future<String?> _resolveTargetSize(VideoCompositionProject project) async {
    final byResolution = _resolutionSize(project.output.resolution);
    if (byResolution != null) return byResolution;
    final byRatio = _ratioSize(project.output.ratio);
    if (byRatio != null) return byRatio;
    if (project.clips.isEmpty) return null;
    final firstSize = await _probeDimensions(
      _localPathFromUri(project.clips.first.sourceUri),
    );
    if (firstSize == null) return null;
    final w = firstSize.$1;
    final h = firstSize.$2;
    if (w <= 0 || h <= 0) return null;
    // Force even dimensions (libx264 requires it).
    final ew = w.isEven ? w : w - 1;
    final eh = h.isEven ? h : h - 1;
    return '$ew:$eh';
  }

  int _widthFromTarget(String size) {
    final parts = size.split(':');
    return int.tryParse(parts.first) ?? 0;
  }

  int _heightFromTarget(String size) {
    final parts = size.split(':');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  Future<(int, int)?> _probeDimensions(String path) async {
    try {
      final info = await _prober(path);
      if (info == null) return null;
      final streams = info.getStreams();
      for (final stream in streams) {
        if (stream.getType() == 'video') {
          final w = stream.getWidth() ?? 0;
          final h = stream.getHeight() ?? 0;
          if (w > 0 && h > 0) return (w, h);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasAudioStream(String path) async {
    try {
      final info = await _prober(path);
      if (info == null) return false;
      for (final stream in info.getStreams()) {
        if (stream.getType() == 'audio') return true;
      }
      return false;
    } catch (_) {
      // 探测失败时保守认为有音轨；若实际没有 ffmpeg 会再报错，再被 _friendlyFfmpegError 捕获。
      return true;
    }
  }

  /// Verifies every clip/BGM source file is still on disk before kicking off
  /// ffmpeg. Without this, missing files surface as a long ffmpeg log and the
  /// user has no idea which clip is broken.
  void _ensureSourcesExist(VideoCompositionProject project) {
    final missing = <String>[];
    for (final clip in project.clips) {
      final path = _localPathFromUri(clip.sourceUri);
      if (path.isEmpty || !File(path).existsSync()) {
        missing.add(clip.label);
      }
    }
    final bgm = project.audio.bgmSource;
    if (project.audio.requiresBgm && bgm != null) {
      final bgmPath = _localPathFromUri(bgm.sourceUri);
      if (bgmPath.isEmpty || !File(bgmPath).existsSync()) {
        missing.add(bgm.label);
      }
    }
    if (missing.isNotEmpty) {
      throw PlatformException(
        code: 'missing_source',
        message: '以下素材文件已不存在，请重新选择：${missing.join('、')}',
      );
    }
  }

  /// Translates raw ffmpeg log output into a short, user-friendly hint.
  String _friendlyFfmpegError(String raw) {
    final message = raw.trim();
    if (message.isEmpty) return '视频合成失败，请重试。';
    final lower = message.toLowerCase();
    if (lower.contains('does not contain any stream') ||
        lower.contains('stream specifier') ||
        lower.contains('matches no streams')) {
      return '某个视频片段缺少音频/视频轨，已尝试自动跳过。请将该片段替换或在「音频」中切换为静音/BGM 后重试。';
    }
    if (lower.contains('width and height of input videos must be even') ||
        lower.contains('width or height not divisible by 2')) {
      return '视频分辨率为奇数像素，编码器无法处理。请选择 720p / 1080p 或固定的比例后重试。';
    }
    if (lower.contains('do not match the corresponding output link') ||
        lower.contains('input link parameters') ||
        lower.contains('inputs have different size') ||
        lower.contains('filter input has different')) {
      return '多个片段的分辨率/比例不一致。请在「输出设置」选择固定的分辨率（如 1080p）或比例（如 16:9）后重试。';
    }
    if (lower.contains('no such file or directory') ||
        lower.contains('does not exist')) {
      return '找不到视频文件，请检查素材是否仍在本地，或重新选择素材。';
    }
    if (lower.contains('permission denied')) {
      return '没有访问视频文件的权限。请重新选择素材或检查系统权限设置。';
    }
    if (lower.contains('invalid data found when processing input') ||
        lower.contains('invalid argument')) {
      return '视频文件无法解析，可能已损坏。请更换素材后重试。';
    }
    if (lower.contains('out of memory') || lower.contains('cannot allocate')) {
      return '内存不足，导出失败。请减少片段数量或降低分辨率后重试。';
    }
    if (lower.contains('no space left on device') ||
        lower.contains('disk full')) {
      return '设备存储空间不足。请清理后重试。';
    }
    // Fallback: keep the last meaningful line of the log instead of dumping
    // hundreds of lines into the UI.
    final lines = message
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final tail = lines.isEmpty ? message : lines.last;
    return '视频合成失败：$tail';
  }

  static Future<FfmpegRunResult> _runFfmpeg(List<String> arguments) async {
    final session = await FFmpegKit.executeWithArguments(arguments);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      return const FfmpegRunResult(success: true, message: '');
    }
    final logs = await session.getAllLogsAsString();
    return FfmpegRunResult(success: false, message: logs ?? returnCode.toString());
  }

  static Future<MediaInformation?> _probeMedia(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      return session.getMediaInformation();
    } catch (_) {
      return null;
    }
  }

  String _localPathFromUri(String value) {
    if (value.startsWith('file://')) {
      return Uri.parse(value).toFilePath();
    }
    return value;
  }

  String _seconds(int milliseconds) => (milliseconds / 1000).toStringAsFixed(3);
}
