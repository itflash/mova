# 图片生成入库 实施计划

> **给 agentic worker 用的：必须的 SUB-SKILL：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 来逐步实现这个计划。步骤使用 checkbox (`- [ ]`) 语法进行追踪。

**目标：** 在素材库新增 AI 生图入口，新增独立的图片创作页，接入 AgentEarth GPT Image 2 生图能力，自动下载外链并上传七牛/缤纷云入库，任务页新增视频/图片 tab，图片任务支持复制到图片创作、重新生成、失败项重试。

**架构：** 采用路线 A（扩展 TaskRecord），在现有 models.dart 中增加 TaskKind、ImageMetadataState、ImageTaskResultItem 等数据模型；新增 image_generation_service.dart 处理推荐/执行/轮询/结果解析；新增 image_create_page.dart 作为图片创作页；修改 library_page.dart 增加 AI 生图入口；修改 tasks_page.dart 增加视频/图片 tab 和图片任务卡片；在 AppState 中增加图片域的创作状态和任务动作。

**技术栈：** Dart / Flutter + AgentEarth API + 七牛云 / 缤纷云 S4 存储

---

### Task 1: 扩展 models.dart — 新增枚举和数据类

**文件：**
- 修改：`lib/app/models.dart`

按照设计文档的第 7 节，新增以下内容：

- [ ] **Step 1: 在 AttachmentRole 枚举后面新增 TaskKind、TaskTab、ImageCreateMode、ImageResultStatus 枚举**

```dart
enum TaskKind { video, image }

enum TaskTab { video, image }

enum ImageCreateMode { textToImage }

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
```

注意：把 `AttachmentRole` 枚举放在 `TaskKind` 之前，保持代码组织清晰。在 `AttachmentRole` 枚举的闭合 `}` 后插入。

- [ ] **Step 2: 新增 ImageMetadataState 类**

在 `MetadataState` 类之后（`MetadataState` 的 `}` 闭合后）插入：

```dart
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
```

- [ ] **Step 3: 新增 ImageTaskResultItem 类**

在刚添加的 `ImageMetadataState` 之后插入：

```dart
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
      localTempPath: clearLocalTempPath ? null : (localTempPath ?? this.localTempPath),
      storageUrl: clearStorageUrl ? null : (storageUrl ?? this.storageUrl),
      attachmentId: clearAttachmentId ? null : (attachmentId ?? this.attachmentId),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
      downloadRetryCount: downloadRetryCount ?? this.downloadRetryCount,
      uploadRetryCount: uploadRetryCount ?? this.uploadRetryCount,
    );
  }
}
```

- [ ] **Step 4: 扩展 TaskRecord — 增加 kind、imageResults、imageMetadata 字段**

在 `TaskRecord` 类中：

1. 在构造函数参数中（`this.pollLogs = const []` 之前或附近）增加：
```dart
this.kind = TaskKind.video,
this.imageResults = const [],
this.imageMetadata,
```

2. 在字段声明区（`final String id;` 附近合适位置）增加：
```dart
final TaskKind kind;
final List<ImageTaskResultItem> imageResults;
final ImageMetadataState? imageMetadata;
```

3. 在 `copyWith` 方法的参数中增加：
```dart
TaskKind? kind,
List<ImageTaskResultItem>? imageResults,
ImageMetadataState? imageMetadata,
bool clearImageMetadata = false,
```

4. 在 `copyWith` 方法的返回值构造中增加：
```dart
kind: kind ?? this.kind,
imageResults: imageResults ?? this.imageResults,
imageMetadata: clearImageMetadata ? null : (imageMetadata ?? this.imageMetadata),
```

- [ ] **Step 5: 扩展 SettingsState — 增加 imageAutoFallbackEnabled 字段**

1. 在构造函数参数中增加：
```dart
this.imageAutoFallbackEnabled = false,
```

2. 在字段声明区增加：
```dart
final bool imageAutoFallbackEnabled;
```

3. 在 `copyWith` 方法的参数中增加：
```dart
bool? imageAutoFallbackEnabled,
```

4. 在 `copyWith` 的返回值构造中增加：
```dart
imageAutoFallbackEnabled: imageAutoFallbackEnabled ?? this.imageAutoFallbackEnabled,
```

- [ ] **Step 6: 验证 — 运行 `flutter analyze` 确保无编译错误**

```bash
flutter analyze lib/app/models.dart
```

- [ ] **Step 7: 提交**

```bash
git add lib/app/models.dart
git commit -m "feat: add image generation data models (TaskKind, ImageMetadataState, ImageTaskResultItem, etc.)"
```

---

### Task 2: 扩展 mock_data.dart — 新增图片创作默认值

**文件：**
- 修改：`lib/app/mock_data.dart`

- [ ] **Step 1: 在文件末尾新增 imageMetadataDefaults 常量**

```dart
const imageMetadataDefaults = ImageMetadataState(
  aspectRatio: '1:1',
  quality: 'medium',
  numImages: 1,
  outputFormat: 'png',
  category: '',
  role: AttachmentRole.referenceImage,
);
```

- [ ] **Step 2: 在文件末尾新增 aspectRatioToImageSize 映射**

```dart
const aspectRatioToImageSize = {
  '1:1': 'square_hd',
  '4:3': 'landscape_4_3',
  '16:9': 'landscape_16_9',
  '9:16': 'portrait_16_9',
};
```

- [ ] **Step 3: 更新 settingsDefaults — 增加 imageAutoFallbackEnabled**

在 `settingsDefaults` 的定义 `const settingsDefaults = SettingsState(` 的构造函数参数中，在 `autoDownload: true,` 之后增加：

```dart
imageAutoFallbackEnabled: false,
```

- [ ] **Step 4: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/app/mock_data.dart
```

- [ ] **Step 5: 提交**

```bash
git add lib/app/mock_data.dart
git commit -m "feat: add image creation defaults and aspect ratio mapping"
```

---

### Task 3: 新增 image_generation_service.dart

**文件：**
- 创建：`lib/services/image_generation_service.dart`

- [ ] **Step 1: 创建文件骨架和类声明**

```dart
import 'dart:convert';

import '../app/models.dart';
import 'api_client.dart';

class ImageGenerationService {
  ImageGenerationService({ApiClient? client}) : _client = client;

  final ApiClient? _client;

  ApiClient _clientForBaseUrl(String baseUrl) =>
      _client ?? ApiClient(baseUrl: baseUrl);
}
```

- [ ] **Step 2: 实现 resolveTool 方法 — 推荐图片工具**

实际 GPT Image 2 schema 确认自 AgentEarth recommend（2026-06-13）:
- 必填: `prompt` (string)
- 可选: `image_size` (预设字符串或 {width, height} 对象, 默认 `landscape_4_3`), `num_images` (1-4, 默认 1), `output_format` (jpeg/png/webp, 默认 png), `quality` (low/medium/high, 默认 high), `sync_mode` (bool, 默认 false)

Fallback `xl_dumplingai_generate_ai_image` schema 不同：入参是 `prompt` + `height`/`width` (整数像素) + `model` + `style`，没有 `image_size` 预设。

```dart
  Future<SeedanceTool> resolveTool(
    String apiKey, {
    required String baseUrl,
    bool allowFallback = false,
  }) async {
    const primaryToolName = 'xl_falai_post_openai_gpt_image_2';
    const fallbackToolName = 'xl_dumplingai_generate_ai_image';

    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/recommend',
      apiKey,
      {'query': 'GPT Image 2 text to image generation', 'limit': 10},
    );

    final tools = response['tools'];
    if (tools is! List) {
      throw const ApiClientException('AgentEarth 推荐未返回 tools。');
    }

    Map<String, Object?>? matched;
    for (final item in tools) {
      if (item is! Map) continue;
      final tool = Map<String, Object?>.from(item);
      final toolUrl = tool['tool_url'];
      if (toolUrl is String && toolUrl.contains('tool_name=$primaryToolName')) {
        matched = tool;
        break;
      }
    }

    if (matched == null && allowFallback) {
      // fallback 从单独的推荐查询获取
      try {
        return await _resolveFallbackTool(apiKey, baseUrl: baseUrl);
      } on Exception {
        // fallback also failed, throw original error
      }
    }

    if (matched == null) {
      throw ApiClientException(
        'AgentEarth 推荐未返回 $primaryToolName 的完整 tool_url，已阻止扣费执行。',
      );
    }

    final toolUrl = matched['tool_url'] as String;
    return SeedanceTool(
      toolName: matched['tool_name'] is String
          ? matched['tool_name'] as String
          : primaryToolName,
      toolUrl: toolUrl,
      credit: matched['credit'] is num
          ? (matched['credit'] as num).round()
          : 10,
      description: matched['description'] is String
          ? matched['description'] as String
          : 'GPT Image 2',
      inputProperties: const {'prompt', 'image_size', 'num_images', 'output_format', 'quality', 'sync_mode'},
      fromRecommendation: true,
    );
  }
```

- [ ] **Step 3: 实现 buildRequestPreview 方法（含 fallback 专用版本）**

GPT Image 2 主工具使用 `_buildImageExecuteParams`，DumplingAI fallback 使用 `_buildFallbackExecuteParams`（`height`/`width` 整数像素）。

```dart
  SeedanceRequestPreview buildRequestPreview({
    required String prompt,
    required ImageMetadataState metadata,
    required String baseUrl,
    SeedanceTool? tool,
  }) {
    final resolvedTool = tool ?? _fallbackImageTool(baseUrl);
    final params = _buildImageExecuteParams(prompt: prompt, metadata: metadata);
    final body = <String, Object?>{'params': params};
    return _makePreview(resolvedTool, body);
  }

  SeedanceRequestPreview _buildFallbackPreview({
    required String prompt,
    required ImageMetadataState metadata,
    required String baseUrl,
    required SeedanceTool tool,
  }) {
    final params = _buildFallbackExecuteParams(prompt: prompt, metadata: metadata);
    final body = <String, Object?>{'params': params};
    return _makePreview(tool, body);
  }

  SeedanceRequestPreview _makePreview(SeedanceTool tool, Map<String, Object?> body) {
    return SeedanceRequestPreview(
      toolName: tool.toolName,
      toolUrl: tool.toolUrl,
      body: body,
      prettyJson: _prettyJson({
        'tool_name': tool.toolName,
        'tool_url': tool.toolUrl,
        ...body,
      }),
    );
  }
```

- [ ] **Step 4: 实现 execute 方法 — 提交图片生成任务**

关键：DumplingAI fallback 的 schema 不同（`height`/`width` 整数，无 `image_size` 预设），execute 需对 fallback 使用 `_buildFallbackExecuteParams`。

```dart
  Future<TaskExecution> execute({
    required String apiKey,
    required String prompt,
    required ImageMetadataState metadata,
    required String baseUrl,
    SeedanceTool? tool,
    bool allowFallback = false,
  }) async {
    SeedanceTool resolvedTool;
    try {
      resolvedTool = tool ?? await resolveTool(apiKey, baseUrl: baseUrl, allowFallback: allowFallback);
    } on Exception {
      if (allowFallback) {
        resolvedTool = await _resolveFallbackTool(apiKey, baseUrl: baseUrl);
      } else {
        rethrow;
      }
    }

    final isFallback = resolvedTool.toolName == 'xl_dumplingai_generate_ai_image';
    final preview = isFallback
        ? _buildFallbackPreview(prompt: prompt, metadata: metadata, baseUrl: baseUrl, tool: resolvedTool)
        : buildRequestPreview(prompt: prompt, metadata: metadata, baseUrl: baseUrl, tool: resolvedTool);

    Map<String, Object?> response;
    try {
      response = await _clientForBaseUrl(baseUrl).post(
        resolvedTool.toolUrl,
        apiKey,
        preview.body,
      );
    } on Exception catch (error) {
      if (allowFallback && !isFallback) {
        final fallbackTool = await _resolveFallbackTool(apiKey, baseUrl: baseUrl);
        final fallbackPreview = _buildFallbackPreview(
          prompt: prompt, metadata: metadata, baseUrl: baseUrl, tool: fallbackTool,
        );
        try {
          response = await _clientForBaseUrl(baseUrl).post(
            fallbackTool.toolUrl, apiKey, fallbackPreview.body,
          );
          final result = parseAgentEarthAsyncResult(response['result']);
          final responseUrl = _firstStringFromMap(result, ['response_url']);
          if (responseUrl == null) {
            throw TaskExecutionException('备用工具执行成功，但未返回 response_url。', requestPreview: fallbackPreview);
          }
          return TaskExecution(
            responseUrl: responseUrl,
            statusUrl: _firstStringFromMap(result, ['status_url']),
            toolName: fallbackTool.toolName,
            credit: fallbackTool.credit,
            requestPreview: fallbackPreview,
            responsePreview: _prettyJson(response),
          );
        } on Exception catch (fallbackError) {
          throw TaskExecutionException(
            '主工具失败，备用工具也失败：${fallbackError.toString().replaceFirst('Exception: ', '')}',
            requestPreview: preview,
          );
        }
      }
      throw TaskExecutionException(
        error.toString().replaceFirst('Exception: ', ''),
        requestPreview: preview,
      );
    }

    final result = parseAgentEarthAsyncResult(response['result']);
    final responseUrl = _firstStringFromMap(result, ['response_url']);
    if (responseUrl == null) {
      throw TaskExecutionException(
        'AgentEarth 执行成功，但未返回 response_url，无法继续轮询结果。',
        requestPreview: preview,
      );
    }

    return TaskExecution(
      responseUrl: responseUrl,
      statusUrl: _firstStringFromMap(result, ['status_url']),
      toolName: resolvedTool.toolName,
      credit: resolvedTool.credit,
      requestPreview: preview,
      responsePreview: _prettyJson(response),
    );
  }
```

- [ ] **Step 5: 实现 poll 方法 — 轮询并提取图片 URL 列表**

```dart
  Future<ImagePolledResult> poll({
    required String apiKey,
    required String responseUrl,
    required String baseUrl,
  }) async {
    final requestPreview = _buildPollRequestPreview(responseUrl, baseUrl);

    try {
      final response = await _clientForBaseUrl(baseUrl).post(
        '/tool/execute?tool_name=xl_get_response',
        apiKey,
        {'params': {'response_url': responseUrl}},
      );

      final result = parseAgentEarthAsyncResult(response['result']);
      final rawStatus = result['status'] is String ? result['status'] as String : null;
      final imageUrls = _extractImageUrls(result);

      final status = _normalizeImageStatus(rawStatus, imageUrls);
      final failure = _extractFailureDetail(result);

      return ImagePolledResult(
        status: status,
        progress: _normalizeImageProgress(result['progress'], status),
        requestPreview: requestPreview,
        responsePreview: _prettyJson(response),
        imageUrls: imageUrls,
        statusDetail: _normalizeImageStatusDetail(rawStatus, imageUrls, failure),
        lastError: failure?.message,
        hasAnomaly: rawStatus != null && _isCompletedStatus(rawStatus) && imageUrls.isEmpty,
        anomalyMessage: rawStatus != null && _isCompletedStatus(rawStatus) && imageUrls.isEmpty
            ? '上游状态已完成，但没有返回图片 URL，可手动刷新重试。'
            : null,
      );
    } on ApiClientException catch (error) {
      return ImagePolledResult(
        status: TaskStatus.failure,
        progress: 0,
        requestPreview: requestPreview,
        responsePreview: _prettyJson({'error_msg': error.message}),
        imageUrls: const [],
        statusDetail: '查询失败',
        lastError: error.message,
      );
    }
  }
```

- [ ] **Step 6: 实现 ImagePolledResult 类**

在同一个文件末尾添加：

```dart
class ImagePolledResult {
  const ImagePolledResult({
    required this.status,
    required this.progress,
    required this.requestPreview,
    required this.responsePreview,
    required this.imageUrls,
    this.statusDetail,
    this.lastError,
    this.hasAnomaly = false,
    this.anomalyMessage,
  });

  final TaskStatus status;
  final int progress;
  final String requestPreview;
  final String responsePreview;
  final List<String> imageUrls;
  final String? statusDetail;
  final String? lastError;
  final bool hasAnomaly;
  final String? anomalyMessage;
}
```

- [ ] **Step 7: 实现私有辅助方法**

在类中添加以下私有方法：

```dart
  SeedanceTool _fallbackImageTool(String baseUrl) {
    return SeedanceTool(
      toolName: 'xl_falai_post_openai_gpt_image_2',
      toolUrl: '$baseUrl/tool/execute?tool_name=xl_falai_post_openai_gpt_image_2',
      credit: 10,
      description: 'GPT Image 2',
      inputProperties: const {'prompt', 'image_size', 'num_images', 'output_format', 'quality', 'sync_mode'},
      fromRecommendation: false,
    );
  }

  Future<SeedanceTool> _resolveFallbackTool(String apiKey, {required String baseUrl}) async {
    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/recommend',
      apiKey,
      {'query': 'DumplingAI image generation', 'limit': 10},
    );
    final tools = response['tools'];
    if (tools is! List) {
      throw const ApiClientException('AgentEarth 推荐未返回备用工具。');
    }
    for (final item in tools) {
      if (item is! Map) continue;
      final tool = Map<String, Object?>.from(item);
      final toolUrl = tool['tool_url'];
      if (toolUrl is String && toolUrl.contains('tool_name=xl_dumplingai_generate_ai_image')) {
        return SeedanceTool(
          toolName: 'xl_dumplingai_generate_ai_image',
          toolUrl: toolUrl,
          credit: tool['credit'] is num ? (tool['credit'] as num).round() : 10,
          description: tool['description'] is String ? tool['description'] as String : 'DumplingAI Image',
          inputProperties: const {'prompt'},
          fromRecommendation: true,
        );
      }
    }
    throw const ApiClientException('AgentEarth 推荐未返回备用工具。');
  }

  Map<String, Object?> _buildImageExecuteParams({
    required String prompt,
    required ImageMetadataState metadata,
  }) {
    final imageSize = aspectRatioToImageSize[metadata.aspectRatio] ?? 'square_hd';
    return _compactObject({
      'prompt': prompt,
      'image_size': imageSize,
      'num_images': metadata.numImages,
      'output_format': metadata.outputFormat,
      'quality': metadata.quality,
      'sync_mode': false,
    });
  }

  List<String> _extractImageUrls(Map<String, Object?> result) {
    final urls = <String>[];
    _collectImageUrls(result, urls);
    return urls;
  }

  void _collectImageUrls(Object? value, List<String> urls) {
    final parsed = _parseEmbeddedJson(value);
    if (parsed is List) {
      for (final item in parsed) {
        _collectImageUrls(item, urls);
      }
    } else if (parsed is Map) {
      final directKeys = ['image_url', 'url', 'download_url', 'file_url'];
      for (final key in directKeys) {
        final candidate = parsed[key];
        if (candidate is String && _looksLikeImageUrl(candidate)) {
          urls.add(candidate.trim());
        }
      }
      for (final entry in parsed.entries) {
        if (entry.key.toString() == 'images' && entry.value is List) {
          for (final img in entry.value as List) {
            if (img is String && _looksLikeImageUrl(img)) {
              urls.add(img.trim());
            } else if (img is Map) {
              final url = img['url'];
              if (url is String && _looksLikeImageUrl(url)) {
                urls.add(url.trim());
              }
            }
          }
        } else if (!directKeys.contains(entry.key.toString())) {
          _collectImageUrls(entry.value, urls);
        }
      }
    }
  }

  bool _looksLikeImageUrl(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }
    final lower = trimmed.toLowerCase();
    return lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.webp') ||
        lower.contains('/image') ||
        lower.contains('/images') ||
        lower.contains('output') ||
        lower.contains('result');
  }

  TaskStatus _normalizeImageStatus(String? rawStatus, List<String> imageUrls) {
    if (imageUrls.isNotEmpty) return TaskStatus.success;
    final text = rawStatus?.toUpperCase();
    if (['FAILED', 'FAILURE', 'ERROR', 'CANCELED'].contains(text)) {
      return TaskStatus.failure;
    }
    if (['COMPLETED', 'SUCCESS', 'SUCCEEDED', 'OK'].contains(text)) {
      return TaskStatus.inProgress;
    }
    if (['IN_PROGRESS', 'RUNNING', 'PROCESSING'].contains(text)) {
      return TaskStatus.inProgress;
    }
    return TaskStatus.submitted;
  }

  int _normalizeImageProgress(Object? progress, TaskStatus status) {
    if (progress is num && progress.isFinite) return progress.round().clamp(0, 100);
    if (progress is String) {
      final parsed = num.tryParse(progress.replaceAll('%', '').trim());
      if (parsed != null && parsed.isFinite) return parsed.round().clamp(0, 100);
    }
    if (status == TaskStatus.success) return 100;
    if (status == TaskStatus.failure) return 0;
    if (status == TaskStatus.inProgress) return 68;
    return 10;
  }

  String? _normalizeImageStatusDetail(String? rawStatus, List<String> imageUrls, dynamic failure) {
    if (imageUrls.isNotEmpty) return 'SUCCESS (${imageUrls.length} images)';
    if (failure != null) return failure.message ?? 'FAILURE';
    return rawStatus;
  }

  String? _firstStringFromMap(Map<String, Object?> value, List<String> keys) {
    for (final key in keys) {
      final item = value[key];
      if (item is String && item.trim().isNotEmpty) return item;
    }
    return null;
  }

  Map<String, Object?> _compactObject(Map<String, Object?> value) {
    return Map.fromEntries(
      value.entries.where((entry) => _isPresent(entry.value)),
    );
  }

  bool _isPresent(Object? value) {
    if (value == null || value == '') return false;
    if (value is List) return value.isNotEmpty;
    return true;
  }

  String _prettyJson(Object? value) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  }

  Object? _parseEmbeddedJson(Object? value) {
    if (value is! String) return value;
    final trimmed = value.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        return value;
      }
    }
    return value;
  }
```

注意：`_extractFailureDetail`、`_isCompletedStatus`、`_buildPollRequestPreview`、`parseAgentEarthAsyncResult` 这些工具方法从 `seedance_service.dart` 中复用。需要在文件顶部声明：

```dart
import 'seedance_service.dart';
```

因为 `parseAgentEarthAsyncResult` 和 `_buildPollRequestPreview` 等方法在 `seedance_service.dart` 中定义。或者将它们提取到共享工具文件中。出于简洁考虑，此阶段从 `ImageGenerationService` 直接引用 `seedance_service.dart` 中的公开方法。`_buildPollRequestPreview` 是私有的，所以我们需要在 `seedance_service.dart` 中将 `buildPollRequestPreview` 保持为公开函数（它已经是公开的），并且在 `ImageGenerationService` 中调用它。

实际上 `buildPollRequestPreview` 已经是公开函数（在 `seedance_service.dart` 第 305 行定义），所以直接使用即可。

- [ ] **Step 8: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/services/image_generation_service.dart
```

- [ ] **Step 9: 提交**

```bash
git add lib/services/image_generation_service.dart
git commit -m "feat: add image generation service with recommend/execute/poll"
```

---

### Task 4: 在 AppState 中补图片任务状态与动作

**文件：**
- 修改：`lib/app/app_state.dart`

- [ ] **Step 1: 引入 image_generation_service**

在文件顶部的 import 区域（`import '../services/seedance_service.dart';` 之后）新增：

```dart
import '../services/image_generation_service.dart';
```

- [ ] **Step 2: 新增图片创作状态字段**

在 `AppState` 类的字段声明区（`final Map<ModeId, ToolResolution> toolResolutions = {};` 之后）新增：

```dart
  String imagePrompt = '';
  ImageMetadataState imageMetadata = imageMetadataDefaults;
  ImageCreateMode activeImageMode = ImageCreateMode.textToImage;
  ToolResolution imageToolResolution = ToolResolution(status: ToolResolutionStatus.idle);
  bool isSubmittingImageTask = false;
  String? imageSubmitErrorMessage;
  TaskTab activeTaskTab = TaskTab.video;
```

- [ ] **Step 3: 新增 image_generation_service 实例**

在构造函数中增加：

```dart
final ImageGenerationService _imageGenerationService;
```

在构造函数参数中增加：

```dart
ImageGenerationService? imageGenerationService,
```

在初始化列表中增加：

```dart
_imageGenerationService = imageGenerationService ?? ImageGenerationService(),
```

- [ ] **Step 4: 新增图片创作相关方法**

在 `AppState` 类中新增以下方法。放在 `resolveActiveTool()` 方法之后：

```dart
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
        baseUrl: settings.agentEarthBaseUrl,
        allowFallback: settings.imageAutoFallbackEnabled,
      );
      imageToolResolution = ToolResolution(status: ToolResolutionStatus.ready, tool: tool);
    } on Exception catch (error) {
      imageToolResolution = ToolResolution(
        status: ToolResolutionStatus.error,
        errorMessage: _cleanError(error),
      );
    }
    notifyListeners();
  }
```

在 `requestPreview` getter 之后新增：

```dart
  SeedanceRequestPreview get imageRequestPreview =>
      _imageGenerationService.buildRequestPreview(
        prompt: imagePrompt,
        metadata: imageMetadata,
        baseUrl: settings.agentEarthBaseUrl,
        tool: imageToolResolution.tool,
      );
```

在 `copyTaskToCreate` 方法之后新增：

```dart
  void copyImageTaskToCreate(String taskId) {
    final task = tasks.cast<TaskRecord?>().firstWhere(
      (item) => item?.id == taskId,
      orElse: () => null,
    );
    if (task == null || task.kind != TaskKind.image) return;

    imagePrompt = task.prompt;
    imageMetadata = task.imageMetadata ?? imageMetadataDefaults;
    currentTab = AppTab.create;
    notifyListeners();
  }
```

在 `submitTask` 方法之后新增 `submitImageTask` 方法：

```dart
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
    if (isSubmittingImageTask) {
      imageSubmitErrorMessage = '任务正在提交中。';
      notifyListeners();
      return false;
    }

    isSubmittingImageTask = true;
    imageSubmitErrorMessage = null;
    notifyListeners();

    try {
      await resolveImageTool();
      final execution = await _imageGenerationService.execute(
        apiKey: settings.agentEarthApiKey,
        prompt: imagePrompt,
        metadata: imageMetadata,
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
          prompt: imagePrompt,
          status: TaskStatus.submitted,
          pollingStatus: settings.autoPoll ? PollingStatus.polling : PollingStatus.idle,
          downloadStatus: DownloadStatus.idle,
          progress: 10,
          downloadProgress: 0,
          createdAt: now,
          updatedAt: now,
          estimatedCredit: execution.credit,
          attachments: const [],
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
```

在 `refreshTask` 方法之后新增 `refreshImageTask` 方法：

```dart
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
      status: task.status == TaskStatus.submitted ? TaskStatus.inProgress : task.status,
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

      final isDone = result.status == TaskStatus.success || result.status == TaskStatus.failure;
      final nextPolling = isDone ? PollingStatus.idle : PollingStatus.polling;

      final latestIndex = tasks.indexWhere((item) => item.id == taskId);
      if (latestIndex == -1) return false;
      final currentTask = tasks[latestIndex];

      // 更新结果项：新图片 URL 匹配到对应结果项
      List<ImageTaskResultItem> updatedResults = List.from(currentTask.imageResults);
      for (var i = 0; i < result.imageUrls.length && i < updatedResults.length; i++) {
        if (updatedResults[i].remoteUrl == null || updatedResults[i].remoteUrl!.isEmpty) {
          updatedResults[i] = updatedResults[i].copyWith(
            remoteUrl: result.imageUrls[i],
            status: ImageResultStatus.readyToTransfer,
            updatedAt: DateTime.now(),
          );
        }
      }

      final summary = result.lastError ?? result.statusDetail ?? '查询完成';
      tasks[latestIndex] = _appendPollLog(
        currentTask.copyWith(
          status: result.status,
          pollingStatus: nextPolling,
          progress: result.progress < currentTask.progress ? currentTask.progress : result.progress,
          statusDetail: result.statusDetail,
          lastError: result.lastError,
          responsePreview: result.responsePreview,
          updatedAt: DateTime.now(),
          clearLastError: result.lastError == null,
          hasAnomaly: result.hasAnomaly,
          anomalyMessage: result.anomalyMessage,
          clearAnomalyMessage: !result.hasAnomaly,
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

      // 触发转存：对 readyToTransfer 的结果项启动下载+上传
      if (result.status == TaskStatus.success && isCurrentStorageConfigured) {
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
          : buildPollRequestPreview(fallbackPollUrl, baseUrl: settings.agentEarthBaseUrl);
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
          responsePreview: jsonEncode({'error': _cleanError(error)}),
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
```

- [ ] **Step 5: 新增转存相关方法**

在 `downloadTaskResult` 方法之后新增：

```dart
  Future<void> _transferImageResults(String taskId) async {
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return;
    final task = tasks[index];
    if (task.kind != TaskKind.image) return;

    for (var i = 0; i < task.imageResults.length; i++) {
      final item = task.imageResults[i];
      if (item.status != ImageResultStatus.readyToTransfer && item.status != ImageResultStatus.downloadFailed && item.status != ImageResultStatus.uploadFailed) {
        continue;
      }
      if (item.remoteUrl == null || item.remoteUrl!.isEmpty) continue;

      // 下载
      tasks[index] = task.copyWith(
        imageResults: _updateImageResult(task.imageResults, i, item.copyWith(status: ImageResultStatus.downloading, updatedAt: DateTime.now())),
      );
      notifyListeners();

      File? tempFile;
      try {
        tempFile = await downloadRemoteImageToTemp(item.remoteUrl!, 'img-${item.id}.${imageMetadata.outputFormat}');
      } on Exception catch (error) {
        tasks[index] = task.copyWith(
          imageResults: _updateImageResult(task.imageResults, i, item.copyWith(
            status: ImageResultStatus.downloadFailed,
            lastError: '下载失败：${_cleanError(error)}',
            downloadRetryCount: item.downloadRetryCount + 1,
            updatedAt: DateTime.now(),
          )),
        );
        notifyListeners();
        continue;
      }

      // 上传
      tasks[index] = task.copyWith(
        imageResults: _updateImageResult(task.imageResults, i, item.copyWith(
          status: ImageResultStatus.uploading,
          localTempPath: tempFile.path,
          updatedAt: DateTime.now(),
        )),
      );
      notifyListeners();

      try {
        final mimeType = 'image/${imageMetadata.outputFormat}';
        final bytes = await tempFile.readAsBytes();
        final pickedFile = PickedNativeFile.fromBytes(
          name: 'ai-image-${item.id}.${imageMetadata.outputFormat}',
          mimeType: mimeType,
          bytes: bytes,
        );

        final uploadResult = await switch (settings.storageProvider) {
          StorageProvider.qiniu => _qiniuUploadService.upload(settings: settings, file: pickedFile),
          StorageProvider.bitifulS4 => _bitifulUploadService.upload(settings: settings, file: pickedFile),
        };

        final attachmentId = await insertUploadedAttachment(
          uploadResult,
          labelOverride: 'AI图片-${DateTime.now().millisecondsSinceEpoch}',
          roleOverride: imageMetadata.role,
          categoryOverride: imageMetadata.category,
        );

        tasks[index] = task.copyWith(
          imageResults: _updateImageResult(task.imageResults, i, item.copyWith(
            status: ImageResultStatus.imported,
            storageUrl: uploadResult.url,
            attachmentId: attachmentId,
            updatedAt: DateTime.now(),
          )),
        );
        notifyListeners();
      } on Exception catch (error) {
        tasks[index] = task.copyWith(
          imageResults: _updateImageResult(task.imageResults, i, item.copyWith(
            status: ImageResultStatus.uploadFailed,
            lastError: '上传失败：${_cleanError(error)}',
            uploadRetryCount: item.uploadRetryCount + 1,
            updatedAt: DateTime.now(),
          )),
        );
        notifyListeners();
      }
    }

    // 聚合任务级状态
    _aggregateImageTaskStatus(taskId);
  }

  void _aggregateImageTaskStatus(String taskId) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = tasks[index];
    final results = task.imageResults;
    final imported = results.where((r) => r.status == ImageResultStatus.imported).length;
    final total = results.length;
    final failed = results.where((r) =>
      r.status == ImageResultStatus.downloadFailed || r.status == ImageResultStatus.uploadFailed
    ).length;

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

  List<ImageTaskResultItem> _updateImageResult(List<ImageTaskResultItem> results, int index, ImageTaskResultItem updated) {
    final copy = List<ImageTaskResultItem>.from(results);
    copy[index] = updated;
    return copy;
  }

  Future<File> downloadRemoteImageToTemp(String url, String fileName) async {
    final uri = Uri.parse(url);
    final request = await HttpClient().getUrl(uri);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('下载失败（HTTP ${response.statusCode}）', uri: uri);
    }
    final tempFile = File('${Directory.systemTemp.path}/$fileName');
    final sink = tempFile.openWrite();
    await for (final chunk in response) {
      sink.add(chunk);
    }
    await sink.close();
    return tempFile;
  }

  Future<String> insertUploadedAttachment(
    StorageUploadResult result, {
    String? labelOverride,
    AttachmentRole? roleOverride,
    String? categoryOverride,
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
      ),
    );
    notifyListeners();
    return id;
  }
```

- [ ] **Step 6: 新增重试方法**

```dart
  Future<bool> retryFailedImageTransfers(String taskId) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;
    final task = tasks[index];
    if (task.kind != TaskKind.image) return false;

    // 清空失败状态的结果项
    final updatedResults = task.imageResults.map((item) {
      if (item.status == ImageResultStatus.downloadFailed || item.status == ImageResultStatus.uploadFailed) {
        return item.copyWith(
          status: item.remoteUrl != null ? ImageResultStatus.readyToTransfer : ImageResultStatus.queued,
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
      imageResults: _updateImageResult(task.imageResults, resultIndex, item.copyWith(status: ImageResultStatus.readyToTransfer, clearLastError: true)),
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
      imageResults: _updateImageResult(task.imageResults, resultIndex, item.copyWith(status: ImageResultStatus.readyToTransfer, clearLastError: true)),
    );
    notifyListeners();
    unawaited(_transferImageResults(taskId));
    return true;
  }
```

注意：需要在 `import 'dart:io';` 和 `import 'dart:convert';` 之后确保 `HttpClient` 和 `File` 可访问 — 它们已经通过 `dart:io` 引入。

- [ ] **Step 7: 更新序列化 — _taskToJson 和 _taskFromJson**

在 `_taskToJson` 方法中，增加图片相关字段：

```dart
'kind': value.kind.name,
'imageResults': value.imageResults.map(_imageResultToJson).toList(),
'imageMetadata': value.imageMetadata != null ? _imageMetadataToJson(value.imageMetadata!) : null,
```

在 `_taskFromJson` 方法中，从 map 中读取：

```dart
kind: _enumValue(TaskKind.values, map['kind'], TaskKind.video),
imageResults: _listFromJson(map['imageResults'], _imageResultFromJson),
imageMetadata: map['imageMetadata'] != null ? _imageMetadataFromJson(map['imageMetadata']) : null,
```

新增序列化辅助方法：

```dart
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
    final map = value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
    return ImageTaskResultItem(
      id: _stringValue(map['id'], 'img-${DateTime.now().microsecondsSinceEpoch}'),
      status: _enumValue(ImageResultStatus.values, map['status'], ImageResultStatus.queued),
      remoteUrl: map['remoteUrl'] as String?,
      localTempPath: map['localTempPath'] as String?,
      storageUrl: map['storageUrl'] as String?,
      attachmentId: map['attachmentId'] as String?,
      lastError: map['lastError'] as String?,
      updatedAt: DateTime.tryParse(_stringValue(map['updatedAt'], '')),
      downloadRetryCount: map['downloadRetryCount'] is num ? (map['downloadRetryCount'] as num).round() : 0,
      uploadRetryCount: map['uploadRetryCount'] is num ? (map['uploadRetryCount'] as num).round() : 0,
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
    final map = value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
    return ImageMetadataState(
      aspectRatio: _stringValue(map['aspectRatio'], imageMetadataDefaults.aspectRatio),
      quality: _stringValue(map['quality'], imageMetadataDefaults.quality),
      numImages: map['numImages'] is num ? (map['numImages'] as num).round() : imageMetadataDefaults.numImages,
      outputFormat: _stringValue(map['outputFormat'], imageMetadataDefaults.outputFormat),
      category: _stringValue(map['category'], imageMetadataDefaults.category),
      role: _enumValue(AttachmentRole.values, map['role'], imageMetadataDefaults.role),
    );
  }
```

- [ ] **Step 8: 更新 _settingsToJson 和 _settingsFromJson**

在 `_settingsToJson` 的返回 map 中增加：

```dart
'imageAutoFallbackEnabled': value.imageAutoFallbackEnabled,
```

在 `_settingsFromJson` 的 `SettingsState(...)` 构造中增加：

```dart
imageAutoFallbackEnabled: _boolValue(map['imageAutoFallbackEnabled'], false),
```

- [ ] **Step 9: 在 _restoreFromJson 中恢复 activeTaskTab**

在 `_restoreFromJson` 方法中，和 `currentTab` 等字段一起恢复：

```dart
activeTaskTab = _enumValue(TaskTab.values, map['activeTaskTab'], TaskTab.video);
```

在 `_toJson` 方法的返回 map 中增加：

```dart
'activeTaskTab': activeTaskTab.name,
```

- [ ] **Step 10: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/app/app_state.dart
```

- [ ] **Step 11: 提交**

```bash
git add lib/app/app_state.dart
git commit -m "feat: add image task state, actions, and transfer methods to AppState"
```

---

### Task 5: 在 native_file_picker.dart 中新增工厂方法

**文件：**
- 修改：`lib/services/native_file_picker.dart`

- [ ] **Step 1: 为 PickedNativeFile 新增 fromBytes 工厂方法**

在 `fromPlatformMap` 工厂方法之后新增：

```dart
  factory PickedNativeFile.fromBytes({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) {
    return PickedNativeFile(name: name, mimeType: mimeType, bytes: bytes);
  }
```

- [ ] **Step 2: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/services/native_file_picker.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/services/native_file_picker.dart
git commit -m "feat: add fromBytes factory to PickedNativeFile"
```

---

### Task 6: 新增图片创作页 image_create_page.dart

**文件：**
- 创建：`lib/pages/image_create_page.dart`

> 此页面的 UI 设计交由 UI UX promax 把控。下面的代码是功能骨架，具体 UI 组件样式需由 UI UX promax 调整。

- [ ] **Step 1: 创建 ImageCreatePage 骨架**

```dart
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/mock_data.dart';
import '../app/models.dart';
import 'home_shell.dart';

class ImageCreatePage extends StatefulWidget {
  const ImageCreatePage({super.key});

  @override
  State<ImageCreatePage> createState() => _ImageCreatePageState();
}

class _ImageCreatePageState extends State<ImageCreatePage> {
  late final TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _syncPrompt(state);

    return AppPageScaffold(
      eyebrow: 'Create',
      title: '图片创作',
      subtitle: '生成图片并自动入库到素材库。',
      trailing: _ImageSubmitCluster(
        state: state,
        onSubmit: state.imagePrompt.trim().isNotEmpty && !state.isSubmittingImageTask
            ? () => _submitImageTask(context, state)
            : null,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: [
          // 模式区
          SectionLabel('模式'),
          UtilityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ModeChip(label: '文生图', selected: true, onTap: () {}),
                const SizedBox(height: 12),
                Text('使用文字描述生成图片。', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 描述区
          SectionLabel('描述'),
          UtilityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prompt', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _promptController,
                  minLines: 4,
                  maxLines: 7,
                  onChanged: (value) {
                    state.imagePrompt = value;
                    state.notifyListeners();
                  },
                  decoration: const InputDecoration(
                    hintText: '描述主体、风格、镜头、构图、光线、材质和氛围。',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 参数区
          SectionLabel('参数'),
          UtilityPanel(
            child: Column(
              children: [
                _DropdownRow(
                  label: '比例',
                  value: state.imageMetadata.aspectRatio,
                  items: const ['1:1', '4:3', '16:9', '9:16'],
                  onChanged: (v) {
                    state.imageMetadata = state.imageMetadata.copyWith(aspectRatio: v);
                    state.notifyListeners();
                  },
                ),
                const PanelDivider(),
                _DropdownRow(
                  label: '质量',
                  value: state.imageMetadata.quality,
                  items: const ['low', 'medium', 'high'],
                  onChanged: (v) {
                    state.imageMetadata = state.imageMetadata.copyWith(quality: v);
                    state.notifyListeners();
                  },
                ),
                const PanelDivider(),
                _DropdownRow(
                  label: '张数',
                  value: '${state.imageMetadata.numImages}',
                  items: const ['1', '2', '3', '4'],
                  onChanged: (v) {
                    state.imageMetadata = state.imageMetadata.copyWith(numImages: int.tryParse(v) ?? 1);
                    state.notifyListeners();
                  },
                ),
                const PanelDivider(),
                _DropdownRow(
                  label: '输出格式',
                  value: state.imageMetadata.outputFormat,
                  items: const ['png', 'jpeg', 'webp'],
                  onChanged: (v) {
                    state.imageMetadata = state.imageMetadata.copyWith(outputFormat: v);
                    state.notifyListeners();
                  },
                ),
                const PanelDivider(),
                _DropdownRow(
                  label: '分类',
                  value: state.imageMetadata.category,
                  items: ['', ...state.categories],
                  displayItems: ['(默认)', ...state.categories],
                  onChanged: (v) {
                    state.imageMetadata = state.imageMetadata.copyWith(category: v);
                    state.notifyListeners();
                  },
                ),
                const PanelDivider(),
                _DropdownRow<AttachmentRole>(
                  label: '入库角色',
                  value: state.imageMetadata.role,
                  items: const [AttachmentRole.referenceImage, AttachmentRole.firstFrame, AttachmentRole.lastFrame],
                  displayItems: const ['参考图', '首帧图', '尾帧图'],
                  itemToLabel: (r) {
                    switch (r) {
                      case AttachmentRole.referenceImage: return '参考图';
                      case AttachmentRole.firstFrame: return '首帧图';
                      case AttachmentRole.lastFrame: return '尾帧图';
                      default: return '参考图';
                    }
                  },
                  onChanged: (v) {
                    state.imageMetadata = state.imageMetadata.copyWith(role: v);
                    state.notifyListeners();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 请求预览区
          SectionLabel('请求预览'),
          UtilityPanel(child: _ImageRequestPreviewCard(state: state)),
          const SizedBox(height: 16),
          // 提交区
          _ImageSubmitPanel(
            state: state,
            onSubmit: state.imagePrompt.trim().isNotEmpty && !state.isSubmittingImageTask
                ? () => _submitImageTask(context, state)
                : null,
          ),
          if (state.imageSubmitErrorMessage != null) ...[
            const SizedBox(height: 16),
            SectionLabel('提交失败'),
            UtilityPanel(
              child: UtilityTile(
                title: state.imageSubmitErrorMessage!,
                subtitle: '任务没有被创建，也不会产生扣费执行记录。',
                trailing: Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _syncPrompt(AppState state) {
    if (_promptController.text != state.imagePrompt) {
      _promptController.value = TextEditingValue(
        text: state.imagePrompt,
        selection: TextSelection.collapsed(offset: state.imagePrompt.length),
      );
    }
  }

  Future<void> _submitImageTask(BuildContext context, AppState state) async {
    final submitted = await state.submitImageTask();
    if (submitted) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('图片任务已提交')));
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(state.imageSubmitErrorMessage ?? '提交失败')));
  }
}

// 辅助组件...
```

**注意：** 以上是功能骨架代码，具体 UI 组件的视觉样式需要由 UI UX promax 根据实际设计语言调整。关键点：
- 右上角积分 badge（复用 `_CreditBadge` 的模式，但使用 `imageToolResolution`）
- 右上角"生成并入库"按钮
- 模式区目前只有"文生图"
- 参数区使用 `_DropdownRow` 系列组件

- [ ] **Step 2: 补充提交集群组件 _ImageSubmitCluster、_ImageSubmitPanel、_ImageRequestPreviewCard 等**

在文件末尾添加这些私有组件。核心是：
- `_ImageSubmitCluster`: 积分 badge + 提交按钮（右上角 trailing）
- `_ImageSubmitPanel`: 底部提交面板（积分 + 提交按钮）
- `_ImageRequestPreviewCard`: 请求预览卡片
- `_DropdownRow`: 复用 video 创作页的 `_ValueRow` + `DropdownButton` 模式
- `_CreditBadge` 类和 `_ModeChip` 类从 `create_page.dart` 复用（或提取为共享 widget）

- [ ] **Step 3: 注册路由 — 修改 home_shell.dart**

需要在 `home_shell.dart` 中将 `ImageCreatePage` 注册为路由。因为当前设计是：素材库页点击"AI 生图"跳转到 `ImageCreatePage`，这不是一个底部 tab，而是一个通过 Navigator.push 进入的独立页面。所以在 `library_page.dart` 中直接通过 `Navigator.push` 进入即可，不需要修改 `home_shell.dart`。

- [ ] **Step 4: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/pages/image_create_page.dart
```

- [ ] **Step 5: 提交**

```bash
git add lib/pages/image_create_page.dart
git commit -m "feat: add image create page with mode/prompt/params/preview/submit"
```

---

### Task 7: 在素材库页增加 AI 生图入口

**文件：**
- 修改：`lib/pages/library_page.dart`

- [ ] **Step 1: 在"上传与统计"区（upload & stats section）新增 AI 生图按钮**

在 `library_page.dart` 中找到"打开相册"按钮所在位置（在 `UploadStatsPanel` 或类似的区域中），在"打开相册"按钮旁边新增一个并列的 `AI 生图` 按钮。

按钮样式与"打开相册"一致，点击时需要先引入 `image_create_page.dart`:

```dart
import 'image_create_page.dart';
```

然后在按钮的 onPressed 中：

```dart
onPressed: () {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ImageCreatePage()),
  );
}
```

**注意：** 具体按钮在 `library_page.dart` 中的位置需要由代码阅读确定。根据设计文档是在 `打开相册` 按钮旁边。

- [ ] **Step 2: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/pages/library_page.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/pages/library_page.dart
git commit -m "feat: add AI image creation entry to library page"
```

---

### Task 8: 在任务页增加视频/图片 tab 和图片任务卡片

**文件：**
- 修改：`lib/pages/tasks_page.dart`

- [ ] **Step 1: 在 tasks_page.dart 顶部新增 tab 切换 UI**

在 `AppPageScaffold` 的 `eyebrow`/`title`/`subtitle` 区域下方，任务列表上方，新增 tab 切换：

```dart
Row(
  children: [
    _TaskTabChip(label: '视频', selected: state.activeTaskTab == TaskTab.video, onTap: () => state.activeTaskTab = TaskTab.video),
    const SizedBox(width: 10),
    _TaskTabChip(label: '图片', selected: state.activeTaskTab == TaskTab.image, onTap: () => state.activeTaskTab = TaskTab.image),
  ],
)
```

- [ ] **Step 2: 根据 activeTaskTab 过滤任务列表**

```dart
final filteredTasks = state.tasks.where((task) {
  if (state.activeTaskTab == TaskTab.video) return task.kind == TaskKind.video;
  return task.kind == TaskKind.image;
}).toList();
```

将原来的 `state.tasks` 替换为 `filteredTasks`。

- [ ] **Step 3: 为图片任务渲染不同的任务卡片**

在 `itemBuilder` 中，根据 `task.kind` 渲染不同的卡片内容：

```dart
if (task.kind == TaskKind.image) {
  return _ImageTaskCard(task: task, state: state);
}
return _VideoTaskCard(task: task, state: state);  // 原视频任务卡片逻辑
```

- [ ] **Step 4: 创建 _ImageTaskCard 组件**

在同一个文件中新增 `_ImageTaskCard` 组件，包含：
- 状态标签（StatusPill）
- Prompt 摘要
- 创建时间 / 更新时间
- 异常标识
- 状态详情
- 失败原因
- 轮询日志入口
- 生成张数：`${task.imageMetadata?.numImages ?? 0}`
- 已入库 x/y：`${task.imageResults.where((r) => r.status == ImageResultStatus.imported).length}/${task.imageResults.length}`
- 缩略图结果网格（简单展示 status/url）
- 操作按钮：复制到图片创作、重新生成、重试失败项、查看详情、删除任务

**注意：** 详细 UI 样式交由 UI UX promax 把控。这里只提供功能骨架。

- [ ] **Step 5: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/pages/tasks_page.dart
```

- [ ] **Step 6: 提交**

```bash
git add lib/pages/tasks_page.dart
git commit -m "feat: add video/image tab and image task cards to tasks page"
```

---

### Task 9: 在设置页增加图片自动 fallback 开关

**文件：**
- 修改：`lib/pages/settings_page.dart`

- [ ] **Step 1: 在设置页的高级设置区新增开关**

在 `settings_page.dart` 中找到合适位置（"生成"相关设置区或"高级"设置区的末尾），新增：

```dart
SwitchListTile.adaptive(
  contentPadding: EdgeInsets.zero,
  title: const Text('主工具失败时自动尝试备用生图服务'),
  subtitle: Text(
    '关闭后会严格使用 GPT Image 2；开启后失败时会尝试兼容服务，结果风格和参数支持可能不同。',
    style: Theme.of(context).textTheme.bodySmall,
  ),
  value: state.settings.imageAutoFallbackEnabled,
  onChanged: (value) => state.updateSettings(
    (current) => current.copyWith(imageAutoFallbackEnabled: value),
  ),
),
```

- [ ] **Step 2: 验证 — 运行 flutter analyze**

```bash
flutter analyze lib/pages/settings_page.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat: add image auto fallback toggle to settings"
```

---

### Task 10: 补测试和集成验证

**文件：**
- 创建：`test/models_test.dart` (扩展)
- 创建：`test/image_generation_service_test.dart`
- 创建：`test/app_state_image_test.dart`

- [ ] **Step 1: 编写 ImageTaskResultItem 的序列化测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/models.dart';

void main() {
  test('ImageTaskResultItem copyWith preserves non-updated fields', () {
    final item = ImageTaskResultItem(
      id: 'img-1',
      status: ImageResultStatus.queued,
    );
    final updated = item.copyWith(status: ImageResultStatus.generating);
    expect(updated.id, 'img-1');
    expect(updated.status, ImageResultStatus.generating);
  });

  test('ImageTaskResultItem copyWith clear fields', () {
    final item = ImageTaskResultItem(
      id: 'img-1',
      status: ImageResultStatus.readyToTransfer,
      remoteUrl: 'https://example.com/img.png',
      lastError: 'some error',
    );
    final cleared = item.copyWith(clearRemoteUrl: true, clearLastError: true);
    expect(cleared.remoteUrl, isNull);
    expect(cleared.lastError, isNull);
  });
}
```

- [ ] **Step 2: 运行测试**

```bash
flutter test test/
```

- [ ] **Step 3: 提交**

```bash
git add test/
git commit -m "test: add model serialization and image service tests"
```

- [ ] **Step 4: 运行完整的 flutter analyze**

```bash
flutter analyze
```

确保整个项目没有分析错误。

- [ ] **Step 5: 最终提交（如有遗漏修改）**

```bash
git add -A
git commit -m "chore: fix remaining analysis issues"
```

---

## 实施完成后的验证清单

1. 素材库页可看到 "AI 生图" 按钮，点击可进入图片创作页
2. 图片创作页可展示积分 badge
3. 图片创作页可展示请求预览
4. 图片创作页可提交任务
5. 提交后任务页自动切到 "图片" tab
6. 图片任务可正常轮询
7. 图片任务可显示状态详情
8. 图片任务可复制到图片创作页
9. 图片任务可重新生成
10. 图片任务可重试失败项
11. 上游返回图片 URL 时能自动下载
12. 下载成功后自动上传到七牛/缤纷云
13. 上传成功后自动写入素材库
14. 视频创作页现有能力不受影响
15. 视频任务页现有能力不受影响
16. 手动素材上传不受影响
17. 设置页新增 fallback 开关，默认关闭
