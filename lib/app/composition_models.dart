enum CompositionSourceType { localFile, attachment, task }

enum CompositionTransitionType { none, fade, crossDissolve, black, whiteFlash }

enum CompositionAudioMode { keepOriginal, muted, originalPlusBgm, bgmOnly }

enum CompositionBgmSourceType { localFile, attachment }

enum CompositionExportStatus {
  idle,
  preparing,
  trimming,
  composing,
  writing,
  success,
  failure,
  canceled,
}

class CompositionClip {
  const CompositionClip({
    required this.id,
    required this.label,
    required this.sourceType,
    required this.sourceUri,
    required this.fileName,
    required this.startMs,
    required this.endMs,
    this.sourceId,
    this.transitionType = CompositionTransitionType.none,
    this.transitionDurationMs = 0,
  });

  const CompositionClip.local({
    required String id,
    required String label,
    required String localUri,
    required String fileName,
    required int startMs,
    required int endMs,
    CompositionTransitionType transitionType = CompositionTransitionType.none,
    int transitionDurationMs = 0,
  }) : this(
         id: id,
         label: label,
         sourceType: CompositionSourceType.localFile,
         sourceUri: localUri,
         fileName: fileName,
         startMs: startMs,
         endMs: endMs,
         transitionType: transitionType,
         transitionDurationMs: transitionDurationMs,
       );

  final String id;
  final String label;
  final CompositionSourceType sourceType;
  final String sourceUri;
  final String fileName;
  final int startMs;
  final int endMs;
  final String? sourceId;
  final CompositionTransitionType transitionType;
  final int transitionDurationMs;

  int get durationMs => endMs - startMs;

  CompositionClip copyWith({
    String? id,
    String? label,
    CompositionSourceType? sourceType,
    String? sourceUri,
    String? fileName,
    int? startMs,
    int? endMs,
    String? sourceId,
    bool clearSourceId = false,
    CompositionTransitionType? transitionType,
    int? transitionDurationMs,
  }) {
    return CompositionClip(
      id: id ?? this.id,
      label: label ?? this.label,
      sourceType: sourceType ?? this.sourceType,
      sourceUri: sourceUri ?? this.sourceUri,
      fileName: fileName ?? this.fileName,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      sourceId: clearSourceId ? null : (sourceId ?? this.sourceId),
      transitionType: transitionType ?? this.transitionType,
      transitionDurationMs: transitionDurationMs ?? this.transitionDurationMs,
    );
  }
}

class CompositionOutputSettings {
  const CompositionOutputSettings({
    required this.resolution,
    required this.ratio,
    required this.fps,
    required this.bitrateKbps,
    required this.fileName,
  });

  static const defaults = CompositionOutputSettings(
    resolution: 'follow-first',
    ratio: 'follow-first',
    fps: 30,
    bitrateKbps: 8000,
    fileName: 'mova-composition.mp4',
  );

  final String resolution;
  final String ratio;
  final int fps;
  final int bitrateKbps;
  final String fileName;

  CompositionOutputSettings copyWith({
    String? resolution,
    String? ratio,
    int? fps,
    int? bitrateKbps,
    String? fileName,
  }) {
    return CompositionOutputSettings(
      resolution: resolution ?? this.resolution,
      ratio: ratio ?? this.ratio,
      fps: fps ?? this.fps,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      fileName: fileName ?? this.fileName,
    );
  }
}

class CompositionBgmSource {
  const CompositionBgmSource({
    required this.id,
    required this.label,
    required this.sourceType,
    required this.sourceUri,
    required this.fileName,
  });

  const CompositionBgmSource.local({
    required String id,
    required String label,
    required String localUri,
    required String fileName,
  }) : this(
         id: id,
         label: label,
         sourceType: CompositionBgmSourceType.localFile,
         sourceUri: localUri,
         fileName: fileName,
       );

  final String id;
  final String label;
  final CompositionBgmSourceType sourceType;
  final String sourceUri;
  final String fileName;

  CompositionBgmSource copyWith({
    String? id,
    String? label,
    CompositionBgmSourceType? sourceType,
    String? sourceUri,
    String? fileName,
  }) {
    return CompositionBgmSource(
      id: id ?? this.id,
      label: label ?? this.label,
      sourceType: sourceType ?? this.sourceType,
      sourceUri: sourceUri ?? this.sourceUri,
      fileName: fileName ?? this.fileName,
    );
  }
}

class CompositionAudioSettings {
  const CompositionAudioSettings({
    this.mode = CompositionAudioMode.keepOriginal,
    this.bgmSource,
    this.originalVolume = 1.0,
    this.bgmVolume = 1.0,
  });

  static const defaults = CompositionAudioSettings();

  final CompositionAudioMode mode;
  final CompositionBgmSource? bgmSource;
  final double originalVolume;
  final double bgmVolume;

  bool get requiresBgm {
    return mode == CompositionAudioMode.originalPlusBgm ||
        mode == CompositionAudioMode.bgmOnly;
  }

  CompositionAudioSettings copyWith({
    CompositionAudioMode? mode,
    CompositionBgmSource? bgmSource,
    double? originalVolume,
    double? bgmVolume,
    bool clearBgmSource = false,
  }) {
    return CompositionAudioSettings(
      mode: mode ?? this.mode,
      bgmSource: clearBgmSource ? null : (bgmSource ?? this.bgmSource),
      originalVolume: originalVolume ?? this.originalVolume,
      bgmVolume: bgmVolume ?? this.bgmVolume,
    );
  }
}

class VideoCompositionProject {
  const VideoCompositionProject({
    required this.clips,
    required this.output,
    required this.audio,
  });

  static const empty = VideoCompositionProject(
    clips: [],
    output: CompositionOutputSettings.defaults,
    audio: CompositionAudioSettings.defaults,
  );

  final List<CompositionClip> clips;
  final CompositionOutputSettings output;
  final CompositionAudioSettings audio;

  bool get canExport => validationMessages.isEmpty;

  List<String> get validationMessages {
    final messages = <String>[];

    if (clips.isEmpty) {
      messages.add('至少添加 1 个视频片段。');
    }

    for (final clip in clips) {
      if (clip.sourceType == CompositionSourceType.localFile &&
          clip.sourceUri.trim().isEmpty) {
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

  int get durationMs {
    return clips.fold(0, (total, clip) => total + clip.durationMs);
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
