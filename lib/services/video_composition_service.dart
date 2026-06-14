import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';

import '../app/composition_models.dart';

typedef FfmpegRunner = Future<FfmpegRunResult> Function(List<String> arguments);
typedef FfmpegCancel = Future<void> Function();

class FfmpegRunResult {
  const FfmpegRunResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class VideoCompositionService {
  VideoCompositionService({FfmpegRunner? runner, FfmpegCancel? cancel})
    : _runner = runner ?? _runFfmpeg,
      _cancel = cancel ?? FFmpegKit.cancel;

  static const channel = MethodChannel('mova/video_composition');

  final FfmpegRunner _runner;
  final FfmpegCancel _cancel;

  Future<CompositionExportResult> export(VideoCompositionProject project) async {
    final outputDirectory = await Directory.systemTemp.createTemp(
      'mova-composition-',
    );
    final outputFileName = project.output.fileName.trim().isEmpty
        ? 'mova-composition.mp4'
        : project.output.fileName.trim();
    final outputPath = '${outputDirectory.path}/$outputFileName';
    if (project.clips.length == 1 &&
        project.clips.single.startMs == 0 &&
        project.audio.mode == CompositionAudioMode.keepOriginal) {
      await File(_localPathFromUri(project.clips.single.sourceUri)).copy(outputPath);
      return CompositionExportResult(
        localPath: outputPath,
        fileName: outputFileName,
        durationMs: project.durationMs,
        width: 0,
        height: 0,
      );
    }
    final arguments = _buildArguments(project, outputPath);
    final result = await _runner(arguments);
    if (!result.success) {
      throw PlatformException(
        code: 'export_failed',
        message: result.message.isEmpty ? '视频合成失败。' : result.message,
      );
    }
    return CompositionExportResult(
      localPath: outputPath,
      fileName: outputFileName,
      durationMs: project.durationMs,
      width: 0,
      height: 0,
    );
  }

  Future<void> cancel() => _cancel();

  List<String> _buildArguments(VideoCompositionProject project, String outputPath) {
    final clips = project.clips;
    if (clips.isEmpty) {
      throw PlatformException(code: 'invalid_project', message: '至少添加 1 个视频片段。');
    }

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
      final filter = _buildFilterGraph(project);
      args.addAll(['-filter_complex', filter, '-map', '[vout]']);
      if (project.audio.mode != CompositionAudioMode.muted) {
        args.addAll(['-map', '[aout]']);
      }
      args.addAll(['-c:v', 'libx264']);
      if (project.audio.mode != CompositionAudioMode.muted) {
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

  String _buildFilterGraph(VideoCompositionProject project) {
    final clips = project.clips;
    final parts = <String>[];
    for (var i = 0; i < clips.length; i++) {
      parts.add('[$i:v:0]setpts=PTS-STARTPTS[v$i]');
      if (project.audio.mode != CompositionAudioMode.muted &&
          project.audio.mode != CompositionAudioMode.bgmOnly) {
        parts.add(
          '[$i:a:0]asetpts=PTS-STARTPTS,volume=${project.audio.originalVolume}[a$i]',
        );
      }
    }

    final outputScale = _scaleFilter(project.output);
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
      if (project.audio.mode != CompositionAudioMode.muted &&
          project.audio.mode != CompositionAudioMode.bgmOnly) {
        final audioInputs = List.generate(clips.length, (index) => '[a$index]').join();
        parts.add('${audioInputs}concat=n=${clips.length}:v=0:a=1[abase]');
      }
    } else {
      final concatInputs = List.generate(clips.length, (index) {
        if (project.audio.mode == CompositionAudioMode.muted ||
            project.audio.mode == CompositionAudioMode.bgmOnly) {
          return '[v$index]';
        }
        return '[v$index][a$index]';
      }).join();
      if (project.audio.mode == CompositionAudioMode.muted ||
          project.audio.mode == CompositionAudioMode.bgmOnly) {
        parts.add('${concatInputs}concat=n=${clips.length}:v=1:a=0[vbase]');
      } else {
        parts.add('${concatInputs}concat=n=${clips.length}:v=1:a=1[vbase][abase]');
      }
      parts.add('[vbase]$outputScale[vout]');
    }

    switch (project.audio.mode) {
      case CompositionAudioMode.keepOriginal:
        parts.add('[abase]anull[aout]');
      case CompositionAudioMode.muted:
        break;
      case CompositionAudioMode.originalPlusBgm:
        final bgmIndex = clips.length;
        parts.add('[$bgmIndex:a:0]volume=${project.audio.bgmVolume}[bgm]');
        parts.add('[abase][bgm]amix=inputs=2:duration=first:dropout_transition=2[aout]');
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

  String _scaleFilter(CompositionOutputSettings output) {
    final size = switch (output.resolution) {
      '1080p' => '1920:1080',
      '720p' => '1280:720',
      _ => null,
    };
    if (size == null) return 'format=yuv420p';
    return 'scale=$size:force_original_aspect_ratio=decrease,pad=$size:(ow-iw)/2:(oh-ih)/2,format=yuv420p';
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

  String _localPathFromUri(String value) {
    if (value.startsWith('file://')) {
      return Uri.parse(value).toFilePath();
    }
    return value;
  }

  String _seconds(int milliseconds) => (milliseconds / 1000).toStringAsFixed(3);
}
