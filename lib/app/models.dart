enum AppTab { create, library, tasks, settings }

enum ModeId { text, firstFrame, firstLast, reference }

enum StorageProvider { qiniu, bitifulS4 }

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
    this.imageAutoFallbackEnabled = false,
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
  final bool imageAutoFallbackEnabled;

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
    bool? imageAutoFallbackEnabled,
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
      imageAutoFallbackEnabled:
          imageAutoFallbackEnabled ?? this.imageAutoFallbackEnabled,
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

  Attachment copyWith({
    String? label,
    AttachmentRole? role,
    AttachmentKind? kind,
    String? fileName,
    String? category,
    DateTime? createdAt,
    AttachmentStatus? status,
    String? url,
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
    bool clearLocalResourceUri = false,
    bool clearLocalFileName = false,
    bool clearLocalUpdatedAt = false,
    bool clearLocalErrorMessage = false,
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
      localStatus: localStatus ?? this.localStatus,
      localDownloadProgress: localDownloadProgress ?? this.localDownloadProgress,
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
    );
  }
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
    bool clearImageMetadata = false,
    bool clearImageMode = false,
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
