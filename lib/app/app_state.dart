import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'composition_models.dart';
import 'mock_data.dart';
import 'models.dart';
import '../services/app_storage.dart';
import '../services/api_client.dart';
import '../services/bitiful_s4_upload_service.dart';
import '../services/native_file_picker.dart';
import '../services/qiniu_upload_service.dart';
import '../services/seedance_service.dart';
import '../services/image_generation_service.dart';
import '../services/storage_upload_result.dart';
import '../services/video_frame_service.dart';
import '../services/video_composition_service.dart';

class AppState extends ChangeNotifier {
  static final RegExp promptTokenPattern = RegExp(r'@\{[^}]+\}');
  static const int minSeedanceDurationSeconds = 4;
  static const int maxSeedanceDurationSeconds = 15;
  final SeedanceService _seedanceService;
  final NativeFilePicker _filePicker;
  final QiniuUploadService _qiniuUploadService;
  final BitifulS4UploadService _bitifulUploadService;
  final AppStorage _storage;
  final ImageGenerationService _imageGenerationService;
  final VideoFrameService _videoFrameService;
  final VideoCompositionService _videoCompositionService;
  static const MethodChannel _mediaChannel = MethodChannel('mova/media');
  Timer? _persistDebounce;
  Timer? _pollingTimer;
  bool _persistenceLoaded = false;
  bool _appInForeground = true;
  final Set<String> _refreshingTaskIds = {};
  final Set<String> _transferringImageTaskIds = {};
  final Map<String, _SignedUrlCacheEntry> _signedUrlCache = {};
  final Map<String, bool> _qiniuBucketPrivateByBucket = {};
  final Map<String, Future<bool?>> _qiniuBucketPrivateRefreshes = {};
  int _compositionClipSequence = 0;

  AppState({
    SeedanceService? seedanceService,
    NativeFilePicker? filePicker,
    QiniuUploadService? qiniuUploadService,
    BitifulS4UploadService? bitifulUploadService,
    AppStorage? storage,
    ImageGenerationService? imageGenerationService,
    VideoFrameService? videoFrameService,
    VideoCompositionService? videoCompositionService,
  }) : _seedanceService = seedanceService ?? SeedanceService(),
       _filePicker = filePicker ?? NativeFilePicker(),
       _qiniuUploadService = qiniuUploadService ?? QiniuUploadService(),
       _bitifulUploadService = bitifulUploadService ?? BitifulS4UploadService(),
       _storage = storage ?? AppStorage(),
       _imageGenerationService =
           imageGenerationService ?? ImageGenerationService(),
       _videoFrameService = videoFrameService ?? VideoFrameService(),
       _videoCompositionService =
           videoCompositionService ?? VideoCompositionService() {
    _initializeToolResolutions();
    addListener(_schedulePersist);
  }

  AppTab currentTab = AppTab.create;
  ModeId activeMode = ModeId.text;
  String prompt = initialPrompt;
  MetadataState metadata = metadataDefaults;
  SettingsState settings = settingsDefaults;
  final List<Attachment> library = [...initialLibrary];
  final List<TaskRecord> tasks = [...initialTasks];
  final List<RecentVideoSource> recentVideoSources = [];
  final List<String> categories = [...defaultCategories];
  final List<String> selectedAttachmentIds = [];
  String? selectedFirstFrameAttachmentId;
  String? selectedLastFrameAttachmentId;
  final Map<String, int> attachmentLastUsedAt = {};
  String libraryQuery = '';
  LibraryFilter libraryFilter = LibraryFilter.all;
  LibraryViewMode libraryViewMode = LibraryViewMode.comfortable;
  bool libraryRecentFirst = true;
  final List<String> selectedCategoryFilters = [];
  String mentionQuery = '';
  String mentionCategoryFilter = 'all';
  bool mentionOpen = false;
  int? mentionStart;
  int? mentionEnd;
  bool isSubmitting = false;
  String? submitErrorMessage;
  String? uploadErrorMessage;
  String configStatusMessage = '先选择存储提供商并填写配置，再测试连接。';
  bool isTestingAgentEarth = false;
  bool isTestingQiniu = false;
  bool isTestingBitiful = false;
  bool isFetchingBuckets = false;
  bool isFetchingDomains = false;
  final List<String> bucketOptions = [];
  final List<String> domainOptions = [];
  bool? qiniuBucketPrivate;
  final Set<String> expandedPollLogTaskIds = {};
  final Map<ModeId, ToolResolution> toolResolutions = {};
  String imagePrompt = '';
  ImageMetadataState imageMetadata = imageMetadataDefaults;
  ImageCreateMode activeImageMode = ImageCreateMode.textToImage;
  final List<String> selectedImageAttachmentIds = [];
  ToolResolution imageToolResolution = ToolResolution(
    status: ToolResolutionStatus.idle,
  );
  bool isSubmittingImageTask = false;
  String? imageSubmitErrorMessage;
  TaskTab activeTaskTab = TaskTab.video;
  bool showArchivedTasks = false;
  VideoCompositionProject compositionProject = VideoCompositionProject.empty;
  CompositionExportStatus compositionExportStatus =
      CompositionExportStatus.idle;
  int compositionExportProgress = 0;
  String compositionExportStage = '';
  String? compositionExportErrorMessage;
  CompositionExportResult? compositionExportResult;

  bool get isExportingComposition => switch (compositionExportStatus) {
    CompositionExportStatus.preparing ||
    CompositionExportStatus.trimming ||
    CompositionExportStatus.composing ||
    CompositionExportStatus.writing => true,
    _ => false,
  };

  void setActiveTaskTab(TaskTab tab) {
    activeTaskTab = tab;
    notifyListeners();
  }

  void setShowArchivedTasks(bool value) {
    if (showArchivedTasks == value) return;
    showArchivedTasks = value;
    notifyListeners();
  }

  void setLibraryViewMode(LibraryViewMode mode) {
    if (libraryViewMode == mode) return;
    libraryViewMode = mode;
    notifyListeners();
  }

  bool get isAgentEarthConfigured =>
      settings.agentEarthApiKey.trim().isNotEmpty;

  void updateImagePrompt(String value) {
    imagePrompt = value;
    notifyListeners();
  }

  void updateImageMetadata(
    ImageMetadataState Function(ImageMetadataState current) update,
  ) {
    imageMetadata = update(imageMetadata);
    notifyListeners();
  }

  void setActiveImageMode(ImageCreateMode mode) {
    if (activeImageMode == mode) return;
    activeImageMode = mode;
    imageToolResolution = ToolResolution(status: ToolResolutionStatus.idle);
    notifyListeners();
  }

  StorageProvider get currentStorageProvider => settings.storageProvider;

  String get currentStorageProviderLabel =>
      storageProviderLabel(settings.storageProvider);

  bool get isQiniuConfigured =>
      settings.qiniuAccessKey.trim().isNotEmpty &&
      settings.qiniuSecretKey.trim().isNotEmpty &&
      settings.qiniuBucket.trim().isNotEmpty &&
      settings.qiniuDomain.trim().isNotEmpty;

  bool get isBitifulConfigured =>
      settings.bitifulAccessKey.trim().isNotEmpty &&
      settings.bitifulSecretKey.trim().isNotEmpty &&
      settings.bitifulBucket.trim().isNotEmpty &&
      settings.bitifulEndpoint.trim().isNotEmpty &&
      settings.bitifulRegion.trim().isNotEmpty;

  bool get isCurrentStorageConfigured {
    switch (settings.storageProvider) {
      case StorageProvider.qiniu:
        return isQiniuConfigured;
      case StorageProvider.bitifulS4:
        return isBitifulConfigured;
    }
  }

  String storageProviderLabel(StorageProvider provider) {
    switch (provider) {
      case StorageProvider.qiniu:
        return '七牛云';
      case StorageProvider.bitifulS4:
        return '缤纷云（Bitiful）S4';
    }
  }

  ToolResolution get activeToolResolution =>
      toolResolutions[activeMode] ??
      ToolResolution(
        status: ToolResolutionStatus.idle,
        tool: fallbackToolForMode(
          activeMode,
          baseUrl: settings.agentEarthBaseUrl,
        ),
      );

  SeedanceRequestPreview get requestPreview =>
      _seedanceService.buildRequestPreview(
        mode: activeMode,
        prompt: effectiveVideoPrompt,
        metadata: metadata,
        attachments: selectedAttachments,
        baseUrl: settings.agentEarthBaseUrl,
        tool: activeToolResolution.tool,
      );

  SeedanceRequestPreview get imageRequestPreview =>
      _imageGenerationService.buildRequestPreview(
        mode: activeImageMode,
        prompt: imagePrompt,
        metadata: imageMetadata,
        attachments: selectedImageAttachments,
        baseUrl: settings.agentEarthBaseUrl,
        tool: imageToolResolution.tool,
      );

  Future<SeedanceRequestPreview> resolveImageRequestPreview() async {
    final previewAttachments = await _resolveImageAttachmentsForGeneration(
      List<Attachment>.from(selectedImageAttachments),
    );
    return _imageGenerationService.buildRequestPreview(
      mode: activeImageMode,
      prompt: imagePrompt,
      metadata: imageMetadata,
      attachments: previewAttachments,
      baseUrl: settings.agentEarthBaseUrl,
      tool: imageToolResolution.tool,
    );
  }

  Future<SeedanceRequestPreview> resolveRequestPreview() async {
    final previewAttachments = await _resolveAttachmentsForSeedance(
      List<Attachment>.from(selectedAttachments),
    );
    return _seedanceService.buildRequestPreview(
      mode: activeMode,
      prompt: effectiveVideoPrompt,
      metadata: metadata,
      attachments: previewAttachments,
      baseUrl: settings.agentEarthBaseUrl,
      tool: activeToolResolution.tool,
    );
  }

  List<Attachment> get uploadedLibrary =>
      queryAttachments(uploadedOnly: true, sort: false);

  List<RecentVideoSource> get visibleRecentVideoSources {
    final byKey = <String, RecentVideoSource>{};
    for (final source in recentVideoSources) {
      final key =
          '${source.type.name}|${source.attachmentId ?? ''}|${source.taskId ?? ''}|${source.sourceUri}';
      byKey[key] = source;
    }
    final values = byKey.values.toList()
      ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return values.take(8).toList();
  }

  bool get usesFrameSlots =>
      activeMode == ModeId.firstFrame || activeMode == ModeId.firstLast;

  bool get supportsPromptMentions => activeMode == ModeId.reference;

  String get effectiveVideoPrompt =>
      _normalizedVideoPromptForMode(prompt, activeMode);

  List<Attachment> get selectedAttachments {
    switch (activeMode) {
      case ModeId.text:
        return const [];
      case ModeId.firstFrame:
        final firstFrame = selectedFirstFrameAttachment;
        return firstFrame == null
            ? const []
            : [firstFrame.copyWith(role: AttachmentRole.firstFrame)];
      case ModeId.firstLast:
        final attachments = <Attachment>[];
        final firstFrame = selectedFirstFrameAttachment;
        final lastFrame = selectedLastFrameAttachment;
        if (firstFrame != null) {
          attachments.add(firstFrame.copyWith(role: AttachmentRole.firstFrame));
        }
        if (lastFrame != null) {
          attachments.add(lastFrame.copyWith(role: AttachmentRole.lastFrame));
        }
        return attachments;
      case ModeId.reference:
        final byId = {for (final item in uploadedLibrary) item.id: item};
        return selectedAttachmentIds
            .map((id) => byId[id])
            .whereType<Attachment>()
            .toList();
    }
  }

  List<Attachment> get selectedImageAttachments {
    final byId = {for (final item in uploadedLibrary) item.id: item};
    return selectedImageAttachmentIds
        .map((id) => byId[id])
        .whereType<Attachment>()
        .where((attachment) => attachment.kind == AttachmentKind.image)
        .toList();
  }

  Attachment? get selectedFirstFrameAttachment =>
      _uploadedAttachmentById(
        selectedFirstFrameAttachmentId,
        kind: AttachmentKind.image,
      ) ??
      _legacySelectedImageAttachment;

  Attachment? get selectedLastFrameAttachment => _uploadedAttachmentById(
    selectedLastFrameAttachmentId,
    kind: AttachmentKind.image,
  );

  List<Attachment> get mentionCandidates {
    if (!supportsPromptMentions) {
      return const [];
    }
    return queryAttachments(
      query: mentionQuery,
      category: mentionCategoryFilter,
      uploadedOnly: true,
    );
  }

  bool canAccessAttachment(Attachment attachment) {
    return attachment.url.trim().isNotEmpty ||
        (attachment.storageProvider == StorageProvider.bitifulS4 &&
            (attachment.objectKey?.trim().isNotEmpty ?? false));
  }

  Future<String> resolveAttachmentPreviewUrl(Attachment attachment) {
    return _resolveAttachmentAccessUrl(
      attachment,
      purpose: _AttachmentAccessPurpose.preview,
    );
  }

  Future<String> resolveAttachmentShareUrl(Attachment attachment) {
    return _resolveAttachmentAccessUrl(
      attachment,
      purpose: _AttachmentAccessPurpose.share,
    );
  }

  List<Attachment> get visibleLibrary => queryAttachments(
    query: libraryQuery,
    filter: libraryFilter,
    categories: selectedCategoryFilters,
  );

  List<Attachment> queryAttachments({
    String query = '',
    String category = 'all',
    LibraryFilter filter = LibraryFilter.all,
    List<String> categories = const [],
    AttachmentKind? kind,
    String? excludeAttachmentId,
    bool uploadedOnly = false,
    bool sort = true,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final result = library.where((item) {
      if (excludeAttachmentId != null && item.id == excludeAttachmentId) {
        return false;
      }
      if (uploadedOnly && item.status != AttachmentStatus.uploaded) {
        return false;
      }
      final matchesFilter =
          filter == LibraryFilter.all || item.kind.name == filter.name;
      final matchesCategory =
          categories.isEmpty || categories.contains(item.category);
      final matchesMentionCategory =
          category == 'all' || item.category == category;
      final matchesKind = kind == null || item.kind == kind;
      final matchesQuery =
          normalizedQuery.isEmpty ||
          item.label.toLowerCase().contains(normalizedQuery) ||
          item.fileName.toLowerCase().contains(normalizedQuery) ||
          item.category.toLowerCase().contains(normalizedQuery) ||
          displayCategoryLabel(
            item.category,
          ).toLowerCase().contains(normalizedQuery);

      return matchesFilter &&
          matchesCategory &&
          matchesMentionCategory &&
          matchesKind &&
          matchesQuery;
    }).toList();
    if (!sort) {
      return result;
    }
    result.sort(_compareAttachments);
    return result;
  }

  List<String> get validationMessages {
    final messages = <String>[];
    final roles = selectedAttachments.map((item) => item.role).toList();

    if (effectiveVideoPrompt.trim().isEmpty) {
      messages.add('Prompt 不能为空。');
    }
    if (effectiveVideoPrompt.length > 5000) {
      messages.add('Prompt 不能超过 5000 字符。');
    }
    final durationSeconds = int.tryParse(metadata.duration.trim());
    if (durationSeconds == null) {
      messages.add(
        '时长必须是 $minSeedanceDurationSeconds-$maxSeedanceDurationSeconds 秒之间的整数。',
      );
    } else if (durationSeconds < minSeedanceDurationSeconds ||
        durationSeconds > maxSeedanceDurationSeconds) {
      messages.add(
        'Seedance2 当前支持 $minSeedanceDurationSeconds-$maxSeedanceDurationSeconds 秒视频，请调整时长。',
      );
    }

    if (activeMode == ModeId.text && selectedAttachments.isNotEmpty) {
      messages.add('文本生视频模式不接收素材。');
    }

    if (activeMode == ModeId.firstFrame &&
        !roles.contains(AttachmentRole.firstFrame) &&
        !roles.contains(AttachmentRole.referenceImage)) {
      messages.add('首帧图生视频至少需要一张首帧图或参考图。');
    }

    if (activeMode == ModeId.firstFrame) {
      final startImageCount =
          roles.where((role) => role == AttachmentRole.firstFrame).length +
          roles.where((role) => role == AttachmentRole.referenceImage).length;
      if (startImageCount > 1) {
        messages.add('首帧图生视频模式最多只能选择 1 张起始图片。');
      }
      if (roles.contains(AttachmentRole.lastFrame)) {
        messages.add('首帧图生视频模式不能同时选择尾帧图片。');
      }
      if (roles.contains(AttachmentRole.referenceVideo) ||
          roles.contains(AttachmentRole.referenceAudio)) {
        messages.add('首帧图生视频模式不支持参考视频或参考音频。');
      }
    }

    if (activeMode == ModeId.firstLast) {
      final hasStart =
          roles.contains(AttachmentRole.firstFrame) ||
          roles.contains(AttachmentRole.referenceImage);
      final hasEnd = roles.contains(AttachmentRole.lastFrame);
      if (!hasStart) {
        messages.add('首尾帧视频模式需要一张起始图片。');
      }
      if (!hasEnd) {
        messages.add('首尾帧视频模式需要一张尾帧图片。');
      }
      final startImageCount =
          roles.where((role) => role == AttachmentRole.firstFrame).length +
          roles.where((role) => role == AttachmentRole.referenceImage).length;
      if (startImageCount > 1) {
        messages.add('首尾帧视频模式最多只能选择 1 张起始图片。');
      }
      if (roles.where((role) => role == AttachmentRole.lastFrame).length > 1) {
        messages.add('首尾帧视频模式最多只能选择 1 张尾帧图片。');
      }
      if (roles.contains(AttachmentRole.referenceVideo) ||
          roles.contains(AttachmentRole.referenceAudio)) {
        messages.add('首尾帧视频模式不支持参考视频或参考音频。');
      }
    }

    if (activeMode == ModeId.reference) {
      if (roles.contains(AttachmentRole.firstFrame) ||
          roles.contains(AttachmentRole.lastFrame)) {
        messages.add('参考素材生成模式不能混用首帧或尾帧角色素材。');
      }
      final imageCount = roles
          .where((role) => role == AttachmentRole.referenceImage)
          .length;
      final videoCount = roles
          .where((role) => role == AttachmentRole.referenceVideo)
          .length;
      final audioCount = roles
          .where((role) => role == AttachmentRole.referenceAudio)
          .length;
      final hasReference = roles.any(
        (role) =>
            role == AttachmentRole.referenceImage ||
            role == AttachmentRole.referenceVideo ||
            role == AttachmentRole.referenceAudio,
      );
      if (!hasReference) {
        messages.add('参考素材生成模式至少需要一项参考图、参考视频或参考音频。');
      }
      if (imageCount > 9) {
        messages.add('参考素材生成模式最多支持 9 张参考图。');
      }
      if (videoCount > 3) {
        messages.add('参考素材生成模式最多支持 3 个参考视频。');
      }
      if (audioCount > 3) {
        messages.add('参考素材生成模式最多支持 3 个参考音频。');
      }
      if (imageCount + videoCount + audioCount > 12) {
        messages.add('参考图/视频/音频总数最多为 12 个。');
      }
      if (audioCount > 0 && imageCount + videoCount == 0) {
        messages.add('参考音频必须搭配至少一项参考图或参考视频。');
      }
      if (roles.contains(AttachmentRole.referenceAudio) &&
          !metadata.generateAudio) {
        messages.add('使用参考音频时，必须开启生成音频。');
      }
    }

    return messages;
  }

  Future<void> loadPersistedState() async {
    try {
      final raw = await _storage.readState();
      if (raw != null && raw.trim().isNotEmpty) {
        _restoreFromJson(jsonDecode(raw));
        _syncSelectedAttachmentsFromPrompt();
        _backfillAttachmentSourceTaskId();
        _backfillAttachmentStorageDomain();
      }
    } catch (error) {
      configStatusMessage = '本地配置读取失败：${_cleanError(error)}';
    } finally {
      _persistenceLoaded = true;
      notifyListeners();
      _resumePollingAfterLifecycle();
    }
  }

  /// 历史素材在落库时尚无 sourceTaskId 字段。加载持久化数据后，用图片任务的
  /// imageResults[].attachmentId 反查 taskId，给 sourceTaskId 为空但确实产自
  /// 某任务的素材补上归属，使其能在素材库里按任务折叠分组。已带 sourceTaskId
  /// 的素材保持不变；回填结果会在下一次 savePersistedState 时随正常持久化落盘。
  void _backfillAttachmentSourceTaskId() {
    final index = buildAttachmentTaskIdIndex(tasks);
    if (index.isEmpty) return;
    var changed = false;
    for (var i = 0; i < library.length; i++) {
      final attachment = library[i];
      if (attachment.sourceTaskId != null &&
          attachment.sourceTaskId!.isNotEmpty) {
        continue;
      }
      final taskId = index[attachment.id];
      if (taskId == null) continue;
      library[i] = attachment.copyWith(sourceTaskId: taskId);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// 由图片任务的 imageResults[].attachmentId 反查 taskId，建立
  /// attachmentId -> taskId 索引。用于给历史素材回填 sourceTaskId，
  /// 使其能在素材库里按任务折叠分组。
  static Map<String, String> buildAttachmentTaskIdIndex(
    Iterable<TaskRecord> tasks,
  ) {
    final index = <String, String>{};
    for (final task in tasks) {
      if (task.kind != TaskKind.image) continue;
      for (final item in task.imageResults) {
        final attachmentId = item.attachmentId;
        if (attachmentId == null || attachmentId.isEmpty) continue;
        if (!index.containsKey(attachmentId)) {
          index[attachmentId] = task.id;
        }
      }
    }
    return index;
  }

  /// 历史素材落库时未记录 storageDomain。加载持久化数据后，从素材的 url
  /// （形如 https://domain.example.com/key）反解出 scheme://host[:port] 回填，
  /// 使切换空间后旧素材仍能用各自域名访问。已带 storageDomain 的素材不变；
  /// url 为空或无法解析的跳过。回填结果随下一次持久化落盘。
  void _backfillAttachmentStorageDomain() {
    var changed = false;
    for (var i = 0; i < library.length; i++) {
      final attachment = library[i];
      if (attachment.storageDomain != null &&
          attachment.storageDomain!.trim().isNotEmpty) {
        continue;
      }
      final rawUrl = attachment.url.trim();
      if (rawUrl.isEmpty) continue;
      final uri = Uri.tryParse(rawUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) continue;
      // 提取 scheme://host[:port] 作为域名，去掉 path/query。
      final port = uri.hasPort ? ':${uri.port}' : '';
      final domain = '${uri.scheme}://${uri.host}$port';
      library[i] = attachment.copyWith(storageDomain: domain);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    final foreground = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive => true,
      AppLifecycleState.hidden => false,
      AppLifecycleState.paused => false,
      AppLifecycleState.detached => false,
    };
    _appInForeground = foreground;
    if (foreground) {
      _resumePollingAfterLifecycle();
    } else {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  void setCurrentTab(AppTab tab) {
    if (currentTab == tab) return;
    currentTab = tab;
    notifyListeners();
  }

  void resetCompositionProject() {
    compositionProject = VideoCompositionProject.empty;
    compositionExportErrorMessage = null;
    compositionExportResult = null;
    notifyListeners();
  }

  String _newCompositionClipId() {
    final sequence = _compositionClipSequence++;
    return 'composition-clip-${DateTime.now().microsecondsSinceEpoch}-$sequence';
  }

  void addCompositionClip(CompositionClip clip) {
    compositionProject = compositionProject.copyWith(
      clips: [...compositionProject.clips, clip],
    );
    compositionExportErrorMessage = null;
    notifyListeners();
  }

  void updateCompositionClip(
    String clipId,
    CompositionClip Function(CompositionClip clip) update,
  ) {
    var changed = false;
    final clips = compositionProject.clips.map((clip) {
      if (clip.id != clipId) return clip;
      changed = true;
      return update(clip);
    }).toList();
    if (!changed) return;
    compositionProject = compositionProject.copyWith(clips: clips);
    compositionExportErrorMessage = null;
    notifyListeners();
  }

  void removeCompositionClip(String clipId) {
    final clips = compositionProject.clips
        .where((clip) => clip.id != clipId)
        .toList();
    if (clips.length == compositionProject.clips.length) return;
    compositionProject = compositionProject.copyWith(clips: clips);
    compositionExportErrorMessage = null;
    notifyListeners();
  }

  void duplicateCompositionClip(String clipId) {
    final index = compositionProject.clips.indexWhere(
      (clip) => clip.id == clipId,
    );
    if (index == -1) return;
    final source = compositionProject.clips[index];
    final duplicate = source.copyWith(
      id: _newCompositionClipId(),
      label: '${source.label} 副本',
    );
    final clips = [...compositionProject.clips]..insert(index + 1, duplicate);
    compositionProject = compositionProject.copyWith(clips: clips);
    compositionExportErrorMessage = null;
    notifyListeners();
  }

  void moveCompositionClip(String clipId, int delta) {
    if (delta == 0) return;
    final clips = [...compositionProject.clips];
    final currentIndex = clips.indexWhere((clip) => clip.id == clipId);
    if (currentIndex == -1) return;
    final targetIndex = (currentIndex + delta).clamp(0, clips.length - 1);
    if (targetIndex == currentIndex) return;
    final clip = clips.removeAt(currentIndex);
    clips.insert(targetIndex, clip);
    compositionProject = compositionProject.copyWith(clips: clips);
    compositionExportErrorMessage = null;
    notifyListeners();
  }

  void updateCompositionOutput(CompositionOutputSettings output) {
    compositionProject = compositionProject.copyWith(output: output);
    compositionExportErrorMessage = null;
    notifyListeners();
  }

  void updateCompositionAudio(CompositionAudioSettings audio) {
    compositionProject = compositionProject.copyWith(audio: audio);
    compositionExportErrorMessage = null;
    notifyListeners();
  }

  Future<bool> exportComposition() async {
    if (isExportingComposition) return false;

    final messages = compositionProject.validationMessages;
    if (messages.isNotEmpty) {
      compositionExportErrorMessage = messages.first;
      notifyListeners();
      return false;
    }

    compositionExportStatus = CompositionExportStatus.preparing;
    compositionExportProgress = 0;
    compositionExportStage = '准备素材';
    compositionExportErrorMessage = null;
    compositionExportResult = null;
    notifyListeners();

    try {
      final result = await _videoCompositionService.export(compositionProject);
      compositionExportStatus = CompositionExportStatus.success;
      compositionExportProgress = 100;
      compositionExportStage = '导出完成';
      compositionExportResult = result;
      notifyListeners();
      return true;
    } on Exception catch (error) {
      compositionExportStatus = CompositionExportStatus.failure;
      compositionExportProgress = 0;
      compositionExportStage = '导出失败';
      compositionExportErrorMessage = _cleanError(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> cancelCompositionExport() async {
    if (!isExportingComposition) return;
    await _videoCompositionService.cancel();
    compositionExportStatus = CompositionExportStatus.canceled;
    compositionExportStage = '已取消';
    notifyListeners();
  }

  Future<void> pickAndAddLocalCompositionVideo() async {
    final picked = await _filePicker.pickSingleVideoFile();
    final uri = picked?.uri.trim() ?? '';
    if (picked == null || uri.isEmpty) return;

    addCompositionClip(
      CompositionClip.local(
        id: 'clip-${DateTime.now().millisecondsSinceEpoch}',
        label: picked.name,
        localUri: uri,
        fileName: picked.name,
        startMs: 0,
        endMs: picked.durationMs ?? 15000,
      ),
    );
    currentTab = AppTab.composition;
    notifyListeners();
  }

  Future<void> pickAndReplaceCompositionVideo(String clipId) async {
    final picked = await _filePicker.pickSingleVideoFile();
    final uri = picked?.uri.trim() ?? '';
    if (picked == null || uri.isEmpty) return;

    updateCompositionClip(
      clipId,
      (current) => current.copyWith(
        label: picked.name,
        sourceType: CompositionSourceType.localFile,
        sourceUri: uri,
        fileName: picked.name,
        startMs: 0,
        endMs: picked.durationMs ?? 15000,
        clearSourceId: true,
      ),
    );
  }

  Future<void> pickCompositionBgm() async {
    final picked = await _filePicker.pickSingleAudioFile();
    final uri = picked?.uri.trim() ?? '';
    if (picked == null || uri.isEmpty) return;

    updateCompositionAudio(
      compositionProject.audio.copyWith(
        bgmSource: CompositionBgmSource.local(
          id: 'bgm-${DateTime.now().millisecondsSinceEpoch}',
          label: picked.name,
          localUri: uri,
          fileName: picked.name,
        ),
      ),
    );
  }

  void setActiveMode(ModeId mode) {
    if (activeMode == mode) return;
    activeMode = mode;
    if (mode == ModeId.text) {
      selectedAttachmentIds.clear();
    }
    if (mode != ModeId.reference) {
      selectedAttachmentIds.clear();
      prompt = _normalizedVideoPromptForMode(prompt, mode);
      closeMention();
    }
    if (mode == ModeId.text || mode == ModeId.reference) {
      selectedFirstFrameAttachmentId = null;
      selectedLastFrameAttachmentId = null;
    } else if (mode == ModeId.firstFrame) {
      selectedLastFrameAttachmentId = null;
    }
    submitErrorMessage = null;
    notifyListeners();
    resolveActiveTool();
  }

  void updatePrompt(String value) {
    prompt = _normalizedVideoPromptForMode(value, activeMode);
    if (supportsPromptMentions) {
      _syncSelectedAttachmentsFromPrompt();
    }
    notifyListeners();
  }

  String mentionTokenForAttachment(Attachment attachment) {
    return '@{${attachment.label}}';
  }

  void inspectMention(String value, int cursor) {
    if (!supportsPromptMentions) {
      mentionOpen = false;
      mentionQuery = '';
      mentionCategoryFilter = 'all';
      mentionStart = null;
      mentionEnd = null;
      notifyListeners();
      return;
    }

    final beforeCursor = value.substring(0, cursor.clamp(0, value.length));
    final match = RegExp(r'@([^\s@]*)$').firstMatch(beforeCursor);

    if (match == null) {
      if (mentionOpen || mentionQuery.isNotEmpty) {
        mentionOpen = false;
        mentionQuery = '';
        mentionCategoryFilter = 'all';
        mentionStart = null;
        mentionEnd = null;
        notifyListeners();
      }
      return;
    }

    mentionOpen = true;
    mentionQuery = match.group(1) ?? '';
    mentionStart = match.start;
    mentionEnd = cursor;
    notifyListeners();
  }

  void closeMention() {
    if (!mentionOpen &&
        mentionQuery.isEmpty &&
        mentionCategoryFilter == 'all' &&
        mentionStart == null &&
        mentionEnd == null) {
      return;
    }
    mentionOpen = false;
    mentionQuery = '';
    mentionCategoryFilter = 'all';
    mentionStart = null;
    mentionEnd = null;
    notifyListeners();
  }

  void setMentionQuery(String value) {
    mentionQuery = value;
    notifyListeners();
  }

  void setMentionCategoryFilter(String value) {
    mentionCategoryFilter = value;
    notifyListeners();
  }

  void clearPrompt() {
    prompt = '';
    selectedAttachmentIds.clear();
    selectedFirstFrameAttachmentId = null;
    selectedLastFrameAttachmentId = null;
    closeMention();
    notifyListeners();
  }

  void updateMetadata(MetadataState Function(MetadataState current) update) {
    metadata = update(metadata);
    notifyListeners();
  }

  void updateSettings(SettingsState Function(SettingsState current) update) {
    final previousApiKey = settings.agentEarthApiKey;
    final previousBaseUrl = settings.agentEarthBaseUrl;
    final previousStorageProvider = settings.storageProvider;
    final previousBucket = settings.qiniuBucket;
    final previousAutoPoll = settings.autoPoll;
    final previousBitifulAccessKey = settings.bitifulAccessKey;
    final previousBitifulSecretKey = settings.bitifulSecretKey;
    final previousBitifulBucket = settings.bitifulBucket;
    final previousBitifulEndpoint = settings.bitifulEndpoint;
    final previousBitifulRegion = settings.bitifulRegion;
    settings = update(settings);
    if (previousAutoPoll != settings.autoPoll) {
      _applyAutoPollSetting(settings.autoPoll);
    }
    if (previousStorageProvider != settings.storageProvider) {
      configStatusMessage = _defaultStorageConfigMessage(
        provider: settings.storageProvider,
      );
    }
    if (previousBitifulAccessKey != settings.bitifulAccessKey ||
        previousBitifulSecretKey != settings.bitifulSecretKey ||
        previousBitifulBucket != settings.bitifulBucket ||
        previousBitifulEndpoint != settings.bitifulEndpoint ||
        previousBitifulRegion != settings.bitifulRegion) {
      _signedUrlCache.clear();
    }
    notifyListeners();
    if (previousApiKey != settings.agentEarthApiKey ||
        previousBaseUrl != settings.agentEarthBaseUrl) {
      _initializeToolResolutions();
      resolveActiveTool();
    }
    if (previousBucket != settings.qiniuBucket &&
        settings.storageProvider == StorageProvider.qiniu &&
        settings.qiniuBucket.isNotEmpty) {
      // 切换 bucket 后旧的私有属性失效，清空签名缓存并重置，由 fetchDomainList 重新查询。
      qiniuBucketPrivate =
          _qiniuBucketPrivateByBucket[settings.qiniuBucket.trim()];
      _signedUrlCache.removeWhere((key, _) => key.startsWith('qiniu:'));
      fetchDomainList();
    }
  }

  void toggleAttachmentSelection(String attachmentId) {
    if (activeMode != ModeId.reference) return;
    if (selectedAttachmentIds.contains(attachmentId)) {
      selectedAttachmentIds.remove(attachmentId);
    } else {
      selectedAttachmentIds.add(attachmentId);
    }
    notifyListeners();
  }

  void removeSelectedAttachment(String attachmentId) {
    if (activeMode != ModeId.reference) return;
    final attachment = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
    selectedAttachmentIds.remove(attachmentId);
    if (attachment != null) {
      prompt = prompt.replaceAll(mentionTokenForAttachment(attachment), '');
      prompt = prompt.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    }
    notifyListeners();
  }

  void selectVideoFrameAttachment(
    String attachmentId, {
    required AttachmentRole role,
  }) {
    if (role != AttachmentRole.firstFrame && role != AttachmentRole.lastFrame) {
      return;
    }
    final attachment = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
    if (attachment == null || attachment.kind != AttachmentKind.image) return;
    if (role == AttachmentRole.firstFrame) {
      selectedFirstFrameAttachmentId = attachmentId;
    } else {
      selectedLastFrameAttachmentId = attachmentId;
    }
    _markAttachmentUsed(attachmentId);
    notifyListeners();
  }

  void clearVideoFrameAttachment(AttachmentRole role) {
    if (role == AttachmentRole.firstFrame) {
      selectedFirstFrameAttachmentId = null;
    } else if (role == AttachmentRole.lastFrame) {
      selectedLastFrameAttachmentId = null;
    }
    notifyListeners();
  }

  void addImageReferenceAttachment(String attachmentId) {
    final attachment = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
    if (attachment == null || attachment.kind != AttachmentKind.image) return;
    if (!selectedImageAttachmentIds.contains(attachmentId)) {
      selectedImageAttachmentIds.add(attachmentId);
    }
    _markAttachmentUsed(attachmentId);
    notifyListeners();
  }

  void removeImageReferenceAttachment(String attachmentId) {
    selectedImageAttachmentIds.removeWhere((item) => item == attachmentId);
    notifyListeners();
  }

  void selectMentionAttachment(String attachmentId, {int? fallbackCursor}) {
    if (activeMode != ModeId.reference) return;
    final attachment = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
    if (attachment == null) return;
    if (!selectedAttachmentIds.contains(attachmentId)) {
      selectedAttachmentIds.add(attachmentId);
    }
    _markAttachmentUsed(attachmentId);

    if (mentionStart != null && mentionEnd != null) {
      final prefix = prompt.substring(0, mentionStart!);
      final suffix = prompt.substring(mentionEnd!);
      prompt = '$prefix${mentionTokenForAttachment(attachment)} $suffix'
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trimLeft();
    } else {
      final cursor = (fallbackCursor ?? prompt.length).clamp(0, prompt.length);
      final prefix = prompt.substring(0, cursor);
      final suffix = prompt.substring(cursor);
      prompt = '$prefix${mentionTokenForAttachment(attachment)} $suffix'
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trimLeft();
    }

    mentionOpen = false;
    mentionQuery = '';
    mentionCategoryFilter = 'all';
    mentionStart = null;
    mentionEnd = null;
    _syncSelectedAttachmentsFromPrompt();
    notifyListeners();
  }

  void replaceSelectedAttachment({
    required String currentAttachmentId,
    required String nextAttachmentId,
  }) {
    if (activeMode != ModeId.reference) return;
    if (currentAttachmentId == nextAttachmentId) return;
    final current = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == currentAttachmentId,
      orElse: () => null,
    );
    final next = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == nextAttachmentId,
      orElse: () => null,
    );
    if (current == null || next == null) return;
    final index = selectedAttachmentIds.indexOf(currentAttachmentId);
    if (index == -1) return;
    if (!selectedAttachmentIds.contains(nextAttachmentId)) {
      selectedAttachmentIds[index] = nextAttachmentId;
    } else {
      final nextIndex = selectedAttachmentIds.indexOf(nextAttachmentId);
      selectedAttachmentIds[index] = nextAttachmentId;
      selectedAttachmentIds[nextIndex] = currentAttachmentId;
    }
    prompt = prompt.replaceAll(
      mentionTokenForAttachment(current),
      mentionTokenForAttachment(next),
    );
    _markAttachmentUsed(nextAttachmentId);
    _syncSelectedAttachmentsFromPrompt();
    notifyListeners();
  }

  void setLibraryQuery(String value) {
    libraryQuery = value;
    notifyListeners();
  }

  void setLibraryFilter(LibraryFilter value) {
    libraryFilter = value;
    notifyListeners();
  }

  bool get hasActiveLibraryFilters =>
      libraryQuery.trim().isNotEmpty ||
      libraryFilter != LibraryFilter.all ||
      selectedCategoryFilters.isNotEmpty ||
      !libraryRecentFirst;

  void clearLibraryFilters() {
    libraryQuery = '';
    libraryFilter = LibraryFilter.all;
    selectedCategoryFilters.clear();
    libraryRecentFirst = true;
    notifyListeners();
  }

  void setLibraryRecentFirst(bool value) {
    if (libraryRecentFirst == value) return;
    libraryRecentFirst = value;
    notifyListeners();
  }

  void toggleCategoryFilter(String category) {
    if (selectedCategoryFilters.contains(category)) {
      selectedCategoryFilters.remove(category);
    } else {
      selectedCategoryFilters.add(category);
    }
    notifyListeners();
  }

  void updateAttachmentCategory(String attachmentId, String category) {
    final index = library.indexWhere((item) => item.id == attachmentId);
    if (index == -1) return;
    final normalized = category.trim();
    if (normalized.isNotEmpty && !categories.contains(normalized)) {
      categories.add(normalized);
    }
    library[index] = library[index].copyWith(category: normalized);
    notifyListeners();
  }

  bool addCategory(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || categories.contains(normalized)) {
      return false;
    }
    categories.add(normalized);
    notifyListeners();
    return true;
  }

  bool renameCategory(String previous, String next) {
    final normalizedPrevious = previous.trim();
    final normalizedNext = next.trim();
    if (normalizedPrevious.isEmpty ||
        normalizedNext.isEmpty ||
        normalizedPrevious == normalizedNext ||
        categories.contains(normalizedNext)) {
      return false;
    }
    final index = categories.indexOf(normalizedPrevious);
    if (index == -1) return false;
    categories[index] = normalizedNext;
    for (var i = 0; i < library.length; i++) {
      if (library[i].category == normalizedPrevious) {
        library[i] = library[i].copyWith(category: normalizedNext);
      }
    }
    if (selectedCategoryFilters.contains(normalizedPrevious)) {
      selectedCategoryFilters
        ..remove(normalizedPrevious)
        ..add(normalizedNext);
    }
    if (mentionCategoryFilter == normalizedPrevious) {
      mentionCategoryFilter = normalizedNext;
    }
    notifyListeners();
    return true;
  }

  bool deleteCategory(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return false;
    categories.removeWhere((item) => item == normalized);
    selectedCategoryFilters.removeWhere((item) => item == normalized);
    if (mentionCategoryFilter == normalized) {
      mentionCategoryFilter = 'all';
    }
    for (var i = 0; i < library.length; i++) {
      if (library[i].category == normalized) {
        library[i] = library[i].copyWith(category: '');
      }
    }
    notifyListeners();
    return true;
  }

  int attachmentCountForCategory(String category) {
    return library.where((item) => item.category == category).length;
  }

  void updateAttachmentRole(String attachmentId, AttachmentRole role) {
    final index = library.indexWhere((item) => item.id == attachmentId);
    if (index == -1) return;
    library[index] = library[index].copyWith(role: role);
    notifyListeners();
  }

  void removeFromLibrary(String attachmentId) {
    final attachment = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
    library.removeWhere((item) => item.id == attachmentId);
    selectedAttachmentIds.removeWhere((item) => item == attachmentId);
    selectedImageAttachmentIds.removeWhere((item) => item == attachmentId);
    if (selectedFirstFrameAttachmentId == attachmentId) {
      selectedFirstFrameAttachmentId = null;
    }
    if (selectedLastFrameAttachmentId == attachmentId) {
      selectedLastFrameAttachmentId = null;
    }
    if (attachment != null) {
      prompt = prompt.replaceAll(mentionTokenForAttachment(attachment), '');
      prompt = prompt.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    }
    notifyListeners();
  }

  Future<void> deleteAttachment(
    String attachmentId, {
    bool deleteRemote = false,
  }) async {
    final attachment = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
    if (attachment == null) return;

    if (deleteRemote) {
      final objectKey = attachment.objectKey?.trim();
      if (objectKey == null || objectKey.isEmpty) {
        throw StateError('当前素材缺少对象 Key，无法删除云端文件。');
      }
      switch (attachment.storageProvider) {
        case StorageProvider.qiniu:
          final bucket = attachment.storageBucket?.trim().isNotEmpty == true
              ? attachment.storageBucket!.trim()
              : settings.qiniuBucket.trim();
          if (bucket.isEmpty) {
            throw StateError('未配置七牛 Bucket，无法删除云端文件。');
          }
          await _qiniuUploadService.deleteObject(
            settings: settings,
            bucket: bucket,
            objectKey: objectKey,
          );
        case StorageProvider.bitifulS4:
          final bucket = attachment.storageBucket?.trim().isNotEmpty == true
              ? attachment.storageBucket!.trim()
              : settings.bitifulBucket.trim();
          final endpoint = attachment.storageEndpoint?.trim().isNotEmpty == true
              ? attachment.storageEndpoint!.trim()
              : settings.bitifulEndpoint.trim();
          final region = attachment.storageRegion?.trim().isNotEmpty == true
              ? attachment.storageRegion!.trim()
              : settings.bitifulRegion.trim();
          if (bucket.isEmpty || endpoint.isEmpty || region.isEmpty) {
            throw StateError('缤纷云存储配置不完整，无法删除云端文件。');
          }
          await _bitifulUploadService.deleteObject(
            settings: settings,
            objectKey: objectKey,
            bucket: bucket,
            endpoint: endpoint,
            region: region,
          );
      }
      _signedUrlCache.removeWhere(
        (key, _) => key.contains(':${attachment.id}:$objectKey'),
      );
    }

    removeFromLibrary(attachmentId);
  }

  Future<BatchDeleteAttachmentsResult> deleteAttachments(
    Iterable<String> attachmentIds, {
    bool deleteRemote = false,
  }) async {
    var deletedCount = 0;
    final failures = <BatchDeleteAttachmentFailure>[];
    for (final attachmentId in attachmentIds.toSet()) {
      final attachment = library.cast<Attachment?>().firstWhere(
        (item) => item?.id == attachmentId,
        orElse: () => null,
      );
      if (attachment == null) continue;
      try {
        final canDeleteRemote =
            deleteRemote && attachment.objectKey?.trim().isNotEmpty == true;
        await deleteAttachment(attachmentId, deleteRemote: canDeleteRemote);
        deletedCount++;
      } on Exception catch (error) {
        failures.add(
          BatchDeleteAttachmentFailure(
            attachment: attachment,
            message: _cleanError(error),
          ),
        );
      }
    }
    return BatchDeleteAttachmentsResult(
      deletedCount: deletedCount,
      failures: failures,
    );
  }

  void archiveTask(String taskId) {
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return;
    tasks[index] = tasks[index].copyWith(archivedAt: DateTime.now());
    expandedPollLogTaskIds.remove(taskId);
    notifyListeners();
    _stopAutoPollingIfIdle();
  }

  void restoreTask(String taskId) {
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return;
    tasks[index] = tasks[index].copyWith(clearArchivedAt: true);
    notifyListeners();
    _startAutoPollingIfNeeded();
  }

  void _markAttachmentUsed(String attachmentId) {
    attachmentLastUsedAt[attachmentId] = DateTime.now().millisecondsSinceEpoch;
  }

  int _compareAttachments(Attachment a, Attachment b) {
    if (libraryRecentFirst) {
      final recentA = attachmentLastUsedAt[a.id] ?? 0;
      final recentB = attachmentLastUsedAt[b.id] ?? 0;
      if (recentA != recentB) {
        return recentB.compareTo(recentA);
      }
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  Future<void> resolveActiveTool() async {
    if (!isAgentEarthConfigured) {
      _initializeToolResolutions();
      notifyListeners();
      return;
    }

    final mode = activeMode;
    final current = toolResolutions[mode];
    if (current?.status == ToolResolutionStatus.ready ||
        current?.status == ToolResolutionStatus.loading) {
      return;
    }

    toolResolutions[mode] = ToolResolution(
      status: ToolResolutionStatus.loading,
      tool:
          current?.tool ??
          fallbackToolForMode(mode, baseUrl: settings.agentEarthBaseUrl),
    );
    notifyListeners();

    try {
      final tool = await _seedanceService.resolveTool(
        settings.agentEarthApiKey,
        mode,
        baseUrl: settings.agentEarthBaseUrl,
      );
      toolResolutions[mode] = ToolResolution(
        status: ToolResolutionStatus.ready,
        tool: tool,
      );
    } on Exception catch (error) {
      toolResolutions[mode] = ToolResolution(
        status: ToolResolutionStatus.error,
        tool: fallbackToolForMode(mode, baseUrl: settings.agentEarthBaseUrl),
        errorMessage: _cleanError(error),
      );
    }
    notifyListeners();
  }

  Future<void> resolveImageTool() async {
    if (!isAgentEarthConfigured) {
      imageToolResolution = ToolResolution(status: ToolResolutionStatus.idle);
      notifyListeners();
      return;
    }

    imageToolResolution = ToolResolution(status: ToolResolutionStatus.loading);
    notifyListeners();

    try {
      final tool = await _imageGenerationService.resolveTool(
        settings.agentEarthApiKey,
        mode: activeImageMode,
        baseUrl: settings.agentEarthBaseUrl,
        allowFallback: settings.imageAutoFallbackEnabled,
      );
      imageToolResolution = ToolResolution(
        status: ToolResolutionStatus.ready,
        tool: tool,
      );
    } on Exception catch (error) {
      imageToolResolution = ToolResolution(
        status: ToolResolutionStatus.error,
        errorMessage: _cleanError(error),
      );
    }
    notifyListeners();
  }

  Future<bool> submitTask() async {
    if (!isAgentEarthConfigured) {
      submitErrorMessage = '请先在设置里填写 AgentEarth API Key。';
      notifyListeners();
      return false;
    }
    if (validationMessages.isNotEmpty || isSubmitting) {
      submitErrorMessage = validationMessages.isNotEmpty
          ? validationMessages.first
          : '任务正在提交中。';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    submitErrorMessage = null;
    notifyListeners();

    final mode = activeMode;
    final taskPrompt = effectiveVideoPrompt;
    final taskMetadata = metadata;
    final taskAttachments = List<Attachment>.from(selectedAttachments);

    try {
      final submissionAttachments = await _resolveAttachmentsForSeedance(
        taskAttachments,
      );
      await resolveActiveTool();
      final tool = toolResolutions[mode]?.status == ToolResolutionStatus.ready
          ? toolResolutions[mode]?.tool
          : null;
      final execution = await _seedanceService.execute(
        apiKey: settings.agentEarthApiKey,
        mode: mode,
        prompt: taskPrompt,
        metadata: taskMetadata,
        attachments: submissionAttachments,
        baseUrl: settings.agentEarthBaseUrl,
        tool: tool,
      );
      final now = DateTime.now();
      tasks.insert(
        0,
        TaskRecord(
          id: 'mova-${now.microsecondsSinceEpoch}',
          mode: mode,
          prompt: taskPrompt,
          status: TaskStatus.submitted,
          pollingStatus: settings.autoPoll
              ? PollingStatus.polling
              : PollingStatus.idle,
          downloadStatus: DownloadStatus.idle,
          progress: 10,
          downloadProgress: 0,
          createdAt: now,
          updatedAt: now,
          estimatedCredit: execution.credit,
          attachments: taskAttachments,
          requestPreview: execution.requestPreview.prettyJson,
          responsePreview: execution.responsePreview,
          responseUrl: execution.responseUrl,
          statusUrl: execution.statusUrl,
          toolName: execution.toolName,
          statusDetail: '已提交，等待上游生成。',
          hasAnomaly: false,
        ),
      );
      currentTab = AppTab.tasks;
      activeTaskTab = TaskTab.video;
      showArchivedTasks = false;
      isSubmitting = false;
      notifyListeners();
      if (settings.autoPoll) {
        unawaited(refreshTask(tasks.first.id));
        _startAutoPollingIfNeeded();
      }
      return true;
    } on TaskExecutionException catch (error) {
      submitErrorMessage = error.message;
    } on Exception catch (error) {
      submitErrorMessage = _cleanError(error);
    }

    isSubmitting = false;
    notifyListeners();
    return false;
  }

  void copyTaskToCreate(String taskId) {
    final task = tasks.cast<TaskRecord?>().firstWhere(
      (item) => item?.id == taskId,
      orElse: () => null,
    );
    if (task == null) return;

    activeMode = task.mode;
    prompt = task.prompt;
    metadata = metadata.copyWith();
    _restoreVideoAttachmentStateFromTask(task);
    currentTab = AppTab.create;
    notifyListeners();
  }

  void copyImageTaskToCreate(String taskId) {
    final task = tasks.cast<TaskRecord?>().firstWhere(
      (item) => item?.id == taskId,
      orElse: () => null,
    );
    if (task == null || task.kind != TaskKind.image) return;

    imagePrompt = task.prompt;
    imageMetadata = task.imageMetadata ?? imageMetadataDefaults;
    activeImageMode = task.imageMode ?? ImageCreateMode.textToImage;
    selectedImageAttachmentIds
      ..clear()
      ..addAll(
        task.attachments
            .where((item) => item.kind == AttachmentKind.image)
            .map((item) => item.id),
      );
    imageToolResolution = ToolResolution(status: ToolResolutionStatus.idle);
    currentTab = AppTab.create;
    notifyListeners();
  }

  Future<bool> submitImageTask() async {
    if (!isAgentEarthConfigured) {
      imageSubmitErrorMessage = '请先在设置里填写 AgentEarth API Key。';
      notifyListeners();
      return false;
    }
    if (imagePrompt.trim().isEmpty) {
      imageSubmitErrorMessage = 'Prompt 不能为空。';
      notifyListeners();
      return false;
    }
    if (imagePrompt.length > 2000) {
      imageSubmitErrorMessage = 'Prompt 不能超过 2000 字符。';
      notifyListeners();
      return false;
    }
    if (activeImageMode == ImageCreateMode.imageToImage &&
        selectedImageAttachments.isEmpty) {
      imageSubmitErrorMessage = '图生图至少需要选择一张参考图。';
      notifyListeners();
      return false;
    }
    if (isSubmittingImageTask) {
      imageSubmitErrorMessage = '任务正在提交中。';
      notifyListeners();
      return false;
    }

    isSubmittingImageTask = true;
    imageSubmitErrorMessage = null;
    notifyListeners();

    try {
      final submissionAttachments = await _resolveImageAttachmentsForGeneration(
        List<Attachment>.from(selectedImageAttachments),
      );
      await resolveImageTool();
      final execution = await _imageGenerationService.execute(
        apiKey: settings.agentEarthApiKey,
        mode: activeImageMode,
        prompt: imagePrompt,
        metadata: imageMetadata,
        attachments: submissionAttachments,
        baseUrl: settings.agentEarthBaseUrl,
        tool: imageToolResolution.tool,
        allowFallback: settings.imageAutoFallbackEnabled,
      );

      final now = DateTime.now();
      final numImages = imageMetadata.numImages;
      final imageResults = List<ImageTaskResultItem>.generate(numImages, (i) {
        return ImageTaskResultItem(
          id: 'img-${now.microsecondsSinceEpoch}-$i',
          status: ImageResultStatus.queued,
        );
      });

      tasks.insert(
        0,
        TaskRecord(
          id: 'mova-img-${now.microsecondsSinceEpoch}',
          kind: TaskKind.image,
          mode: ModeId.text,
          imageMode: activeImageMode,
          prompt: imagePrompt,
          status: TaskStatus.submitted,
          pollingStatus: settings.autoPoll
              ? PollingStatus.polling
              : PollingStatus.idle,
          downloadStatus: DownloadStatus.idle,
          progress: 10,
          downloadProgress: 0,
          createdAt: now,
          updatedAt: now,
          estimatedCredit: execution.credit,
          attachments: submissionAttachments,
          requestPreview: execution.requestPreview.prettyJson,
          responsePreview: execution.responsePreview,
          responseUrl: execution.responseUrl,
          statusUrl: execution.statusUrl,
          toolName: execution.toolName,
          statusDetail: '已提交，等待上游生成。',
          hasAnomaly: false,
          imageResults: imageResults,
          imageMetadata: imageMetadata,
        ),
      );

      currentTab = AppTab.tasks;
      activeTaskTab = TaskTab.image;
      showArchivedTasks = false;
      isSubmittingImageTask = false;
      notifyListeners();

      if (settings.autoPoll) {
        unawaited(refreshImageTask(tasks.first.id));
        _startAutoPollingIfNeeded();
      }
      return true;
    } on TaskExecutionException catch (error) {
      imageSubmitErrorMessage = error.message;
    } on Exception catch (error) {
      imageSubmitErrorMessage = _cleanError(error);
    }

    isSubmittingImageTask = false;
    notifyListeners();
    return false;
  }

  Future<bool> refreshTask(String taskId) async {
    if (!isAgentEarthConfigured) {
      return false;
    }
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return false;
    if (_refreshingTaskIds.contains(taskId)) return true;
    final task = tasks[index];
    if (task.kind == TaskKind.image) {
      return refreshImageTask(taskId);
    }
    final pollUrl = _pollUrlForTask(task);
    if (pollUrl == null || pollUrl.trim().isEmpty) {
      tasks[index] = task.copyWith(
        status: TaskStatus.failure,
        pollingStatus: PollingStatus.error,
        lastError: '任务缺少 status_url/response_url，无法查询上游状态。',
        statusDetail: '缺少查询 URL',
        updatedAt: DateTime.now(),
        hasAnomaly: true,
        anomalyMessage: '缺少状态查询地址',
      );
      notifyListeners();
      return false;
    }

    _refreshingTaskIds.add(taskId);
    tasks[index] = task.copyWith(
      pollingStatus: PollingStatus.polling,
      status: task.status == TaskStatus.submitted
          ? TaskStatus.inProgress
          : task.status,
      statusDetail: '正在查询上游状态...',
      updatedAt: DateTime.now(),
      clearLastError: true,
      hasAnomaly: false,
      clearAnomalyMessage: true,
    );
    notifyListeners();

    try {
      final result = await _seedanceService.poll(
        apiKey: settings.agentEarthApiKey,
        responseUrl: pollUrl,
        baseUrl: settings.agentEarthBaseUrl,
        finalResponseUrl: task.responseUrl,
      );
      final nextPolling =
          result.status == TaskStatus.success ||
              result.status == TaskStatus.failure
          ? PollingStatus.idle
          : PollingStatus.polling;
      final nextDownload =
          result.status == TaskStatus.success &&
              task.downloadStatus == DownloadStatus.error
          ? DownloadStatus.idle
          : task.downloadStatus;
      final latestIndex = tasks.indexWhere((item) => item.id == taskId);
      if (latestIndex == -1) return false;
      final currentTask = tasks[latestIndex];
      final summary = result.lastError ?? result.statusDetail ?? '查询完成';
      tasks[latestIndex] = _appendPollLog(
        currentTask.copyWith(
          status: result.status,
          pollingStatus: nextPolling,
          downloadStatus: nextDownload,
          progress: result.progress < currentTask.progress
              ? currentTask.progress
              : result.progress,
          videoUrl: result.videoUrl,
          statusDetail: result.statusDetail,
          lastError: result.lastError,
          responsePreview: result.responsePreview,
          statusUrl: pollUrl.endsWith('/status')
              ? pollUrl
              : currentTask.statusUrl,
          updatedAt: DateTime.now(),
          clearLastError: result.lastError == null,
          hasAnomaly: result.hasAnomaly,
          anomalyMessage: result.anomalyMessage,
          clearAnomalyMessage: !result.hasAnomaly,
        ),
        TaskPollLog(
          createdAt: DateTime.now(),
          success: result.lastError == null,
          summary: summary,
          requestPreview: result.requestPreview,
          responsePreview: result.responsePreview,
        ),
      );
      if (settings.autoDownload &&
          result.status == TaskStatus.success &&
          result.videoUrl != null &&
          result.videoUrl!.trim().isNotEmpty &&
          currentTask.localResourceUri == null &&
          currentTask.downloadStatus != DownloadStatus.downloading) {
        unawaited(downloadTaskResult(taskId));
      }
      notifyListeners();
      return true;
    } on Exception catch (error) {
      final latestIndex = tasks.indexWhere((item) => item.id == taskId);
      if (latestIndex == -1) return false;
      final currentTask = tasks[latestIndex];
      final fallbackPollUrl = _pollUrlForTask(currentTask);
      final requestPreview = fallbackPollUrl == null
          ? '{}'
          : buildPollRequestPreview(
              fallbackPollUrl,
              baseUrl: settings.agentEarthBaseUrl,
            );
      final responsePreview = jsonEncode({'error': _cleanError(error)});
      if (_isTransientPollingError(error)) {
        tasks[latestIndex] = _appendPollLog(
          currentTask.copyWith(
            pollingStatus: PollingStatus.polling,
            status: currentTask.status == TaskStatus.submitted
                ? TaskStatus.inProgress
                : currentTask.status,
            statusDetail: '查询失败，等待自动重试',
            lastError: _cleanError(error),
            updatedAt: DateTime.now(),
            hasAnomaly: true,
            anomalyMessage: _cleanError(error),
          ),
          TaskPollLog(
            createdAt: DateTime.now(),
            success: false,
            summary: _cleanError(error),
            requestPreview: requestPreview,
            responsePreview: responsePreview,
          ),
        );
        notifyListeners();
        return false;
      }
      tasks[latestIndex] = _appendPollLog(
        currentTask.copyWith(
          pollingStatus: PollingStatus.error,
          statusDetail: '查询失败',
          lastError: _cleanError(error),
          updatedAt: DateTime.now(),
          hasAnomaly: true,
          anomalyMessage: _cleanError(error),
        ),
        TaskPollLog(
          createdAt: DateTime.now(),
          success: false,
          summary: _cleanError(error),
          requestPreview: requestPreview,
          responsePreview: responsePreview,
        ),
      );
      notifyListeners();
      return false;
    } finally {
      _refreshingTaskIds.remove(taskId);
      if (_hasPollingTasks) {
        _startAutoPollingIfNeeded();
      } else {
        _stopAutoPollingIfIdle();
      }
    }
  }

  bool regenerateTask(String taskId) {
    return false;
  }

  void deleteTask(String taskId) {
    tasks.removeWhere((task) => task.id == taskId);
    expandedPollLogTaskIds.remove(taskId);
    notifyListeners();
    _stopAutoPollingIfIdle();
  }

  Future<bool> refreshImageTask(String taskId) async {
    if (!isAgentEarthConfigured) return false;
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return false;
    if (_refreshingTaskIds.contains(taskId)) return true;
    final task = tasks[index];
    if (task.kind != TaskKind.image) return false;

    final pollUrl = _pollUrlForTask(task);
    if (pollUrl == null || pollUrl.trim().isEmpty) {
      tasks[index] = task.copyWith(
        status: TaskStatus.failure,
        pollingStatus: PollingStatus.error,
        lastError: '任务缺少 status_url/response_url，无法查询上游状态。',
        statusDetail: '缺少查询 URL',
        updatedAt: DateTime.now(),
        hasAnomaly: true,
        anomalyMessage: '缺少状态查询地址',
      );
      notifyListeners();
      return false;
    }

    _refreshingTaskIds.add(taskId);
    tasks[index] = task.copyWith(
      pollingStatus: PollingStatus.polling,
      status: task.status == TaskStatus.submitted
          ? TaskStatus.inProgress
          : task.status,
      statusDetail: '正在查询上游状态...',
      updatedAt: DateTime.now(),
      clearLastError: true,
      hasAnomaly: false,
      clearAnomalyMessage: true,
    );
    notifyListeners();

    try {
      final result = await _imageGenerationService.poll(
        apiKey: settings.agentEarthApiKey,
        responseUrl: pollUrl,
        baseUrl: settings.agentEarthBaseUrl,
      );
      final effectiveImageUrls = result.imageUrls.isNotEmpty
          ? result.imageUrls
          : _extractImageUrlsFromPreview(result.responsePreview);

      final effectiveStatus =
          effectiveImageUrls.isNotEmpty && result.status != TaskStatus.failure
          ? TaskStatus.success
          : result.status;
      final effectiveStatusDetail =
          effectiveImageUrls.isNotEmpty &&
              (result.statusDetail == null ||
                  result.statusDetail == 'COMPLETED，等待结果文件返回')
          ? 'SUCCESS (${effectiveImageUrls.length} images)'
          : result.statusDetail;
      final effectiveHasAnomaly = effectiveImageUrls.isNotEmpty
          ? false
          : result.hasAnomaly;
      final effectiveAnomalyMessage = effectiveImageUrls.isNotEmpty
          ? null
          : result.anomalyMessage;

      final isDone =
          effectiveStatus == TaskStatus.success ||
          effectiveStatus == TaskStatus.failure;
      final nextPolling = isDone ? PollingStatus.idle : PollingStatus.polling;

      final latestIndex = tasks.indexWhere((item) => item.id == taskId);
      if (latestIndex == -1) return false;
      final currentTask = tasks[latestIndex];

      List<ImageTaskResultItem> updatedResults = List.from(
        currentTask.imageResults,
      );
      for (
        var i = 0;
        i < effectiveImageUrls.length && i < updatedResults.length;
        i++
      ) {
        if (updatedResults[i].remoteUrl == null ||
            updatedResults[i].remoteUrl!.isEmpty) {
          updatedResults[i] = updatedResults[i].copyWith(
            remoteUrl: effectiveImageUrls[i],
            status: ImageResultStatus.readyToTransfer,
            updatedAt: DateTime.now(),
          );
        }
      }

      final summary = result.lastError ?? effectiveStatusDetail ?? '查询完成';
      tasks[latestIndex] = _appendPollLog(
        currentTask.copyWith(
          status: effectiveStatus,
          pollingStatus: nextPolling,
          progress: result.progress < currentTask.progress
              ? currentTask.progress
              : result.progress,
          statusDetail: effectiveStatusDetail,
          lastError: result.lastError,
          responsePreview: result.responsePreview,
          updatedAt: DateTime.now(),
          clearLastError: result.lastError == null,
          hasAnomaly: effectiveHasAnomaly,
          anomalyMessage: effectiveAnomalyMessage,
          clearAnomalyMessage: !effectiveHasAnomaly,
          imageResults: updatedResults,
        ),
        TaskPollLog(
          createdAt: DateTime.now(),
          success: result.lastError == null,
          summary: summary,
          requestPreview: result.requestPreview,
          responsePreview: result.responsePreview,
        ),
      );

      if (effectiveStatus == TaskStatus.success && isCurrentStorageConfigured) {
        unawaited(_transferImageResults(taskId));
      }

      notifyListeners();
      return true;
    } on Exception catch (error) {
      final latestIndex = tasks.indexWhere((item) => item.id == taskId);
      if (latestIndex == -1) return false;
      final currentTask = tasks[latestIndex];
      final fallbackPollUrl = _pollUrlForTask(currentTask);
      final requestPreview = fallbackPollUrl == null
          ? '{}'
          : buildPollRequestPreview(
              fallbackPollUrl,
              baseUrl: settings.agentEarthBaseUrl,
            );
      final responsePreview = jsonEncode({'error': _cleanError(error)});
      if (_isTransientPollingError(error)) {
        tasks[latestIndex] = _appendPollLog(
          currentTask.copyWith(
            pollingStatus: PollingStatus.polling,
            status: currentTask.status == TaskStatus.submitted
                ? TaskStatus.inProgress
                : currentTask.status,
            statusDetail: '查询失败，等待自动重试',
            lastError: _cleanError(error),
            updatedAt: DateTime.now(),
            hasAnomaly: true,
            anomalyMessage: _cleanError(error),
          ),
          TaskPollLog(
            createdAt: DateTime.now(),
            success: false,
            summary: _cleanError(error),
            requestPreview: requestPreview,
            responsePreview: responsePreview,
          ),
        );
        notifyListeners();
        return false;
      }
      tasks[latestIndex] = _appendPollLog(
        currentTask.copyWith(
          pollingStatus: PollingStatus.error,
          statusDetail: '查询失败',
          lastError: _cleanError(error),
          updatedAt: DateTime.now(),
          hasAnomaly: true,
          anomalyMessage: _cleanError(error),
        ),
        TaskPollLog(
          createdAt: DateTime.now(),
          success: false,
          summary: _cleanError(error),
          requestPreview: requestPreview,
          responsePreview: responsePreview,
        ),
      );
      notifyListeners();
      return false;
    } finally {
      _refreshingTaskIds.remove(taskId);
      if (_hasPollingTasks) {
        _startAutoPollingIfNeeded();
      } else {
        _stopAutoPollingIfIdle();
      }
    }
  }

  void toggleTaskPollLogs(String taskId) {
    if (expandedPollLogTaskIds.contains(taskId)) {
      expandedPollLogTaskIds.remove(taskId);
    } else {
      expandedPollLogTaskIds.add(taskId);
    }
    notifyListeners();
  }

  void toggleTaskPolling(String taskId) {
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return;

    final task = tasks[index];
    final nextPolling = task.pollingStatus == PollingStatus.polling
        ? PollingStatus.paused
        : PollingStatus.polling;

    tasks[index] = task.copyWith(
      pollingStatus: nextPolling,
      status: nextPolling == PollingStatus.polling
          ? TaskStatus.inProgress
          : task.status,
      statusDetail: nextPolling == PollingStatus.polling
          ? '已恢复轮询上游状态'
          : '已暂停自动轮询',
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    if (nextPolling == PollingStatus.polling) {
      _startAutoPollingIfNeeded();
    } else {
      _stopAutoPollingIfIdle();
    }
  }

  Future<bool> retryTask(String taskId) async {
    final task = tasks.cast<TaskRecord?>().firstWhere(
      (item) => item?.id == taskId,
      orElse: () => null,
    );
    if (task == null) return false;
    if (task.kind == TaskKind.image) {
      if (isSubmittingImageTask) return false;
      imagePrompt = task.prompt;
      imageMetadata = task.imageMetadata ?? imageMetadataDefaults;
      activeImageMode = task.imageMode ?? ImageCreateMode.textToImage;
      selectedImageAttachmentIds
        ..clear()
        ..addAll(
          task.attachments
              .where((item) => item.kind == AttachmentKind.image)
              .map((item) => item.id),
        );
      imageToolResolution = ToolResolution(status: ToolResolutionStatus.idle);
      notifyListeners();
      return submitImageTask();
    }
    if (isSubmitting) return false;
    activeMode = task.mode;
    prompt = task.prompt;
    _restoreVideoAttachmentStateFromTask(task);
    notifyListeners();
    return submitTask();
  }

  Future<bool> downloadTaskResult(String taskId) async {
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return false;
    final task = tasks[index];
    final videoUrl = task.videoUrl;
    if (videoUrl == null || videoUrl.trim().isEmpty) {
      tasks[index] = task.copyWith(
        downloadStatus: DownloadStatus.error,
        lastError: '任务没有可下载的视频 URL。',
        updatedAt: DateTime.now(),
        hasAnomaly: true,
        anomalyMessage: '生成完成但未返回可下载资源',
      );
      notifyListeners();
      return false;
    }

    tasks[index] = task.copyWith(
      downloadStatus: DownloadStatus.downloading,
      downloadProgress: 0,
      updatedAt: DateTime.now(),
      clearLastError: true,
      hasAnomaly: false,
      clearAnomalyMessage: true,
    );
    notifyListeners();

    final client = HttpClient();
    try {
      final uri = Uri.parse(videoUrl);
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败（HTTP ${response.statusCode}）', uri: uri);
      }
      final fileName =
          _lastPathSegment(videoUrl) ??
          'seedance-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final tempFile = File('${Directory.systemTemp.path}/$fileName');
      final sink = tempFile.openWrite();
      final total = response.contentLength;
      var downloaded = 0;
      var lastNotifiedProgress = -1;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          downloaded += chunk.length;
          final latestIndex = tasks.indexWhere((item) => item.id == taskId);
          if (latestIndex != -1 && total > 0) {
            final nextProgress = ((downloaded / total) * 100).round().clamp(
              0,
              100,
            );
            // 节流：百分比未变就不 notify，避免大文件下载时每个 chunk 都触发全树重建。
            if (nextProgress != lastNotifiedProgress) {
              lastNotifiedProgress = nextProgress;
              tasks[latestIndex] = tasks[latestIndex].copyWith(
                downloadProgress: nextProgress,
                updatedAt: DateTime.now(),
              );
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }

      final saved = await _mediaChannel.invokeMapMethod<String, Object?>(
        'saveVideoToGallery',
        {'sourcePath': tempFile.path, 'fileName': fileName},
      );
      final savedPath = saved?['path'] as String?;
      final savedUri = saved?['uri'] as String?;

      final latestIndex = tasks.indexWhere((item) => item.id == taskId);
      if (latestIndex == -1) return false;
      tasks[latestIndex] = tasks[latestIndex].copyWith(
        downloadStatus: DownloadStatus.success,
        downloadProgress: 100,
        localFileName: savedPath ?? tempFile.path,
        localResourceUri: savedUri ?? savedPath ?? tempFile.path,
        updatedAt: DateTime.now(),
        hasAnomaly: false,
        clearAnomalyMessage: true,
      );
      notifyListeners();
      return true;
    } on Exception catch (error) {
      final latestIndex = tasks.indexWhere((item) => item.id == taskId);
      if (latestIndex == -1) return false;
      tasks[latestIndex] = tasks[latestIndex].copyWith(
        downloadStatus: DownloadStatus.error,
        downloadProgress: 0,
        lastError: _cleanError(error),
        updatedAt: DateTime.now(),
        hasAnomaly: true,
        anomalyMessage: '下载失败：${_cleanError(error)}',
      );
      notifyListeners();
      return false;
    } finally {
      client.close(force: false);
    }
  }

  Future<void> _transferImageResults(String taskId) async {
    if (_transferringImageTaskIds.contains(taskId)) return;
    _transferringImageTaskIds.add(taskId);
    try {
      while (true) {
        final index = tasks.indexWhere((task) => task.id == taskId);
        if (index == -1) return;
        final task = tasks[index];
        if (task.kind != TaskKind.image) return;

        final pendingIndex = task.imageResults.indexWhere(
          (item) =>
              (item.status == ImageResultStatus.readyToTransfer ||
                  item.status == ImageResultStatus.downloadFailed ||
                  item.status == ImageResultStatus.uploadFailed) &&
              item.remoteUrl != null &&
              item.remoteUrl!.isNotEmpty,
        );
        if (pendingIndex == -1) {
          _aggregateImageTaskStatus(taskId);
          return;
        }

        final item = task.imageResults[pendingIndex];
        final activeMetadata = task.imageMetadata ?? imageMetadata;
        final fileExtension = activeMetadata.outputFormat.trim().isEmpty
            ? 'png'
            : activeMetadata.outputFormat.trim();

        tasks[index] = task.copyWith(
          imageResults: _updateImageResult(
            task.imageResults,
            pendingIndex,
            item.copyWith(
              status: ImageResultStatus.downloading,
              updatedAt: DateTime.now(),
            ),
          ),
        );
        notifyListeners();

        File? tempFile;
        try {
          tempFile = await downloadRemoteImageToTemp(
            item.remoteUrl!,
            'img-${item.id}.$fileExtension',
          );
        } on Exception catch (error) {
          final latestIndex = tasks.indexWhere((entry) => entry.id == taskId);
          if (latestIndex == -1) return;
          final latestTask = tasks[latestIndex];
          tasks[latestIndex] = latestTask.copyWith(
            imageResults: _updateImageResult(
              latestTask.imageResults,
              pendingIndex,
              item.copyWith(
                status: ImageResultStatus.downloadFailed,
                lastError: '下载失败：${_cleanError(error)}',
                downloadRetryCount: item.downloadRetryCount + 1,
                updatedAt: DateTime.now(),
              ),
            ),
          );
          notifyListeners();
          continue;
        }

        final downloadIndex = tasks.indexWhere((entry) => entry.id == taskId);
        if (downloadIndex == -1) return;
        final taskAfterDownload = tasks[downloadIndex];
        tasks[downloadIndex] = taskAfterDownload.copyWith(
          imageResults: _updateImageResult(
            taskAfterDownload.imageResults,
            pendingIndex,
            item.copyWith(
              status: ImageResultStatus.uploading,
              localTempPath: tempFile.path,
              updatedAt: DateTime.now(),
            ),
          ),
        );
        notifyListeners();

        try {
          final mimeType = 'image/$fileExtension';
          final bytes = await tempFile.readAsBytes();
          final pickedFile = PickedNativeFile.fromBytes(
            name: 'ai-image-${item.id}.$fileExtension',
            mimeType: mimeType,
            bytes: bytes,
          );

          final uploadResult = await switch (settings.storageProvider) {
            StorageProvider.qiniu => _qiniuUploadService.upload(
              settings: settings,
              file: pickedFile,
            ),
            StorageProvider.bitifulS4 => _bitifulUploadService.upload(
              settings: settings,
              file: pickedFile,
            ),
          };

          final attachmentId = await insertUploadedAttachment(
            uploadResult,
            labelOverride: 'AI图片-${DateTime.now().millisecondsSinceEpoch}',
            roleOverride: activeMetadata.role,
            categoryOverride: activeMetadata.category,
            sourceTaskId: taskId,
          );

          final latestIndex = tasks.indexWhere((entry) => entry.id == taskId);
          if (latestIndex == -1) return;
          final latestTask = tasks[latestIndex];
          tasks[latestIndex] = latestTask.copyWith(
            imageResults: _updateImageResult(
              latestTask.imageResults,
              pendingIndex,
              item.copyWith(
                status: ImageResultStatus.imported,
                localTempPath: tempFile.path,
                storageUrl: uploadResult.url,
                attachmentId: attachmentId,
                updatedAt: DateTime.now(),
                clearLastError: true,
              ),
            ),
          );
          notifyListeners();
        } on Exception catch (error) {
          final latestIndex = tasks.indexWhere((entry) => entry.id == taskId);
          if (latestIndex == -1) return;
          final latestTask = tasks[latestIndex];
          tasks[latestIndex] = latestTask.copyWith(
            imageResults: _updateImageResult(
              latestTask.imageResults,
              pendingIndex,
              item.copyWith(
                localTempPath: tempFile.path,
                status: ImageResultStatus.uploadFailed,
                lastError: '上传失败：${_cleanError(error)}',
                uploadRetryCount: item.uploadRetryCount + 1,
                updatedAt: DateTime.now(),
              ),
            ),
          );
          notifyListeners();
        }
      }
    } finally {
      _transferringImageTaskIds.remove(taskId);
      _aggregateImageTaskStatus(taskId);
    }
  }

  void _aggregateImageTaskStatus(String taskId) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = tasks[index];
    final results = task.imageResults;
    final imported = results
        .where((r) => r.status == ImageResultStatus.imported)
        .length;
    final total = results.length;
    final failed = results
        .where(
          (r) =>
              r.status == ImageResultStatus.downloadFailed ||
              r.status == ImageResultStatus.uploadFailed,
        )
        .length;

    if (imported == total) {
      tasks[index] = task.copyWith(
        status: TaskStatus.success,
        statusDetail: '全部图片已入库',
        updatedAt: DateTime.now(),
      );
    } else if (failed > 0 && imported + failed == total) {
      tasks[index] = task.copyWith(
        statusDetail: '已入库 $imported/$total 张，$failed 张失败',
        updatedAt: DateTime.now(),
      );
    } else if (imported > 0) {
      tasks[index] = task.copyWith(
        statusDetail: '已入库 $imported/$total 张，正在转存',
        updatedAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  List<ImageTaskResultItem> _updateImageResult(
    List<ImageTaskResultItem> results,
    int index,
    ImageTaskResultItem updated,
  ) {
    final copy = List<ImageTaskResultItem>.from(results);
    copy[index] = updated;
    return copy;
  }

  Future<File> downloadRemoteImageToTemp(String url, String fileName) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败（HTTP \${response.statusCode}）', uri: uri);
      }
      final tempFile = File('${Directory.systemTemp.path}/$fileName');
      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return tempFile;
    } finally {
      client.close(force: false);
    }
  }

  Future<String?> saveCompositionExportToGallery() async {
    final result = compositionExportResult;
    if (result == null) return null;
    if (!File(result.localPath).existsSync()) {
      compositionExportResult = null;
      compositionExportErrorMessage = '上次导出的文件已不存在，请重新导出。';
      notifyListeners();
      return null;
    }
    final saved = await _mediaChannel.invokeMapMethod<String, Object?>(
      'saveVideoToGallery',
      {'sourcePath': result.localPath, 'fileName': result.fileName},
    );
    return saved?['uri'] as String? ?? saved?['path'] as String?;
  }

  Future<String?> importCompositionExportToLibrary({
    String category = '',
  }) async {
    final result = compositionExportResult;
    if (result == null) return null;
    if (!File(result.localPath).existsSync()) {
      compositionExportResult = null;
      compositionExportErrorMessage = '上次导出的文件已不存在，请重新导出。';
      notifyListeners();
      return null;
    }
    if (!isCurrentStorageConfigured) {
      throw StateError('请先在设置里填写完整的$currentStorageProviderLabel配置。');
    }
    final bytes = await File(result.localPath).readAsBytes();
    final pickedFile = PickedNativeFile.fromBytes(
      name: result.fileName,
      mimeType: 'video/mp4',
      bytes: bytes,
    );
    final uploadResult = await switch (settings.storageProvider) {
      StorageProvider.qiniu => _qiniuUploadService.upload(
        settings: settings,
        file: pickedFile,
      ),
      StorageProvider.bitifulS4 => _bitifulUploadService.upload(
        settings: settings,
        file: pickedFile,
      ),
    };
    return insertUploadedAttachment(
      uploadResult,
      labelOverride: result.fileName,
      roleOverride: AttachmentRole.referenceVideo,
      categoryOverride: category,
    );
  }

  Future<String?> saveAttachmentImageToGallery(String attachmentId) async {
    final attachment = library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
    if (attachment == null || attachment.kind != AttachmentKind.image) {
      return null;
    }
    final url = await resolveAttachmentPreviewUrl(attachment);
    if (url.trim().isEmpty) {
      throw const ApiClientException('当前图片没有可下载地址。');
    }
    final fileName = _lastPathSegment(url) ?? attachment.fileName;
    final tempFile = await downloadRemoteImageToTemp(url, fileName);
    final saved = await _mediaChannel
        .invokeMapMethod<String, Object?>('saveImageToGallery', {
          'sourcePath': tempFile.path,
          'fileName': fileName,
          'mimeType': _mimeTypeForImageFileName(fileName),
        });
    return saved?['uri'] as String? ?? saved?['path'] as String?;
  }

  Attachment? attachmentById(String? attachmentId) {
    if (attachmentId == null || attachmentId.trim().isEmpty) {
      return null;
    }
    return library.cast<Attachment?>().firstWhere(
      (item) => item?.id == attachmentId,
      orElse: () => null,
    );
  }

  Future<PickedLocalMediaFile?> pickLocalVideoSource() {
    return _filePicker.pickSingleVideoFile();
  }

  void rememberVideoFrameSource(VideoFrameSource source) {
    final normalizedUri = source.sourceUri.trim();
    if (normalizedUri.isEmpty) return;
    final entry = RecentVideoSource(
      type: source.type,
      label: source.label,
      sourceUri: normalizedUri,
      lastUsedAt: DateTime.now(),
      attachmentId: source.attachmentId,
      taskId: source.taskId,
      fileName: source.fileName,
    );
    final existingIndex = recentVideoSources.indexWhere(
      (item) =>
          item.type == source.type &&
          item.attachmentId == source.attachmentId &&
          item.taskId == source.taskId &&
          item.sourceUri == normalizedUri,
    );
    if (existingIndex >= 0) {
      recentVideoSources[existingIndex] = entry;
    } else {
      recentVideoSources.insert(0, entry);
    }
    if (recentVideoSources.length > 20) {
      recentVideoSources.removeRange(20, recentVideoSources.length);
    }
    notifyListeners();
  }

  Future<bool> ensureTaskVideoLocal(String taskId) {
    return downloadTaskResult(taskId);
  }

  Future<bool> addAttachmentVideoToComposition(String attachmentId) async {
    final attachment = attachmentById(attachmentId);
    if (attachment == null || attachment.kind != AttachmentKind.video) {
      return false;
    }
    final localized = await ensureAttachmentVideoLocal(attachmentId);
    if (!localized) return false;

    final refreshed = attachmentById(attachmentId);
    final localUri = refreshed?.localResourceUri?.trim() ?? '';
    if (refreshed == null || localUri.isEmpty) return false;

    compositionProject = compositionProject.copyWith(
      clips: [
        ...compositionProject.clips,
        CompositionClip(
          id: _newCompositionClipId(),
          sourceType: CompositionSourceType.attachment,
          sourceId: attachmentId,
          sourceUri: localUri,
          label: refreshed.label.isNotEmpty
              ? refreshed.label
              : attachment.label,
          fileName: refreshed.localFileName ?? attachment.fileName,
          startMs: 0,
          endMs: 15000,
        ),
      ],
    );
    compositionExportErrorMessage = null;
    currentTab = AppTab.composition;
    notifyListeners();
    return true;
  }

  Future<bool> addTaskVideoToComposition(String taskId) async {
    final task = tasks.cast<TaskRecord?>().firstWhere(
      (item) => item?.id == taskId,
      orElse: () => null,
    );
    if (task == null || task.kind != TaskKind.video) return false;

    if (task.localResourceUri?.trim().isEmpty ?? true) {
      final localized = await ensureTaskVideoLocal(taskId);
      if (!localized) return false;
    }

    final refreshed = tasks.cast<TaskRecord?>().firstWhere(
      (item) => item?.id == taskId,
      orElse: () => null,
    );
    final localUri = refreshed?.localResourceUri?.trim() ?? '';
    if (refreshed == null || localUri.isEmpty) return false;

    compositionProject = compositionProject.copyWith(
      clips: [
        ...compositionProject.clips,
        CompositionClip(
          id: _newCompositionClipId(),
          sourceType: CompositionSourceType.task,
          sourceId: taskId,
          sourceUri: localUri,
          label: refreshed.localFileName ?? '任务视频',
          fileName: refreshed.localFileName ?? 'task-video.mp4',
          startMs: 0,
          endMs: 15000,
        ),
      ],
    );
    compositionExportErrorMessage = null;
    currentTab = AppTab.composition;
    notifyListeners();
    return true;
  }

  Future<bool> ensureAttachmentVideoLocal(String attachmentId) async {
    final index = library.indexWhere((item) => item.id == attachmentId);
    if (index == -1) return false;
    final attachment = library[index];
    if (attachment.kind != AttachmentKind.video) {
      return false;
    }
    if (attachment.localStatus == AttachmentLocalStatus.ready &&
        (attachment.localResourceUri?.trim().isNotEmpty ?? false)) {
      return true;
    }

    final remoteUrl = await resolveAttachmentPreviewUrl(attachment);
    if (remoteUrl.trim().isEmpty) {
      library[index] = attachment.copyWith(
        localStatus: AttachmentLocalStatus.error,
        localDownloadProgress: 0,
        localErrorMessage: '当前素材没有可下载的视频地址。',
        localUpdatedAt: DateTime.now(),
      );
      notifyListeners();
      return false;
    }

    library[index] = attachment.copyWith(
      localStatus: AttachmentLocalStatus.downloading,
      localDownloadProgress: 0,
      localUpdatedAt: DateTime.now(),
      clearLocalErrorMessage: true,
    );
    notifyListeners();

    try {
      final fileName = _lastPathSegment(remoteUrl) ?? attachment.fileName;
      final tempFile = await downloadRemoteVideoToTemp(
        remoteUrl,
        fileName,
        onProgress: (progress) {
          final latestIndex = library.indexWhere(
            (item) => item.id == attachmentId,
          );
          if (latestIndex == -1) return;
          library[latestIndex] = library[latestIndex].copyWith(
            localStatus: AttachmentLocalStatus.downloading,
            localDownloadProgress: progress,
            localUpdatedAt: DateTime.now(),
          );
          notifyListeners();
        },
      );
      final saved = await saveVideoToLocalLibrary(tempFile.path, fileName);
      final latestIndex = library.indexWhere((item) => item.id == attachmentId);
      if (latestIndex == -1) return false;
      library[latestIndex] = library[latestIndex].copyWith(
        localStatus: AttachmentLocalStatus.ready,
        localDownloadProgress: 100,
        localFileName: saved?['path'] as String? ?? fileName,
        localResourceUri: saved?['uri'] as String? ?? tempFile.path,
        localUpdatedAt: DateTime.now(),
        clearLocalErrorMessage: true,
      );
      notifyListeners();
      return true;
    } on Exception catch (error) {
      final latestIndex = library.indexWhere((item) => item.id == attachmentId);
      if (latestIndex == -1) return false;
      library[latestIndex] = library[latestIndex].copyWith(
        localStatus: AttachmentLocalStatus.error,
        localDownloadProgress: 0,
        localErrorMessage: _cleanError(error),
        localUpdatedAt: DateTime.now(),
      );
      notifyListeners();
      return false;
    }
  }

  Future<File> downloadRemoteVideoToTemp(
    String url,
    String fileName, {
    void Function(int progress)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败（HTTP \${response.statusCode}）', uri: uri);
      }
      final tempFile = File('${Directory.systemTemp.path}/$fileName');
      final sink = tempFile.openWrite();
      try {
        final total = response.contentLength;
        var downloaded = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (total > 0 && onProgress != null) {
            onProgress(((downloaded / total) * 100).round().clamp(0, 100));
          }
        }
      } finally {
        await sink.close();
      }
      return tempFile;
    } finally {
      client.close(force: false);
    }
  }

  Future<Map<String, Object?>?> saveVideoToLocalLibrary(
    String sourcePath,
    String fileName,
  ) {
    return _mediaChannel.invokeMapMethod<String, Object?>(
      'saveVideoToGallery',
      {'sourcePath': sourcePath, 'fileName': fileName},
    );
  }

  Future<String?> saveCapturedFrameToGallery(CapturedFrameResult frame) async {
    final fileName = frame.path.split('/').last;
    final saved = await _mediaChannel
        .invokeMapMethod<String, Object?>('saveImageToGallery', {
          'sourcePath': frame.path,
          'fileName': fileName,
          'mimeType': _mimeTypeForImageFileName(fileName),
        });
    return saved?['uri'] as String? ?? saved?['path'] as String?;
  }

  Future<CapturedFrameResult> captureVideoFrame({
    required String sourceUri,
    required int positionMs,
    String? suggestedFileName,
  }) {
    return _videoFrameService.captureFrame(
      source: sourceUri,
      positionMs: positionMs,
      suggestedFileName: suggestedFileName,
    );
  }

  Future<String> importCapturedFrameToLibrary(
    CapturedFrameResult frame, {
    required String label,
    required String category,
    AttachmentRole role = AttachmentRole.referenceImage,
  }) async {
    if (!isCurrentStorageConfigured) {
      throw StateError('请先在设置里填写完整的$currentStorageProviderLabel配置。');
    }
    final file = File(frame.path);
    final bytes = await file.readAsBytes();
    final fileName = frame.path.split('/').last;
    final pickedFile = PickedNativeFile.fromBytes(
      name: fileName,
      mimeType: _mimeTypeForImageFileName(fileName),
      bytes: bytes,
    );

    final result = await switch (settings.storageProvider) {
      StorageProvider.qiniu => _qiniuUploadService.upload(
        settings: settings,
        file: pickedFile,
      ),
      StorageProvider.bitifulS4 => _bitifulUploadService.upload(
        settings: settings,
        file: pickedFile,
      ),
    };

    return insertUploadedAttachment(
      result,
      labelOverride: label,
      roleOverride: role,
      categoryOverride: category,
    );
  }

  Future<String> insertUploadedAttachment(
    StorageUploadResult result, {
    String? labelOverride,
    AttachmentRole? roleOverride,
    String? categoryOverride,
    String? sourceTaskId,
  }) async {
    final now = DateTime.now();
    final id = 'asset-${now.microsecondsSinceEpoch}-${library.length}';
    library.insert(
      0,
      Attachment(
        id: id,
        label: labelOverride ?? result.fileName,
        role: roleOverride ?? result.role,
        kind: result.kind,
        fileName: result.fileName,
        category: categoryOverride ?? result.category,
        createdAt: now,
        status: AttachmentStatus.uploaded,
        url: result.url,
        storageProvider: settings.storageProvider,
        objectKey: result.objectKey,
        storageBucket: result.storageBucket,
        storageEndpoint: result.storageEndpoint,
        storageRegion: result.storageRegion,
        storageDomain: result.storageDomain,
        fileSizeBytes: result.fileSizeBytes,
        sourceTaskId: sourceTaskId,
      ),
    );
    notifyListeners();
    return id;
  }

  Future<bool> retryFailedImageTransfers(String taskId) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;
    final task = tasks[index];
    if (task.kind != TaskKind.image) return false;

    final updatedResults = task.imageResults.map((item) {
      if (item.status == ImageResultStatus.downloadFailed ||
          item.status == ImageResultStatus.uploadFailed) {
        return item.copyWith(
          status: item.remoteUrl != null
              ? ImageResultStatus.readyToTransfer
              : ImageResultStatus.queued,
          clearLastError: true,
          updatedAt: DateTime.now(),
        );
      }
      return item;
    }).toList();

    tasks[index] = task.copyWith(
      imageResults: updatedResults,
      statusDetail: '正在重试失败项...',
      updatedAt: DateTime.now(),
    );
    notifyListeners();

    unawaited(_transferImageResults(taskId));
    return true;
  }

  Future<bool> retryImageResultDownload(String taskId, String resultId) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;
    final task = tasks[index];
    final resultIndex = task.imageResults.indexWhere((r) => r.id == resultId);
    if (resultIndex == -1) return false;

    final item = task.imageResults[resultIndex];
    if (item.remoteUrl == null) return false;

    tasks[index] = task.copyWith(
      imageResults: _updateImageResult(
        task.imageResults,
        resultIndex,
        item.copyWith(
          status: ImageResultStatus.readyToTransfer,
          clearLastError: true,
        ),
      ),
    );
    notifyListeners();
    unawaited(_transferImageResults(taskId));
    return true;
  }

  Future<bool> retryImageResultUpload(String taskId, String resultId) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;
    final task = tasks[index];
    final resultIndex = task.imageResults.indexWhere((r) => r.id == resultId);
    if (resultIndex == -1) return false;

    final item = task.imageResults[resultIndex];
    if (item.localTempPath == null) return false;

    tasks[index] = task.copyWith(
      imageResults: _updateImageResult(
        task.imageResults,
        resultIndex,
        item.copyWith(
          status: ImageResultStatus.readyToTransfer,
          clearLastError: true,
        ),
      ),
    );
    notifyListeners();
    unawaited(_transferImageResults(taskId));
    return true;
  }

  void updateAttachmentLabel(String attachmentId, String label) {
    final index = library.indexWhere((item) => item.id == attachmentId);
    if (index == -1) return;
    final normalized = label.trim();
    if (normalized.isEmpty) return;
    final previous = library[index];
    library[index] = previous.copyWith(label: normalized);
    prompt = prompt.replaceAll(
      mentionTokenForAttachment(previous),
      mentionTokenForAttachment(library[index]),
    );
    _syncSelectedAttachmentsFromPrompt();
    notifyListeners();
  }

  void _syncSelectedAttachmentsFromPrompt() {
    if (!supportsPromptMentions) {
      selectedAttachmentIds.clear();
      return;
    }

    final orderedIds = <String>[];
    final seenIds = <String>{};

    for (final match in promptTokenPattern.allMatches(prompt)) {
      final token = match.group(0);
      if (token == null) continue;
      final attachment = library.cast<Attachment?>().firstWhere(
        (item) => item != null && mentionTokenForAttachment(item) == token,
        orElse: () => null,
      );
      if (attachment == null || seenIds.contains(attachment.id)) {
        continue;
      }
      seenIds.add(attachment.id);
      orderedIds.add(attachment.id);
    }

    selectedAttachmentIds
      ..clear()
      ..addAll(orderedIds);
  }

  Future<int> pickAndUploadFiles() async {
    uploadErrorMessage = null;
    if (!isCurrentStorageConfigured) {
      uploadErrorMessage = '请先在设置里填写完整的$currentStorageProviderLabel配置。';
      notifyListeners();
      return 0;
    }

    List<PickedNativeFile> files;
    try {
      files = await _filePicker.pickMediaFiles();
    } on Exception catch (error) {
      uploadErrorMessage = _cleanError(error);
      notifyListeners();
      return 0;
    }
    if (files.isEmpty) {
      return 0;
    }

    var successCount = 0;
    for (final file in files) {
      final now = DateTime.now();
      final id =
          'asset-${now.microsecondsSinceEpoch}-${successCount + library.length}';
      library.insert(
        0,
        Attachment(
          id: id,
          label: file.name,
          role: AttachmentRole.referenceImage,
          kind: AttachmentKind.image,
          fileName: file.name,
          category: categories.isEmpty ? '' : categories.first,
          createdAt: now,
          status: AttachmentStatus.uploading,
          url: '',
        ),
      );
      notifyListeners();

      try {
        final result = await switch (settings.storageProvider) {
          StorageProvider.qiniu => _qiniuUploadService.upload(
            settings: settings,
            file: file,
          ),
          StorageProvider.bitifulS4 => _bitifulUploadService.upload(
            settings: settings,
            file: file,
          ),
        };
        final latestIndex = library.indexWhere((item) => item.id == id);
        if (latestIndex != -1) {
          library[latestIndex] = library[latestIndex].copyWith(
            label: result.fileName,
            role: result.role,
            kind: result.kind,
            fileName: result.fileName,
            category: result.category,
            status: AttachmentStatus.uploaded,
            url: result.url,
            storageProvider: settings.storageProvider,
            objectKey: result.objectKey,
            storageBucket: result.storageBucket,
            storageEndpoint: result.storageEndpoint,
            storageRegion: result.storageRegion,
            fileSizeBytes: result.fileSizeBytes,
          );
        }
        successCount++;
      } on Exception catch (error) {
        uploadErrorMessage = _cleanError(error);
        final latestIndex = library.indexWhere((item) => item.id == id);
        if (latestIndex != -1) {
          library[latestIndex] = library[latestIndex].copyWith(
            status: AttachmentStatus.error,
            url: '',
          );
        }
      }
      notifyListeners();
    }

    return successCount;
  }

  Future<bool> testAgentEarthConfig() async {
    if (!settings.agentEarthApiKey.trim().startsWith('sk-')) {
      configStatusMessage = 'AgentEarth 配置不完整，请检查 API Key。';
      notifyListeners();
      return false;
    }

    isTestingAgentEarth = true;
    configStatusMessage = '正在测试 AgentEarth 工具解析...';
    toolResolutions[activeMode] = ToolResolution(
      status: ToolResolutionStatus.idle,
      tool: fallbackToolForMode(
        activeMode,
        baseUrl: settings.agentEarthBaseUrl,
      ),
    );
    notifyListeners();

    try {
      final tool = await _seedanceService.resolveTool(
        settings.agentEarthApiKey,
        activeMode,
        baseUrl: settings.agentEarthBaseUrl,
      );
      toolResolutions[activeMode] = ToolResolution(
        status: ToolResolutionStatus.ready,
        tool: tool,
      );
      configStatusMessage =
          'AgentEarth 工具解析成功：当前模式使用 ${tool.toolName}，${tool.credit} credits。';
      isTestingAgentEarth = false;
      notifyListeners();
      return true;
    } on Exception catch (error) {
      toolResolutions[activeMode] = ToolResolution(
        status: ToolResolutionStatus.error,
        tool: fallbackToolForMode(
          activeMode,
          baseUrl: settings.agentEarthBaseUrl,
        ),
        errorMessage: _cleanError(error),
      );
      configStatusMessage = 'AgentEarth 配置测试失败：${_cleanError(error)}';
      isTestingAgentEarth = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> fetchBucketList() async {
    if (settings.storageProvider != StorageProvider.qiniu) {
      configStatusMessage = '当前存储提供商不支持自动拉取 Bucket 列表。';
      notifyListeners();
      return false;
    }
    if (settings.qiniuAccessKey.trim().isEmpty ||
        settings.qiniuSecretKey.trim().isEmpty) {
      configStatusMessage = '请先填写七牛 AK 和 SK。';
      notifyListeners();
      return false;
    }

    isFetchingBuckets = true;
    configStatusMessage = '正在拉取 Bucket 列表...';
    notifyListeners();
    try {
      final items = await _qiniuUploadService.fetchBuckets(settings);
      bucketOptions
        ..clear()
        ..addAll(items);
      if (settings.qiniuBucket.isEmpty && items.isNotEmpty) {
        settings = settings.copyWith(qiniuBucket: items.first);
      }
      configStatusMessage = items.isEmpty
          ? '当前账号下没有可用 Bucket。'
          : 'Bucket 列表已刷新。';
      isFetchingBuckets = false;
      notifyListeners();
      if (settings.qiniuBucket.isNotEmpty) {
        await fetchDomainList();
      }
      return true;
    } on Exception catch (error) {
      configStatusMessage = 'Bucket 拉取失败：${_cleanError(error)}';
      isFetchingBuckets = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> fetchDomainList() async {
    if (settings.storageProvider != StorageProvider.qiniu) {
      configStatusMessage = '当前存储提供商不支持自动拉取域名列表。';
      notifyListeners();
      return false;
    }
    if (settings.qiniuAccessKey.trim().isEmpty ||
        settings.qiniuSecretKey.trim().isEmpty ||
        settings.qiniuBucket.trim().isEmpty) {
      configStatusMessage = '请先填写七牛 AK、SK 并选择 Bucket。';
      notifyListeners();
      return false;
    }

    isFetchingDomains = true;
    configStatusMessage = '正在拉取 ${settings.qiniuBucket} 绑定的域名...';
    notifyListeners();
    try {
      final items = await _qiniuUploadService.fetchBucketDomains(
        settings,
        settings.qiniuBucket,
      );
      domainOptions
        ..clear()
        ..addAll(items);
      if (!items.contains(settings.qiniuDomain)) {
        settings = settings.copyWith(
          qiniuDomain: items.isEmpty ? '' : items.first,
        );
      }
      // 顺便查询当前 bucket 是否为私有空间，预览/下载链接需要据此签名。
      await _refreshQiniuBucketPrivate();
      configStatusMessage = items.isEmpty ? '当前 Bucket 还没有绑定可用域名。' : '域名列表已刷新。';
      isFetchingDomains = false;
      notifyListeners();
      return true;
    } on Exception catch (error) {
      configStatusMessage = '域名拉取失败：${_cleanError(error)}';
      isFetchingDomains = false;
      notifyListeners();
      return false;
    }
  }

  /// 查询当前 bucket 的私有属性并缓存到 qiniuBucketPrivate。
  /// 查询失败不阻断流程，置 null 表示未知，预览时按公开空间处理。
  Future<void> _refreshQiniuBucketPrivate() async {
    qiniuBucketPrivate = await _ensureQiniuBucketPrivate(settings.qiniuBucket);
  }

  Future<bool?> _ensureQiniuBucketPrivate(String? bucket) {
    final normalizedBucket = bucket?.trim() ?? '';
    if (normalizedBucket.isEmpty ||
        settings.qiniuAccessKey.trim().isEmpty ||
        settings.qiniuSecretKey.trim().isEmpty) {
      return Future.value(null);
    }
    final cached = _qiniuBucketPrivateByBucket[normalizedBucket];
    if (cached != null) return Future.value(cached);
    final existing = _qiniuBucketPrivateRefreshes[normalizedBucket];
    if (existing != null) return existing;
    final future = _fetchQiniuBucketPrivate(normalizedBucket);
    _qiniuBucketPrivateRefreshes[normalizedBucket] = future;
    return future.whenComplete(
      () => _qiniuBucketPrivateRefreshes.remove(normalizedBucket),
    );
  }

  Future<bool?> _fetchQiniuBucketPrivate(String bucket) async {
    try {
      final isPrivate = await _qiniuUploadService.fetchBucketPrivate(
        settings.copyWith(qiniuBucket: bucket),
      );
      _qiniuBucketPrivateByBucket[bucket] = isPrivate;
      if (bucket == settings.qiniuBucket.trim()) {
        qiniuBucketPrivate = isPrivate;
      }
      notifyListeners();
      return isPrivate;
    } on Exception {
      if (bucket == settings.qiniuBucket.trim()) {
        qiniuBucketPrivate = null;
      }
      return null;
    }
  }

  Future<bool> testQiniuConfig() async {
    if (!isQiniuConfigured) {
      configStatusMessage = '七牛配置不完整，请检查 AK、SK、Bucket 和域名。';
      notifyListeners();
      return false;
    }

    isTestingQiniu = true;
    configStatusMessage = '正在测试七牛配置...';
    notifyListeners();
    try {
      final items = await _qiniuUploadService.fetchBucketDomains(
        settings,
        settings.qiniuBucket,
      );
      domainOptions
        ..clear()
        ..addAll(items);
      await _refreshQiniuBucketPrivate();
      configStatusMessage = items.isEmpty
          ? '七牛配置测试通过，但当前 Bucket 没有返回域名。'
          : '七牛配置测试通过，域名列表可正常访问。';
      isTestingQiniu = false;
      notifyListeners();
      return true;
    } on Exception catch (error) {
      configStatusMessage = '七牛配置测试失败：${_cleanError(error)}';
      isTestingQiniu = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> testBitifulConfig() async {
    if (!isBitifulConfigured) {
      configStatusMessage =
          '缤纷云（Bitiful）S4 配置不完整，请检查 AccessKey、SecretKey、Bucket、Endpoint 和 Region。';
      notifyListeners();
      return false;
    }

    isTestingBitiful = true;
    configStatusMessage = '正在测试缤纷云（Bitiful）S4 配置...';
    notifyListeners();
    try {
      await _bitifulUploadService.testConfig(settings);
      configStatusMessage = '缤纷云（Bitiful）S4 配置测试通过，Bucket 可正常访问。';
      isTestingBitiful = false;
      notifyListeners();
      return true;
    } on Exception catch (error) {
      configStatusMessage = '缤纷云（Bitiful）S4 配置测试失败：${_cleanError(error)}';
      isTestingBitiful = false;
      notifyListeners();
      return false;
    }
  }

  Future<String?> exportBackup() {
    final fileName =
        'mova-backup-${DateTime.now().millisecondsSinceEpoch}.json';
    return _storage.exportState(
      jsonEncode(_toJson()),
      suggestedFileName: fileName,
    );
  }

  Future<bool> importBackup() async {
    try {
      final raw = await _storage.importState();
      if (raw == null || raw.trim().isEmpty) {
        configStatusMessage = '已取消导入';
        notifyListeners();
        return false;
      }
      _restoreFromJson(jsonDecode(raw));
      _syncSelectedAttachmentsFromPrompt();
      configStatusMessage = '备份已导入';
      notifyListeners();
      _startAutoPollingIfNeeded();
      return true;
    } on Exception catch (error) {
      configStatusMessage = '导入失败：${_cleanError(error)}';
      notifyListeners();
      return false;
    }
  }

  void _initializeToolResolutions() {
    for (final mode in ModeId.values) {
      toolResolutions[mode] = ToolResolution(
        status: ToolResolutionStatus.idle,
        tool: fallbackToolForMode(mode, baseUrl: settings.agentEarthBaseUrl),
      );
    }
  }

  void _applyAutoPollSetting(bool enabled) {
    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      final active =
          task.status == TaskStatus.submitted ||
          task.status == TaskStatus.inProgress;
      if (!active) continue;
      if (enabled && task.pollingStatus != PollingStatus.polling) {
        tasks[index] = task.copyWith(
          pollingStatus: PollingStatus.polling,
          statusDetail: '已开启自动轮询',
          updatedAt: DateTime.now(),
        );
      }
      if (!enabled && task.pollingStatus == PollingStatus.polling) {
        tasks[index] = task.copyWith(
          pollingStatus: PollingStatus.paused,
          statusDetail: '已关闭自动轮询',
          updatedAt: DateTime.now(),
        );
      }
    }
    if (enabled) {
      _startAutoPollingIfNeeded();
    } else {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  TaskRecord _appendPollLog(TaskRecord task, TaskPollLog log) {
    return task.copyWith(pollLogs: [log, ...task.pollLogs].take(10).toList());
  }

  String? _pollUrlForTask(TaskRecord task) {
    if (task.statusUrl?.trim().isNotEmpty == true) {
      return task.statusUrl;
    }
    final recoveredStatusUrl = _extractStatusUrl(task.responsePreview);
    if (recoveredStatusUrl != null) {
      return recoveredStatusUrl;
    }
    final derivedStatusUrl = _deriveStatusUrl(task.responseUrl);
    return derivedStatusUrl ?? task.responseUrl;
  }

  String? _extractStatusUrl(String value) {
    final normalized = value.replaceAll(r'\/', '/');
    final match = RegExp(
      r'https://queue\.fal\.run/[^"\\\s]+/status',
    ).firstMatch(normalized);
    return match?.group(0);
  }

  List<String> _extractImageUrlsFromPreview(String value) {
    final matches = RegExp(
      r'https://[^\s"\\]+(?:\.png|\.jpg|\.jpeg|\.webp)(?:\?[^\s"\\]*)?',
      caseSensitive: false,
    ).allMatches(value);
    final urls = <String>[];
    final seen = <String>{};
    for (final match in matches) {
      final raw = match.group(0);
      if (raw == null) continue;
      final normalized = raw.replaceAll(r'\/', '/').trim();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      urls.add(normalized);
    }
    return urls;
  }

  String? _deriveStatusUrl(String? responseUrl) {
    if (responseUrl == null || responseUrl.trim().isEmpty) return null;
    final value = responseUrl.trim();
    if (!value.startsWith('https://queue.fal.run/')) return null;
    if (value.endsWith('/status')) return value;
    return '${value.replaceAll(RegExp(r'/+$'), '')}/status';
  }

  void _startAutoPollingIfNeeded() {
    if (!isAgentEarthConfigured || !_hasPollingTasks || !_appInForeground) {
      return;
    }
    _pollingTimer ??= Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_pollActiveTasks());
    });
  }

  void _stopAutoPollingIfIdle() {
    if (_hasPollingTasks) return;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  bool get _hasPollingTasks => tasks.any(
    (task) =>
        !task.isArchived &&
        task.pollingStatus == PollingStatus.polling &&
        (task.status == TaskStatus.submitted ||
            task.status == TaskStatus.inProgress),
  );

  Future<void> _pollActiveTasks() async {
    if (!isAgentEarthConfigured) return;
    final pollingTasks = tasks
        .where(
          (task) =>
              task.pollingStatus == PollingStatus.polling &&
              !task.isArchived &&
              (task.status == TaskStatus.submitted ||
                  task.status == TaskStatus.inProgress) &&
              !_refreshingTaskIds.contains(task.id),
        )
        .toList();
    for (final task in pollingTasks) {
      if (task.kind == TaskKind.image) {
        await refreshImageTask(task.id);
      } else {
        await refreshTask(task.id);
      }
    }
  }

  void _resumePollingAfterLifecycle() {
    if (!isAgentEarthConfigured) return;
    if (!_hasPollingTasks) {
      _stopAutoPollingIfIdle();
      return;
    }
    _pollingTimer?.cancel();
    _pollingTimer = null;
    unawaited(_pollActiveTasks());
    _startAutoPollingIfNeeded();
  }

  String _cleanError(Object error) {
    final message = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('ApiClientException: ', '');
    if (message.contains('InvalidAccessKeyId')) {
      return '存储配置无效：Access Key 不存在或填写错误，请到设置页检查当前存储配置。';
    }
    if (message.contains('SignatureDoesNotMatch')) {
      return '存储配置无效：签名校验失败，请检查 Access Key、Secret Key 和区域配置。';
    }
    if (message.contains('AccessDenied')) {
      return '存储访问被拒绝，请检查当前存储账号权限和 Bucket 配置。';
    }
    if (message.contains('<Error>') && message.contains('<Code>')) {
      return '上传失败：当前存储配置不可用，请到设置页检查 Access Key、Secret Key、Bucket 和区域。';
    }
    return message;
  }

  String cleanErrorForDisplay(Object error) => _cleanError(error);

  bool _isTransientPollingError(Object error) {
    final message = _cleanError(error).toLowerCase();
    return message.contains('socketfailed host lookup') ||
        message.contains('failed host lookup') ||
        message.contains('no address associated with hostname') ||
        message.contains('connection closed before full header was received') ||
        message.contains('connection reset by peer') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('network is unreachable');
  }

  String _mimeTypeForImageFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String? _lastPathSegment(String url) {
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments == null || segments.isEmpty) return null;
    return segments.last.isEmpty ? null : segments.last;
  }

  void _schedulePersist() {
    if (!_persistenceLoaded) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        await _storage.writeState(jsonEncode(_toJson()));
      } catch (_) {
        // Keep persistence failure non-blocking; visible state should not roll back.
      }
    });
  }

  Map<String, Object?> _toJson() {
    return {
      'version': 4,
      'currentTab': currentTab.name,
      'activeMode': activeMode.name,
      'prompt': prompt,
      'imagePrompt': imagePrompt,
      'imageMetadata': _imageMetadataToJson(imageMetadata),
      'activeImageMode': activeImageMode.name,
      'selectedImageAttachmentIds': selectedImageAttachmentIds,
      'metadata': _metadataToJson(metadata),
      'settings': _settingsToJson(settings),
      'categories': categories,
      'library': library.map(_attachmentToJson).toList(),
      'recentVideoSources': recentVideoSources
          .map(_recentVideoSourceToJson)
          .toList(),
      'libraryViewMode': libraryViewMode.name,
      'libraryRecentFirst': libraryRecentFirst,
      'attachmentLastUsedAt': attachmentLastUsedAt,
      'selectedAttachmentIds': selectedAttachmentIds,
      'selectedFirstFrameAttachmentId': selectedFirstFrameAttachmentId,
      'selectedLastFrameAttachmentId': selectedLastFrameAttachmentId,
      'tasks': tasks.map(_taskToJson).toList(),
      'bucketOptions': bucketOptions,
      'domainOptions': domainOptions,
      'qiniuBucketPrivateByBucket': _qiniuBucketPrivateByBucket,
      'qiniuBucketPrivate': qiniuBucketPrivate,
      'activeTaskTab': activeTaskTab.name,
      'showArchivedTasks': showArchivedTasks,
      'compositionProject': _compositionProjectToJson(compositionProject),
      'compositionExportResult': compositionExportResult == null
          ? null
          : _compositionExportResultToJson(compositionExportResult!),
    };
  }

  void _restoreFromJson(Object? value) {
    if (value is! Map) return;
    final map = Map<String, Object?>.from(value);
    currentTab = _enumValue(AppTab.values, map['currentTab'], AppTab.create);
    activeMode = _enumValue(ModeId.values, map['activeMode'], ModeId.text);
    prompt = map['prompt'] is String ? map['prompt'] as String : initialPrompt;
    imagePrompt = _stringValue(map['imagePrompt'], initialPrompt);
    imageMetadata = _imageMetadataFromJson(map['imageMetadata']);
    activeImageMode = _enumValue(
      ImageCreateMode.values,
      map['activeImageMode'],
      ImageCreateMode.textToImage,
    );
    metadata = _metadataFromJson(map['metadata']);
    settings = _settingsFromJson(map['settings']);
    _initializeToolResolutions();
    libraryViewMode = _enumValue(
      LibraryViewMode.values,
      map['libraryViewMode'],
      LibraryViewMode.comfortable,
    );
    libraryRecentFirst = _boolValue(map['libraryRecentFirst'], true);
    categories
      ..clear()
      ..addAll(_stringListFromJson(map['categories']));
    if (categories.isEmpty) {
      categories.addAll(defaultCategories);
    }

    library
      ..clear()
      ..addAll(_listFromJson(map['library'], _attachmentFromJson));
    recentVideoSources
      ..clear()
      ..addAll(
        _listFromJson(map['recentVideoSources'], _recentVideoSourceFromJson),
      );
    for (final attachment in library) {
      final category = attachment.category.trim();
      if (category.isNotEmpty && !categories.contains(category)) {
        categories.add(category);
      }
    }
    attachmentLastUsedAt
      ..clear()
      ..addAll(_intMapFromJson(map['attachmentLastUsedAt']));
    selectedAttachmentIds
      ..clear()
      ..addAll(_stringListFromJson(map['selectedAttachmentIds']));
    selectedFirstFrameAttachmentId = _nullableStringValue(
      map['selectedFirstFrameAttachmentId'],
    );
    selectedLastFrameAttachmentId = _nullableStringValue(
      map['selectedLastFrameAttachmentId'],
    );
    selectedImageAttachmentIds
      ..clear()
      ..addAll(_stringListFromJson(map['selectedImageAttachmentIds']));
    tasks
      ..clear()
      ..addAll(_listFromJson(map['tasks'], _taskFromJson));
    bucketOptions
      ..clear()
      ..addAll(_stringListFromJson(map['bucketOptions']));
    domainOptions
      ..clear()
      ..addAll(_stringListFromJson(map['domainOptions']));
    _qiniuBucketPrivateByBucket
      ..clear()
      ..addAll(_boolMapFromJson(map['qiniuBucketPrivateByBucket']));
    qiniuBucketPrivate = _nullableBoolValue(map['qiniuBucketPrivate']);
    if (qiniuBucketPrivate != null && settings.qiniuBucket.trim().isNotEmpty) {
      _qiniuBucketPrivateByBucket[settings.qiniuBucket.trim()] =
          qiniuBucketPrivate!;
    }
    activeTaskTab = _enumValue(
      TaskTab.values,
      map['activeTaskTab'],
      TaskTab.video,
    );
    showArchivedTasks = _boolValue(map['showArchivedTasks'], false);
    compositionProject = _compositionProjectFromJson(map['compositionProject']);
    compositionExportStatus = CompositionExportStatus.idle;
    compositionExportProgress = 0;
    compositionExportStage = '';
    compositionExportErrorMessage = null;
    compositionExportResult = _compositionExportResultFromJson(
      map['compositionExportResult'],
    );
    // 上次导出的视频写在系统临时目录里，应用退出后可能被系统清理。
    // 若文件不存在，丢弃缓存的导出结果，避免下次进入剪辑页/保存到相册/
    // 导入素材库时读取空文件而抛异常。
    final cachedExport = compositionExportResult;
    if (cachedExport != null) {
      final localPath = cachedExport.localPath.trim();
      if (localPath.isEmpty || !File(localPath).existsSync()) {
        compositionExportResult = null;
      }
    }
    prompt = _normalizedVideoPromptForMode(prompt, activeMode);
  }

  Map<String, Object?> _metadataToJson(MetadataState value) => {
    'model': value.model,
    'duration': value.duration,
    'frames': value.frames,
    'resolution': value.resolution,
    'ratio': value.ratio,
    'seed': value.seed,
    'cameraFixed': value.cameraFixed,
    'watermark': value.watermark,
    'generateAudio': value.generateAudio,
    'returnLastFrame': value.returnLastFrame,
  };

  MetadataState _metadataFromJson(Object? value) {
    if (value is! Map) return metadataDefaults;
    final map = Map<String, Object?>.from(value);
    return MetadataState(
      model: _stringValue(map['model'], metadataDefaults.model),
      duration: _stringValue(map['duration'], metadataDefaults.duration),
      frames: _stringValue(map['frames'], metadataDefaults.frames),
      resolution: _stringValue(map['resolution'], metadataDefaults.resolution),
      ratio: _stringValue(map['ratio'], metadataDefaults.ratio),
      seed: _stringValue(map['seed'], metadataDefaults.seed),
      cameraFixed: _boolValue(map['cameraFixed'], metadataDefaults.cameraFixed),
      watermark: _boolValue(map['watermark'], metadataDefaults.watermark),
      generateAudio: _boolValue(
        map['generateAudio'],
        metadataDefaults.generateAudio,
      ),
      returnLastFrame: _boolValue(
        map['returnLastFrame'],
        metadataDefaults.returnLastFrame,
      ),
    );
  }

  Map<String, Object?> _settingsToJson(SettingsState value) => {
    'storageProvider': value.storageProvider.name,
    'agentEarthBaseUrl': value.agentEarthBaseUrl,
    'agentEarthApiKey': value.agentEarthApiKey,
    'qiniuAccessKey': value.qiniuAccessKey,
    'qiniuSecretKey': value.qiniuSecretKey,
    'qiniuBucket': value.qiniuBucket,
    'qiniuDomain': value.qiniuDomain,
    'bitifulAccessKey': value.bitifulAccessKey,
    'bitifulSecretKey': value.bitifulSecretKey,
    'bitifulBucket': value.bitifulBucket,
    'bitifulEndpoint': value.bitifulEndpoint,
    'bitifulRegion': value.bitifulRegion,
    'bitifulPublicDomain': value.bitifulPublicDomain,
    'autoPoll': value.autoPoll,
    'autoDownload': value.autoDownload,
    'imageAutoFallbackEnabled': value.imageAutoFallbackEnabled,
  };

  SettingsState _settingsFromJson(Object? value) {
    if (value is! Map) return settingsDefaults;
    final map = Map<String, Object?>.from(value);
    return SettingsState(
      storageProvider: _enumValue(
        StorageProvider.values,
        map['storageProvider'],
        settingsDefaults.storageProvider,
      ),
      agentEarthBaseUrl: _stringValue(
        map['agentEarthBaseUrl'],
        settingsDefaults.agentEarthBaseUrl,
      ),
      agentEarthApiKey: _stringValue(
        map['agentEarthApiKey'],
        settingsDefaults.agentEarthApiKey,
      ),
      qiniuAccessKey: _stringValue(
        map['qiniuAccessKey'],
        settingsDefaults.qiniuAccessKey,
      ),
      qiniuSecretKey: _stringValue(
        map['qiniuSecretKey'],
        settingsDefaults.qiniuSecretKey,
      ),
      qiniuBucket: _stringValue(
        map['qiniuBucket'],
        settingsDefaults.qiniuBucket,
      ),
      qiniuDomain: _stringValue(
        map['qiniuDomain'],
        settingsDefaults.qiniuDomain,
      ),
      bitifulAccessKey: _stringValue(
        map['bitifulAccessKey'],
        settingsDefaults.bitifulAccessKey,
      ),
      bitifulSecretKey: _stringValue(
        map['bitifulSecretKey'],
        settingsDefaults.bitifulSecretKey,
      ),
      bitifulBucket: _stringValue(
        map['bitifulBucket'],
        settingsDefaults.bitifulBucket,
      ),
      bitifulEndpoint: _stringValue(
        map['bitifulEndpoint'],
        settingsDefaults.bitifulEndpoint,
      ),
      bitifulRegion: _stringValue(
        map['bitifulRegion'],
        settingsDefaults.bitifulRegion,
      ),
      bitifulPublicDomain: _stringValue(
        map['bitifulPublicDomain'],
        settingsDefaults.bitifulPublicDomain,
      ),
      autoPoll: _boolValue(map['autoPoll'], settingsDefaults.autoPoll),
      autoDownload: _boolValue(
        map['autoDownload'],
        settingsDefaults.autoDownload,
      ),
      imageAutoFallbackEnabled: _boolValue(
        map['imageAutoFallbackEnabled'],
        false,
      ),
    );
  }

  String _defaultStorageConfigMessage({required StorageProvider provider}) {
    switch (provider) {
      case StorageProvider.qiniu:
        return '先填写七牛云配置，再测试连接或拉取资源。';
      case StorageProvider.bitifulS4:
        return '先填写缤纷云（Bitiful）S4 配置，再测试连接。';
    }
  }

  Future<List<Attachment>> _resolveAttachmentsForSeedance(
    List<Attachment> attachments,
  ) async {
    final resolved = <Attachment>[];
    for (final attachment in attachments) {
      resolved.add(
        attachment.copyWith(
          url: await _resolveAttachmentAccessUrl(
            attachment,
            purpose: _AttachmentAccessPurpose.seedance,
          ),
        ),
      );
    }
    return resolved;
  }

  Future<List<Attachment>> _resolveImageAttachmentsForGeneration(
    List<Attachment> attachments,
  ) async {
    final resolved = <Attachment>[];
    for (final attachment in attachments) {
      if (attachment.kind != AttachmentKind.image) continue;
      resolved.add(
        attachment.copyWith(
          url: await _resolveAttachmentAccessUrl(
            attachment,
            purpose: _AttachmentAccessPurpose.seedance,
          ),
        ),
      );
    }
    return resolved;
  }

  Future<String> _resolveAttachmentAccessUrl(
    Attachment attachment, {
    required _AttachmentAccessPurpose purpose,
  }) async {
    if (attachment.storageProvider == StorageProvider.qiniu) {
      final objectKey = attachment.objectKey?.trim();
      // 域名优先取素材上传时记录的 storageDomain，回退到当前全局配置。
      // 这样切换到其他空间后，旧素材仍用各自归属域名访问，不会全部失效。
      final resolvedDomain =
          (attachment.storageDomain?.trim().isNotEmpty == true
          ? attachment.storageDomain!.trim()
          : settings.qiniuDomain.trim());
      if (objectKey == null || objectKey.isEmpty || resolvedDomain.isEmpty) {
        return attachment.url;
      }
      final normalizedDomain = normalizePublicUrlBase(resolvedDomain);
      final bucket = attachment.storageBucket?.trim().isNotEmpty == true
          ? attachment.storageBucket!.trim()
          : settings.qiniuBucket.trim();
      final isPrivate = await _ensureQiniuBucketPrivate(bucket);
      // 公开空间直接拼域名 + key；私有空间需要带签名 token 才能访问。
      if (isPrivate != true) {
        return '$normalizedDomain/${encodeObjectKeyForUrl(objectKey)}';
      }
      final cacheKey = 'qiniu:${purpose.name}:${attachment.id}:$objectKey';
      final now = DateTime.now();
      final cached = _signedUrlCache[cacheKey];
      if (cached != null &&
          cached.expiresAt.isAfter(now.add(const Duration(minutes: 1)))) {
        return cached.url;
      }
      final expiresIn = switch (purpose) {
        _AttachmentAccessPurpose.preview => const Duration(hours: 1),
        _AttachmentAccessPurpose.share => const Duration(hours: 1),
        _AttachmentAccessPurpose.seedance => const Duration(hours: 24),
      };
      final url = _qiniuUploadService.createPrivateDownloadUrl(
        settings: settings,
        objectKey: objectKey,
        domain: normalizedDomain,
        expiresIn: expiresIn,
      );
      _signedUrlCache[cacheKey] = _SignedUrlCacheEntry(
        url: url,
        expiresAt: now.add(expiresIn),
      );
      return url;
    }
    if (attachment.storageProvider != StorageProvider.bitifulS4) {
      return attachment.url;
    }
    final objectKey = attachment.objectKey?.trim();
    if (objectKey == null || objectKey.isEmpty) {
      return attachment.url;
    }
    if (!isBitifulConfigured) {
      return attachment.url;
    }
    final cacheKey = '${purpose.name}:${attachment.id}:$objectKey';
    final now = DateTime.now();
    final cached = _signedUrlCache[cacheKey];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(minutes: 1)))) {
      return cached.url;
    }
    final expiresIn = switch (purpose) {
      _AttachmentAccessPurpose.preview => const Duration(hours: 1),
      _AttachmentAccessPurpose.share => const Duration(hours: 1),
      _AttachmentAccessPurpose.seedance => const Duration(hours: 24),
    };
    final url = _bitifulUploadService.createPresignedGetUrl(
      settings: settings,
      objectKey: objectKey,
      bucket: attachment.storageBucket,
      endpoint: attachment.storageEndpoint,
      region: attachment.storageRegion,
      expiresIn: expiresIn,
    );
    _signedUrlCache[cacheKey] = _SignedUrlCacheEntry(
      url: url,
      expiresAt: now.add(expiresIn),
    );
    return url;
  }

  Map<String, Object?> _attachmentToJson(Attachment value) => {
    'id': value.id,
    'label': value.label,
    'role': value.role.name,
    'kind': value.kind.name,
    'fileName': value.fileName,
    'category': value.category,
    'createdAt': value.createdAt.toIso8601String(),
    'status': value.status.name,
    'url': value.url,
    'localStatus': value.localStatus.name,
    'localDownloadProgress': value.localDownloadProgress,
    'localResourceUri': value.localResourceUri,
    'localFileName': value.localFileName,
    'localUpdatedAt': value.localUpdatedAt?.toIso8601String(),
    'localErrorMessage': value.localErrorMessage,
    'storageProvider': value.storageProvider.name,
    'objectKey': value.objectKey,
    'storageBucket': value.storageBucket,
    'storageEndpoint': value.storageEndpoint,
    'storageRegion': value.storageRegion,
    'storageDomain': value.storageDomain,
    'fileSizeBytes': value.fileSizeBytes,
    'sourceTaskId': value.sourceTaskId,
  };

  Map<String, Object?> _recentVideoSourceToJson(RecentVideoSource value) => {
    'type': value.type.name,
    'label': value.label,
    'sourceUri': value.sourceUri,
    'lastUsedAt': value.lastUsedAt.toIso8601String(),
    'attachmentId': value.attachmentId,
    'taskId': value.taskId,
    'fileName': value.fileName,
  };

  Attachment _attachmentFromJson(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
    return Attachment(
      id: _stringValue(
        map['id'],
        'asset-${DateTime.now().microsecondsSinceEpoch}',
      ),
      label: _stringValue(map['label'], '未命名素材'),
      role: _enumValue(
        AttachmentRole.values,
        map['role'],
        AttachmentRole.referenceImage,
      ),
      kind: _enumValue(
        AttachmentKind.values,
        map['kind'],
        AttachmentKind.image,
      ),
      fileName: _stringValue(map['fileName'], 'asset'),
      category: _stringValue(map['category'], ''),
      createdAt:
          DateTime.tryParse(_stringValue(map['createdAt'], '')) ??
          DateTime.now(),
      status: _enumValue(
        AttachmentStatus.values,
        map['status'],
        AttachmentStatus.uploaded,
      ),
      url: _stringValue(map['url'], ''),
      localStatus: _enumValue(
        AttachmentLocalStatus.values,
        map['localStatus'],
        AttachmentLocalStatus.none,
      ),
      localDownloadProgress: map['localDownloadProgress'] is num
          ? (map['localDownloadProgress'] as num).round().clamp(0, 100)
          : 0,
      localResourceUri: _nullableStringValue(map['localResourceUri']),
      localFileName: _nullableStringValue(map['localFileName']),
      localUpdatedAt: DateTime.tryParse(
        _stringValue(map['localUpdatedAt'], ''),
      ),
      localErrorMessage: _nullableStringValue(map['localErrorMessage']),
      storageProvider: _enumValue(
        StorageProvider.values,
        map['storageProvider'],
        StorageProvider.qiniu,
      ),
      objectKey: _nullableStringValue(map['objectKey']),
      storageBucket: _nullableStringValue(map['storageBucket']),
      storageEndpoint: _nullableStringValue(map['storageEndpoint']),
      storageRegion: _nullableStringValue(map['storageRegion']),
      storageDomain: _nullableStringValue(map['storageDomain']),
      fileSizeBytes: map['fileSizeBytes'] is num
          ? (map['fileSizeBytes'] as num).round()
          : null,
      sourceTaskId: _nullableStringValue(map['sourceTaskId']),
    );
  }

  RecentVideoSource _recentVideoSourceFromJson(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
    return RecentVideoSource(
      type: _enumValue(
        VideoFrameSourceType.values,
        map['type'],
        VideoFrameSourceType.localFile,
      ),
      label: _stringValue(map['label'], '最近使用视频'),
      sourceUri: _stringValue(map['sourceUri'], ''),
      lastUsedAt:
          DateTime.tryParse(_stringValue(map['lastUsedAt'], '')) ??
          DateTime.now(),
      attachmentId: _nullableStringValue(map['attachmentId']),
      taskId: _nullableStringValue(map['taskId']),
      fileName: _nullableStringValue(map['fileName']),
    );
  }

  Map<String, Object?> _compositionProjectToJson(
    VideoCompositionProject value,
  ) => {
    'clips': value.clips.map(_compositionClipToJson).toList(),
    'output': _compositionOutputToJson(value.output),
    'audio': _compositionAudioToJson(value.audio),
  };

  VideoCompositionProject _compositionProjectFromJson(Object? value) {
    if (value is! Map) return VideoCompositionProject.empty;
    final map = Map<String, Object?>.from(value);
    return VideoCompositionProject(
      clips: _listFromJson(map['clips'], _compositionClipFromJson),
      output: _compositionOutputFromJson(map['output']),
      audio: _compositionAudioFromJson(map['audio']),
    );
  }

  Map<String, Object?> _compositionClipToJson(CompositionClip value) => {
    'id': value.id,
    'label': value.label,
    'sourceType': value.sourceType.name,
    'sourceId': value.sourceId,
    'sourceUri': value.sourceUri,
    'fileName': value.fileName,
    'startMs': value.startMs,
    'endMs': value.endMs,
    'transitionType': value.transitionType.name,
    'transitionDurationMs': value.transitionDurationMs,
  };

  CompositionClip _compositionClipFromJson(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
    return CompositionClip(
      id: _stringValue(
        map['id'],
        'composition-clip-${DateTime.now().microsecondsSinceEpoch}',
      ),
      label: _stringValue(map['label'], '未命名片段'),
      sourceType: _enumValue(
        CompositionSourceType.values,
        map['sourceType'],
        CompositionSourceType.localFile,
      ),
      sourceUri: _stringValue(map['sourceUri'], ''),
      fileName: _stringValue(map['fileName'], ''),
      startMs: _intValue(map['startMs'], 0),
      endMs: _intValue(map['endMs'], 0),
      sourceId: _nullableStringValue(map['sourceId']),
      transitionType: _enumValue(
        CompositionTransitionType.values,
        map['transitionType'],
        CompositionTransitionType.none,
      ),
      transitionDurationMs: _intValue(map['transitionDurationMs'], 0),
    );
  }

  Map<String, Object?> _compositionOutputToJson(
    CompositionOutputSettings value,
  ) => {
    'resolution': value.resolution,
    'ratio': value.ratio,
    'fps': value.fps,
    'bitrateKbps': value.bitrateKbps,
    'fileName': value.fileName,
  };

  CompositionOutputSettings _compositionOutputFromJson(Object? value) {
    if (value is! Map) return CompositionOutputSettings.defaults;
    final map = Map<String, Object?>.from(value);
    return CompositionOutputSettings(
      resolution: _stringValue(
        map['resolution'],
        CompositionOutputSettings.defaults.resolution,
      ),
      ratio: _stringValue(
        map['ratio'],
        CompositionOutputSettings.defaults.ratio,
      ),
      fps: _intValue(map['fps'], CompositionOutputSettings.defaults.fps),
      bitrateKbps: _intValue(
        map['bitrateKbps'],
        CompositionOutputSettings.defaults.bitrateKbps,
      ),
      fileName: _stringValue(
        map['fileName'],
        CompositionOutputSettings.defaults.fileName,
      ),
    );
  }

  Map<String, Object?> _compositionAudioToJson(
    CompositionAudioSettings value,
  ) => {
    'mode': value.mode.name,
    'bgmSource': value.bgmSource == null
        ? null
        : _compositionBgmSourceToJson(value.bgmSource!),
    'originalVolume': value.originalVolume,
    'bgmVolume': value.bgmVolume,
  };

  CompositionAudioSettings _compositionAudioFromJson(Object? value) {
    if (value is! Map) return CompositionAudioSettings.defaults;
    final map = Map<String, Object?>.from(value);
    return CompositionAudioSettings(
      mode: _enumValue(
        CompositionAudioMode.values,
        map['mode'],
        CompositionAudioMode.keepOriginal,
      ),
      bgmSource: _compositionBgmSourceFromJson(map['bgmSource']),
      originalVolume: _doubleValue(
        map['originalVolume'],
        CompositionAudioSettings.defaults.originalVolume,
      ),
      bgmVolume: _doubleValue(
        map['bgmVolume'],
        CompositionAudioSettings.defaults.bgmVolume,
      ),
    );
  }

  Map<String, Object?> _compositionBgmSourceToJson(
    CompositionBgmSource value,
  ) => {
    'id': value.id,
    'label': value.label,
    'sourceType': value.sourceType.name,
    'sourceUri': value.sourceUri,
    'fileName': value.fileName,
  };

  CompositionBgmSource? _compositionBgmSourceFromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    return CompositionBgmSource(
      id: _stringValue(
        map['id'],
        'composition-bgm-${DateTime.now().microsecondsSinceEpoch}',
      ),
      label: _stringValue(map['label'], 'BGM'),
      sourceType: _enumValue(
        CompositionBgmSourceType.values,
        map['sourceType'],
        CompositionBgmSourceType.localFile,
      ),
      sourceUri: _stringValue(map['sourceUri'], ''),
      fileName: _stringValue(map['fileName'], ''),
    );
  }

  Map<String, Object?> _compositionExportResultToJson(
    CompositionExportResult value,
  ) => {
    'localPath': value.localPath,
    'fileName': value.fileName,
    'durationMs': value.durationMs,
    'width': value.width,
    'height': value.height,
  };

  CompositionExportResult? _compositionExportResultFromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    return CompositionExportResult(
      localPath: _stringValue(map['localPath'], ''),
      fileName: _stringValue(map['fileName'], ''),
      durationMs: _intValue(map['durationMs'], 0),
      width: _intValue(map['width'], 0),
      height: _intValue(map['height'], 0),
    );
  }

  Map<String, Object?> _taskToJson(TaskRecord value) => {
    'id': value.id,
    'mode': value.mode.name,
    'prompt': value.prompt,
    'status': value.status.name,
    'pollingStatus': value.pollingStatus.name,
    'downloadStatus': value.downloadStatus.name,
    'progress': value.progress,
    'downloadProgress': value.downloadProgress,
    'createdAt': value.createdAt.toIso8601String(),
    'videoUrl': value.videoUrl,
    'localFileName': value.localFileName,
    'localResourceUri': value.localResourceUri,
    'lastError': value.lastError,
    'statusDetail': value.statusDetail,
    'updatedAt': value.updatedAt.toIso8601String(),
    'estimatedCredit': value.estimatedCredit,
    'attachments': value.attachments.map(_attachmentToJson).toList(),
    'requestPreview': value.requestPreview,
    'responsePreview': value.responsePreview,
    'pollLogs': value.pollLogs.map(_pollLogToJson).toList(),
    'responseUrl': value.responseUrl,
    'statusUrl': value.statusUrl,
    'toolName': value.toolName,
    'hasAnomaly': value.hasAnomaly,
    'anomalyMessage': value.anomalyMessage,
    'kind': value.kind.name,
    'imageResults': value.imageResults.map(_imageResultToJson).toList(),
    'imageMetadata': value.imageMetadata != null
        ? _imageMetadataToJson(value.imageMetadata!)
        : null,
    'imageMode': value.imageMode?.name,
    'archivedAt': value.archivedAt?.toIso8601String(),
  };

  TaskRecord _taskFromJson(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
    return TaskRecord(
      id: _stringValue(
        map['id'],
        'task-${DateTime.now().microsecondsSinceEpoch}',
      ),
      mode: _enumValue(ModeId.values, map['mode'], ModeId.text),
      prompt: _stringValue(map['prompt'], ''),
      status: _enumValue(
        TaskStatus.values,
        map['status'],
        TaskStatus.submitted,
      ),
      pollingStatus: _enumValue(
        PollingStatus.values,
        map['pollingStatus'],
        PollingStatus.idle,
      ),
      downloadStatus: _enumValue(
        DownloadStatus.values,
        map['downloadStatus'],
        DownloadStatus.idle,
      ),
      progress: map['progress'] is num ? (map['progress'] as num).round() : 0,
      downloadProgress: map['downloadProgress'] is num
          ? (map['downloadProgress'] as num).round()
          : 0,
      createdAt:
          DateTime.tryParse(_stringValue(map['createdAt'], '')) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(_stringValue(map['updatedAt'], '')) ??
          DateTime.now(),
      estimatedCredit: map['estimatedCredit'] is num
          ? (map['estimatedCredit'] as num).round()
          : 0,
      attachments: _listFromJson(map['attachments'], _attachmentFromJson),
      requestPreview: _stringValue(map['requestPreview'], '{}'),
      responsePreview: _stringValue(map['responsePreview'], '{}'),
      pollLogs: _listFromJson(map['pollLogs'], _pollLogFromJson),
      videoUrl: map['videoUrl'] as String?,
      localFileName: map['localFileName'] as String?,
      localResourceUri: map['localResourceUri'] as String?,
      lastError: map['lastError'] as String?,
      statusDetail: map['statusDetail'] as String?,
      responseUrl: map['responseUrl'] as String?,
      statusUrl: map['statusUrl'] as String?,
      toolName: map['toolName'] as String?,
      hasAnomaly: _boolValue(map['hasAnomaly'], false),
      anomalyMessage: map['anomalyMessage'] as String?,
      kind: _enumValue(TaskKind.values, map['kind'], TaskKind.video),
      imageResults: _listFromJson(map['imageResults'], _imageResultFromJson),
      imageMetadata: map['imageMetadata'] != null
          ? _imageMetadataFromJson(map['imageMetadata'])
          : null,
      imageMode: map['imageMode'] == null
          ? null
          : _enumValue(
              ImageCreateMode.values,
              map['imageMode'],
              ImageCreateMode.textToImage,
            ),
      archivedAt: DateTime.tryParse(_stringValue(map['archivedAt'], '')),
    );
  }

  Map<String, Object?> _imageResultToJson(ImageTaskResultItem value) => {
    'id': value.id,
    'status': value.status.name,
    'remoteUrl': value.remoteUrl,
    'localTempPath': value.localTempPath,
    'storageUrl': value.storageUrl,
    'attachmentId': value.attachmentId,
    'lastError': value.lastError,
    'updatedAt': value.updatedAt?.toIso8601String(),
    'downloadRetryCount': value.downloadRetryCount,
    'uploadRetryCount': value.uploadRetryCount,
  };

  ImageTaskResultItem _imageResultFromJson(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
    return ImageTaskResultItem(
      id: _stringValue(
        map['id'],
        'img-${DateTime.now().microsecondsSinceEpoch}',
      ),
      status: _enumValue(
        ImageResultStatus.values,
        map['status'],
        ImageResultStatus.queued,
      ),
      remoteUrl: map['remoteUrl'] as String?,
      localTempPath: map['localTempPath'] as String?,
      storageUrl: map['storageUrl'] as String?,
      attachmentId: map['attachmentId'] as String?,
      lastError: map['lastError'] as String?,
      updatedAt: DateTime.tryParse(_stringValue(map['updatedAt'], '')),
      downloadRetryCount: map['downloadRetryCount'] is num
          ? (map['downloadRetryCount'] as num).round()
          : 0,
      uploadRetryCount: map['uploadRetryCount'] is num
          ? (map['uploadRetryCount'] as num).round()
          : 0,
    );
  }

  Map<String, Object?> _imageMetadataToJson(ImageMetadataState value) => {
    'aspectRatio': value.aspectRatio,
    'quality': value.quality,
    'numImages': value.numImages,
    'outputFormat': value.outputFormat,
    'category': value.category,
    'role': value.role.name,
  };

  ImageMetadataState _imageMetadataFromJson(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
    return ImageMetadataState(
      aspectRatio: _stringValue(
        map['aspectRatio'],
        imageMetadataDefaults.aspectRatio,
      ),
      quality: _stringValue(map['quality'], imageMetadataDefaults.quality),
      numImages: map['numImages'] is num
          ? (map['numImages'] as num).round()
          : imageMetadataDefaults.numImages,
      outputFormat: _stringValue(
        map['outputFormat'],
        imageMetadataDefaults.outputFormat,
      ),
      category: _stringValue(map['category'], imageMetadataDefaults.category),
      role: _enumValue(
        AttachmentRole.values,
        map['role'],
        imageMetadataDefaults.role,
      ),
    );
  }

  Map<String, Object?> _pollLogToJson(TaskPollLog value) => {
    'createdAt': value.createdAt.toIso8601String(),
    'success': value.success,
    'summary': value.summary,
    'requestPreview': value.requestPreview,
    'responsePreview': value.responsePreview,
  };

  TaskPollLog _pollLogFromJson(Object? value) {
    final map = value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
    return TaskPollLog(
      createdAt:
          DateTime.tryParse(_stringValue(map['createdAt'], '')) ??
          DateTime.now(),
      success: _boolValue(map['success'], false),
      summary: _stringValue(map['summary'], '查询记录'),
      requestPreview: _stringValue(map['requestPreview'], '{}'),
      responsePreview: _stringValue(map['responsePreview'], '{}'),
    );
  }

  List<T> _listFromJson<T>(Object? value, T Function(Object? item) convert) {
    if (value is! List) return [];
    return value.map(convert).toList();
  }

  List<String> _stringListFromJson(Object? value) {
    if (value is! List) return [];
    return value.whereType<String>().toList();
  }

  Map<String, int> _intMapFromJson(Object? value) {
    if (value is! Map) return {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final data = entry.value;
      if (key is! String || data is! num) continue;
      result[key] = data.round();
    }
    return result;
  }

  String _stringValue(Object? value, String fallback) =>
      value is String ? value : fallback;

  String? _nullableStringValue(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }

  int _intValue(Object? value, int fallback) =>
      value is num ? value.round() : fallback;

  double _doubleValue(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  void _restoreVideoAttachmentStateFromTask(TaskRecord task) {
    selectedAttachmentIds.clear();
    selectedFirstFrameAttachmentId = null;
    selectedLastFrameAttachmentId = null;

    switch (task.mode) {
      case ModeId.text:
        return;
      case ModeId.firstFrame:
        selectedFirstFrameAttachmentId = task.attachments
            .cast<Attachment?>()
            .firstWhere(
              (item) =>
                  item != null &&
                  item.kind == AttachmentKind.image &&
                  (item.role == AttachmentRole.firstFrame ||
                      item.role == AttachmentRole.referenceImage),
              orElse: () => null,
            )
            ?.id;
        return;
      case ModeId.firstLast:
        final firstFrame = task.attachments.cast<Attachment?>().firstWhere(
          (item) =>
              item != null &&
              item.kind == AttachmentKind.image &&
              (item.role == AttachmentRole.firstFrame ||
                  item.role == AttachmentRole.referenceImage),
          orElse: () => null,
        );
        final lastFrame = task.attachments.cast<Attachment?>().firstWhere(
          (item) =>
              item != null &&
              item.kind == AttachmentKind.image &&
              item.role == AttachmentRole.lastFrame,
          orElse: () => null,
        );
        selectedFirstFrameAttachmentId = firstFrame?.id;
        selectedLastFrameAttachmentId = lastFrame?.id;
        return;
      case ModeId.reference:
        selectedAttachmentIds.addAll(task.attachments.map((item) => item.id));
        return;
    }
  }

  Attachment? _uploadedAttachmentById(
    String? attachmentId, {
    AttachmentKind? kind,
  }) {
    if (attachmentId == null || attachmentId.trim().isEmpty) return null;
    for (final attachment in uploadedLibrary) {
      if (attachment.id != attachmentId) continue;
      if (kind != null && attachment.kind != kind) continue;
      return attachment;
    }
    return null;
  }

  Attachment? get _legacySelectedImageAttachment {
    for (final attachmentId in selectedAttachmentIds) {
      final attachment = _uploadedAttachmentById(
        attachmentId,
        kind: AttachmentKind.image,
      );
      if (attachment != null) return attachment;
    }
    return null;
  }

  String _normalizedVideoPromptForMode(String value, ModeId mode) {
    if (mode == ModeId.reference) {
      return value;
    }
    return value
        .replaceAll(promptTokenPattern, '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  bool _boolValue(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  bool? _nullableBoolValue(Object? value) => value is bool ? value : null;

  Map<String, bool> _boolMapFromJson(Object? value) {
    if (value is! Map) return {};
    final result = <String, bool>{};
    value.forEach((key, mapValue) {
      if (key is String && key.trim().isNotEmpty && mapValue is bool) {
        result[key] = mapValue;
      }
    });
    return result;
  }

  T _enumValue<T extends Enum>(List<T> values, Object? value, T fallback) {
    if (value is! String) return fallback;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return fallback;
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _pollingTimer?.cancel();
    _transferringImageTaskIds.clear();
    super.dispose();
  }
}

class BatchDeleteAttachmentsResult {
  const BatchDeleteAttachmentsResult({
    required this.deletedCount,
    required this.failures,
  });

  final int deletedCount;
  final List<BatchDeleteAttachmentFailure> failures;
}

class BatchDeleteAttachmentFailure {
  const BatchDeleteAttachmentFailure({
    required this.attachment,
    required this.message,
  });

  final Attachment attachment;
  final String message;
}

enum _AttachmentAccessPurpose { preview, share, seedance }

class _SignedUrlCacheEntry {
  const _SignedUrlCacheEntry({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}
