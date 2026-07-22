enum AppTab { create, library, composition, tasks, settings }

enum ModeId { text, firstFrame, firstLast, reference }

enum StorageProvider { qiniu, bitifulS4 }

/// 素材的来源。
///
/// - [library] 走用户自己的对象存储（七牛 / 缤纷云），永久保存并进素材库；
/// - [ephemeral] 走 AgentEarth 官方托管的临时通道，仅用于当次任务，不进素材库。
enum AttachmentSource { library, ephemeral }

enum AttachmentRole {
  firstFrame,
  lastFrame,
  referenceImage,
  referenceVideo,
  referenceAudio,
}

enum TaskKind { video, image }

enum TaskTab { video, image }

enum ImageCreateMode { textToImage, imageToImage }

enum ImageResultStatus {
  queued,
  generating,
  readyToTransfer,
  downloading,
  downloadFailed,
  uploading,
  uploadFailed,
  imported,
}

enum AttachmentKind { image, video, audio }

enum AttachmentStatus { queued, uploading, uploaded, error }

enum AttachmentLocalStatus { none, downloading, ready, error }

enum LibraryFilter { all, image, video, audio }

enum LibraryViewMode { comfortable, compact }

enum TaskStatus { submitted, inProgress, success, failure }

enum PollingStatus { idle, polling, paused, error }

enum DownloadStatus { idle, downloading, success, error }

enum ToolResolutionStatus { idle, loading, ready, error }

enum VideoFrameEntryContext { library, createFirstFrame, createLastFrame, task }

enum VideoFrameSourceType { localFile, attachment, task }

class ModeOption {
  const ModeOption({required this.id, required this.title, required this.hint});

  final ModeId id;
  final String title;
  final String hint;
}

class MetadataState {
  const MetadataState({
    required this.model,
    required this.duration,
    required this.frames,
    required this.resolution,
    required this.ratio,
    required this.seed,
    required this.cameraFixed,
    required this.watermark,
    required this.generateAudio,
    required this.returnLastFrame,
  });

  final String model;
  final String duration;
  final String frames;
  final String resolution;
  final String ratio;
  final String seed;
  final bool cameraFixed;
  final bool watermark;
  final bool generateAudio;
  final bool returnLastFrame;

  MetadataState copyWith({
    String? model,
    String? duration,
    String? frames,
    String? resolution,
    String? ratio,
    String? seed,
    bool? cameraFixed,
    bool? watermark,
    bool? generateAudio,
    bool? returnLastFrame,
  }) {
    return MetadataState(
      model: model ?? this.model,
      duration: duration ?? this.duration,
      frames: frames ?? this.frames,
      resolution: resolution ?? this.resolution,
      ratio: ratio ?? this.ratio,
      seed: seed ?? this.seed,
      cameraFixed: cameraFixed ?? this.cameraFixed,
      watermark: watermark ?? this.watermark,
      generateAudio: generateAudio ?? this.generateAudio,
      returnLastFrame: returnLastFrame ?? this.returnLastFrame,
    );
  }
}

class ImageMetadataState {
  const ImageMetadataState({
    required this.aspectRatio,
    required this.quality,
    required this.numImages,
    required this.outputFormat,
    required this.category,
    required this.role,
  });

  final String aspectRatio;
  final String quality;
  final int numImages;
  final String outputFormat;
  final String category;
  final AttachmentRole role;

  ImageMetadataState copyWith({
    String? aspectRatio,
    String? quality,
    int? numImages,
    String? outputFormat,
    String? category,
    AttachmentRole? role,
  }) {
    return ImageMetadataState(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      quality: quality ?? this.quality,
      numImages: numImages ?? this.numImages,
      outputFormat: outputFormat ?? this.outputFormat,
      category: category ?? this.category,
      role: role ?? this.role,
    );
  }
}

class ImageTaskResultItem {
  const ImageTaskResultItem({
    required this.id,
    required this.status,
    this.remoteUrl,
    this.localTempPath,
    this.storageUrl,
    this.attachmentId,
    this.lastError,
    this.updatedAt,
    this.downloadRetryCount = 0,
    this.uploadRetryCount = 0,
  });

  final String id;
  final ImageResultStatus status;
  final String? remoteUrl;
  final String? localTempPath;
  final String? storageUrl;
  final String? attachmentId;
  final String? lastError;
  final DateTime? updatedAt;
  final int downloadRetryCount;
  final int uploadRetryCount;

  ImageTaskResultItem copyWith({
    String? id,
    ImageResultStatus? status,
    String? remoteUrl,
    String? localTempPath,
    String? storageUrl,
    String? attachmentId,
    String? lastError,
    DateTime? updatedAt,
    int? downloadRetryCount,
    int? uploadRetryCount,
    bool clearRemoteUrl = false,
    bool clearLocalTempPath = false,
    bool clearStorageUrl = false,
    bool clearAttachmentId = false,
    bool clearLastError = false,
    bool clearUpdatedAt = false,
  }) {
    return ImageTaskResultItem(
      id: id ?? this.id,
      status: status ?? this.status,
      remoteUrl: clearRemoteUrl ? null : (remoteUrl ?? this.remoteUrl),
      localTempPath: clearLocalTempPath
          ? null
          : (localTempPath ?? this.localTempPath),
      storageUrl: clearStorageUrl ? null : (storageUrl ?? this.storageUrl),
      attachmentId: clearAttachmentId
          ? null
          : (attachmentId ?? this.attachmentId),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
      downloadRetryCount: downloadRetryCount ?? this.downloadRetryCount,
      uploadRetryCount: uploadRetryCount ?? this.uploadRetryCount,
    );
  }
}

class SettingsState {
  const SettingsState({
    required this.storageProvider,
    required this.agentEarthBaseUrl,
    required this.agentEarthApiKey,
    required this.qiniuAccessKey,
    required this.qiniuSecretKey,
    required this.qiniuBucket,
    required this.qiniuDomain,
    required this.bitifulAccessKey,
    required this.bitifulSecretKey,
    required this.bitifulBucket,
    required this.bitifulEndpoint,
    required this.bitifulRegion,
    required this.bitifulPublicDomain,
    required this.autoPoll,
    required this.autoDownload,
  });

  final StorageProvider storageProvider;
  final String agentEarthBaseUrl;
  final String agentEarthApiKey;
  final String qiniuAccessKey;
  final String qiniuSecretKey;
  final String qiniuBucket;
  final String qiniuDomain;
  final String bitifulAccessKey;
  final String bitifulSecretKey;
  final String bitifulBucket;
  final String bitifulEndpoint;
  final String bitifulRegion;
  final String bitifulPublicDomain;
  final bool autoPoll;
  final bool autoDownload;

  SettingsState copyWith({
    StorageProvider? storageProvider,
    String? agentEarthBaseUrl,
    String? agentEarthApiKey,
    String? qiniuAccessKey,
    String? qiniuSecretKey,
    String? qiniuBucket,
    String? qiniuDomain,
    String? bitifulAccessKey,
    String? bitifulSecretKey,
    String? bitifulBucket,
    String? bitifulEndpoint,
    String? bitifulRegion,
    String? bitifulPublicDomain,
    bool? autoPoll,
    bool? autoDownload,
  }) {
    return SettingsState(
      storageProvider: storageProvider ?? this.storageProvider,
      agentEarthBaseUrl: agentEarthBaseUrl ?? this.agentEarthBaseUrl,
      agentEarthApiKey: agentEarthApiKey ?? this.agentEarthApiKey,
      qiniuAccessKey: qiniuAccessKey ?? this.qiniuAccessKey,
      qiniuSecretKey: qiniuSecretKey ?? this.qiniuSecretKey,
      qiniuBucket: qiniuBucket ?? this.qiniuBucket,
      qiniuDomain: qiniuDomain ?? this.qiniuDomain,
      bitifulAccessKey: bitifulAccessKey ?? this.bitifulAccessKey,
      bitifulSecretKey: bitifulSecretKey ?? this.bitifulSecretKey,
      bitifulBucket: bitifulBucket ?? this.bitifulBucket,
      bitifulEndpoint: bitifulEndpoint ?? this.bitifulEndpoint,
      bitifulRegion: bitifulRegion ?? this.bitifulRegion,
      bitifulPublicDomain: bitifulPublicDomain ?? this.bitifulPublicDomain,
      autoPoll: autoPoll ?? this.autoPoll,
      autoDownload: autoDownload ?? this.autoDownload,
    );
  }
}

class Attachment {
  const Attachment({
    required this.id,
    required this.label,
    required this.role,
    required this.kind,
    required this.fileName,
    required this.category,
    required this.createdAt,
    required this.status,
    required this.url,
    this.uploadProgress,
    this.localStatus = AttachmentLocalStatus.none,
    this.localDownloadProgress = 0,
    this.localResourceUri,
    this.localFileName,
    this.localUpdatedAt,
    this.localErrorMessage,
    this.storageProvider = StorageProvider.qiniu,
    this.objectKey,
    this.storageBucket,
    this.storageEndpoint,
    this.storageRegion,
    this.storageDomain,
    this.fileSizeBytes,
    this.sourceTaskId,
    this.source = AttachmentSource.library,
    this.expiresAt,
  });

  final String id;
  final String label;
  final AttachmentRole role;
  final AttachmentKind kind;
  final String fileName;
  final String category;
  final DateTime createdAt;
  final AttachmentStatus status;
  final String url;
  final int? uploadProgress;
  final AttachmentLocalStatus localStatus;
  final int localDownloadProgress;
  final String? localResourceUri;
  final String? localFileName;
  final DateTime? localUpdatedAt;
  final String? localErrorMessage;
  final StorageProvider storageProvider;
  final String? objectKey;
  final String? storageBucket;
  final String? storageEndpoint;
  final String? storageRegion;
  final String? storageDomain;
  final int? fileSizeBytes;

  /// 该素材是哪个任务产出的（图片任务一次可能产出多张）。
  /// 非任务来源（本地导入、合成导出、抓帧导入）为 null。
  final String? sourceTaskId;

  /// 素材来源。默认 [AttachmentSource.library] 表示走用户自建的对象存储、进素材库；
  /// [AttachmentSource.ephemeral] 表示走 AgentEarth 官方托管的临时链接，仅用于当次
  /// 任务，不落进素材库。
  final AttachmentSource source;

  /// 仅对临时素材有意义：链接可能在这个时间之后失效。
  /// null 表示未知或长期有效。
  final DateTime? expiresAt;

  bool get isEphemeral => source == AttachmentSource.ephemeral;

  Attachment copyWith({
    String? label,
    AttachmentRole? role,
    AttachmentKind? kind,
    String? fileName,
    String? category,
    DateTime? createdAt,
    AttachmentStatus? status,
    String? url,
    int? uploadProgress,
    AttachmentLocalStatus? localStatus,
    int? localDownloadProgress,
    String? localResourceUri,
    String? localFileName,
    DateTime? localUpdatedAt,
    String? localErrorMessage,
    StorageProvider? storageProvider,
    String? objectKey,
    String? storageBucket,
    String? storageEndpoint,
    String? storageRegion,
    String? storageDomain,
    int? fileSizeBytes,
    String? sourceTaskId,
    AttachmentSource? source,
    DateTime? expiresAt,
    bool clearLocalResourceUri = false,
    bool clearLocalFileName = false,
    bool clearLocalUpdatedAt = false,
    bool clearLocalErrorMessage = false,
    bool clearFileSizeBytes = false,
    bool clearSourceTaskId = false,
    bool clearExpiresAt = false,
  }) {
    return Attachment(
      id: id,
      label: label ?? this.label,
      role: role ?? this.role,
      kind: kind ?? this.kind,
      fileName: fileName ?? this.fileName,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      url: url ?? this.url,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      localStatus: localStatus ?? this.localStatus,
      localDownloadProgress:
          localDownloadProgress ?? this.localDownloadProgress,
      localResourceUri: clearLocalResourceUri
          ? null
          : (localResourceUri ?? this.localResourceUri),
      localFileName: clearLocalFileName
          ? null
          : (localFileName ?? this.localFileName),
      localUpdatedAt: clearLocalUpdatedAt
          ? null
          : (localUpdatedAt ?? this.localUpdatedAt),
      localErrorMessage: clearLocalErrorMessage
          ? null
          : (localErrorMessage ?? this.localErrorMessage),
      storageProvider: storageProvider ?? this.storageProvider,
      objectKey: objectKey ?? this.objectKey,
      storageBucket: storageBucket ?? this.storageBucket,
      storageEndpoint: storageEndpoint ?? this.storageEndpoint,
      storageRegion: storageRegion ?? this.storageRegion,
      storageDomain: storageDomain ?? this.storageDomain,
      fileSizeBytes: clearFileSizeBytes
          ? null
          : (fileSizeBytes ?? this.fileSizeBytes),
      sourceTaskId: clearSourceTaskId
          ? null
          : (sourceTaskId ?? this.sourceTaskId),
      source: source ?? this.source,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
    );
  }
}

/// 一个素材库列表条目：
/// - 单素材组（多数情况，非任务来源、本地导入、抓帧、合成等）
/// - 任务组（同一任务产出的多个素材，UI 上折叠成一张组卡）
class AttachmentGroup {
  AttachmentGroup({required this.taskId, required this.items})
    : assert(items.isNotEmpty);

  /// 任务 ID。null 代表非任务来源；任务组保证非 null。
  final String? taskId;

  /// 该组下属的素材，按列表展示顺序排列（与传入的素材列表保持一致）。
  final List<Attachment> items;

  bool get isTaskGroup => taskId != null && items.length > 1;

  Attachment get representative => items.first;

  int get count => items.length;
}

/// 把扁平的素材列表按 sourceTaskId 聚合成 [AttachmentGroup]：
/// - sourceTaskId 为空或仅有 1 个素材的任务，作为单素材组（保持原顺序）
/// - 同一任务产出的多素材，合并为一张任务组卡，组的位置取该组首个素材在
///   原列表中的位置，组内素材按原列表相对顺序保留
List<AttachmentGroup> groupAttachmentsByTask(List<Attachment> attachments) {
  final groups = <AttachmentGroup>[];
  final taskGroupIndexById = <String, int>{};

  for (final attachment in attachments) {
    final taskId = attachment.sourceTaskId;
    if (taskId == null || taskId.isEmpty) {
      groups.add(AttachmentGroup(taskId: null, items: [attachment]));
      continue;
    }
    final existingIndex = taskGroupIndexById[taskId];
    if (existingIndex == null) {
      taskGroupIndexById[taskId] = groups.length;
      groups.add(AttachmentGroup(taskId: taskId, items: [attachment]));
    } else {
      groups[existingIndex].items.add(attachment);
    }
  }
  return groups;
}

class VideoFrameSource {
  const VideoFrameSource({
    required this.type,
    required this.label,
    required this.sourceUri,
    this.attachmentId,
    this.taskId,
    this.fileName,
  });

  final VideoFrameSourceType type;
  final String label;
  final String sourceUri;
  final String? attachmentId;
  final String? taskId;
  final String? fileName;
}

class RecentVideoSource {
  const RecentVideoSource({
    required this.type,
    required this.label,
    required this.sourceUri,
    required this.lastUsedAt,
    this.attachmentId,
    this.taskId,
    this.fileName,
  });

  final VideoFrameSourceType type;
  final String label;
  final String sourceUri;
  final DateTime lastUsedAt;
  final String? attachmentId;
  final String? taskId;
  final String? fileName;

  VideoFrameSource toVideoFrameSource() {
    return VideoFrameSource(
      type: type,
      label: label,
      sourceUri: sourceUri,
      attachmentId: attachmentId,
      taskId: taskId,
      fileName: fileName,
    );
  }

  RecentVideoSource copyWith({
    VideoFrameSourceType? type,
    String? label,
    String? sourceUri,
    DateTime? lastUsedAt,
    String? attachmentId,
    String? taskId,
    String? fileName,
  }) {
    return RecentVideoSource(
      type: type ?? this.type,
      label: label ?? this.label,
      sourceUri: sourceUri ?? this.sourceUri,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      attachmentId: attachmentId ?? this.attachmentId,
      taskId: taskId ?? this.taskId,
      fileName: fileName ?? this.fileName,
    );
  }
}

class CapturedFrameResult {
  const CapturedFrameResult({
    required this.path,
    required this.uri,
    required this.width,
    required this.height,
    required this.positionMs,
  });

  final String path;
  final String uri;
  final int width;
  final int height;
  final int positionMs;
}

class TaskRecord {
  const TaskRecord({
    required this.id,
    required this.mode,
    required this.prompt,
    required this.status,
    required this.pollingStatus,
    required this.downloadStatus,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    required this.estimatedCredit,
    required this.attachments,
    required this.requestPreview,
    required this.responsePreview,
    this.pollLogs = const [],
    this.downloadProgress = 0,
    this.videoUrl,
    this.localFileName,
    this.localResourceUri,
    this.lastError,
    this.statusDetail,
    this.responseUrl,
    this.statusUrl,
    this.toolName,
    this.hasAnomaly = false,
    this.anomalyMessage,
    this.kind = TaskKind.video,
    this.imageResults = const [],
    this.imageMetadata,
    this.imageMode,
    this.archivedAt,
  });

  final String id;
  final ModeId mode;
  final String prompt;
  final TaskStatus status;
  final PollingStatus pollingStatus;
  final DownloadStatus downloadStatus;
  final int progress;
  final int downloadProgress;
  final DateTime createdAt;
  final String? videoUrl;
  final String? localFileName;
  final String? localResourceUri;
  final String? lastError;
  final String? statusDetail;
  final DateTime updatedAt;
  final int estimatedCredit;
  final List<Attachment> attachments;
  final String requestPreview;
  final String responsePreview;
  final List<TaskPollLog> pollLogs;
  final String? responseUrl;
  final String? statusUrl;
  final String? toolName;
  final bool hasAnomaly;
  final String? anomalyMessage;
  final TaskKind kind;
  final List<ImageTaskResultItem> imageResults;
  final ImageMetadataState? imageMetadata;
  final ImageCreateMode? imageMode;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  TaskRecord copyWith({
    ModeId? mode,
    String? prompt,
    TaskStatus? status,
    PollingStatus? pollingStatus,
    DownloadStatus? downloadStatus,
    int? progress,
    int? downloadProgress,
    DateTime? createdAt,
    String? videoUrl,
    String? localFileName,
    String? localResourceUri,
    String? lastError,
    String? statusDetail,
    DateTime? updatedAt,
    int? estimatedCredit,
    List<Attachment>? attachments,
    String? requestPreview,
    String? responsePreview,
    List<TaskPollLog>? pollLogs,
    String? responseUrl,
    String? statusUrl,
    String? toolName,
    bool? hasAnomaly,
    String? anomalyMessage,
    bool clearVideoUrl = false,
    bool clearLocalFileName = false,
    bool clearLocalResourceUri = false,
    bool clearLastError = false,
    bool clearStatusDetail = false,
    bool clearResponseUrl = false,
    bool clearStatusUrl = false,
    bool clearToolName = false,
    bool clearAnomalyMessage = false,
    TaskKind? kind,
    List<ImageTaskResultItem>? imageResults,
    ImageMetadataState? imageMetadata,
    ImageCreateMode? imageMode,
    DateTime? archivedAt,
    bool clearImageMetadata = false,
    bool clearImageMode = false,
    bool clearArchivedAt = false,
  }) {
    return TaskRecord(
      id: id,
      mode: mode ?? this.mode,
      prompt: prompt ?? this.prompt,
      status: status ?? this.status,
      pollingStatus: pollingStatus ?? this.pollingStatus,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      progress: progress ?? this.progress,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      estimatedCredit: estimatedCredit ?? this.estimatedCredit,
      attachments: attachments ?? this.attachments,
      requestPreview: requestPreview ?? this.requestPreview,
      responsePreview: responsePreview ?? this.responsePreview,
      pollLogs: pollLogs ?? this.pollLogs,
      videoUrl: clearVideoUrl ? null : (videoUrl ?? this.videoUrl),
      localFileName: clearLocalFileName
          ? null
          : (localFileName ?? this.localFileName),
      localResourceUri: clearLocalResourceUri
          ? null
          : (localResourceUri ?? this.localResourceUri),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      statusDetail: clearStatusDetail
          ? null
          : (statusDetail ?? this.statusDetail),
      responseUrl: clearResponseUrl ? null : (responseUrl ?? this.responseUrl),
      statusUrl: clearStatusUrl ? null : (statusUrl ?? this.statusUrl),
      toolName: clearToolName ? null : (toolName ?? this.toolName),
      hasAnomaly: hasAnomaly ?? this.hasAnomaly,
      anomalyMessage: clearAnomalyMessage
          ? null
          : (anomalyMessage ?? this.anomalyMessage),
      kind: kind ?? this.kind,
      imageResults: imageResults ?? this.imageResults,
      imageMetadata: clearImageMetadata
          ? null
          : (imageMetadata ?? this.imageMetadata),
      imageMode: clearImageMode ? null : (imageMode ?? this.imageMode),
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
    );
  }
}

class TaskPollLog {
  const TaskPollLog({
    required this.createdAt,
    required this.success,
    required this.summary,
    required this.requestPreview,
    required this.responsePreview,
  });

  final DateTime createdAt;
  final bool success;
  final String summary;
  final String requestPreview;
  final String responsePreview;
}

class SeedanceTool {
  const SeedanceTool({
    required this.toolName,
    required this.toolUrl,
    required this.credit,
    required this.description,
    required this.inputProperties,
    required this.fromRecommendation,
  });

  final String toolName;
  final String toolUrl;
  final int credit;
  final String description;
  final Set<String> inputProperties;
  final bool fromRecommendation;
}

class ToolResolution {
  const ToolResolution({required this.status, this.tool, this.errorMessage});

  final ToolResolutionStatus status;
  final SeedanceTool? tool;
  final String? errorMessage;

  ToolResolution copyWith({
    ToolResolutionStatus? status,
    SeedanceTool? tool,
    String? errorMessage,
    bool clearTool = false,
    bool clearErrorMessage = false,
  }) {
    return ToolResolution(
      status: status ?? this.status,
      tool: clearTool ? null : (tool ?? this.tool),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

class SeedanceRequestPreview {
  const SeedanceRequestPreview({
    required this.toolName,
    required this.toolUrl,
    required this.body,
    required this.prettyJson,
  });

  final String toolName;
  final String toolUrl;
  final Map<String, Object?> body;
  final String prettyJson;
}

class TaskExecution {
  const TaskExecution({
    required this.responseUrl,
    required this.statusUrl,
    required this.toolName,
    required this.credit,
    required this.requestPreview,
    required this.responsePreview,
  });

  final String responseUrl;
  final String? statusUrl;
  final String toolName;
  final int credit;
  final SeedanceRequestPreview requestPreview;
  final String responsePreview;
}

class TaskExecutionException implements Exception {
  const TaskExecutionException(this.message, {this.requestPreview});

  final String message;
  final SeedanceRequestPreview? requestPreview;

  @override
  String toString() => message;
}

class TaskPolledResult {
  const TaskPolledResult({
    required this.status,
    required this.progress,
    required this.requestPreview,
    required this.responsePreview,
    this.videoUrl,
    this.statusDetail,
    this.lastError,
    this.hasAnomaly = false,
    this.anomalyMessage,
  });

  final TaskStatus status;
  final int progress;
  final String requestPreview;
  final String responsePreview;
  final String? videoUrl;
  final String? statusDetail;
  final String? lastError;
  final bool hasAnomaly;
  final String? anomalyMessage;
}
