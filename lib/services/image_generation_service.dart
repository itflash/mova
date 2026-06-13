import 'dart:convert';

import '../app/mock_data.dart';
import '../app/models.dart';
import 'api_client.dart';
import 'seedance_service.dart';

class ImageGenerationService {
  ImageGenerationService({ApiClient? client})
    : _client = client; // ignore: prefer_initializing_formals

  final ApiClient? _client;

  ApiClient _clientForBaseUrl(String baseUrl) =>
      _client ?? ApiClient(baseUrl: baseUrl);

  static const _ratioToPixels = {
    '1:1': (1024, 1024),
    '4:3': (1360, 1024),
    '16:9': (1360, 768),
    '9:16': (768, 1360),
  };

  Future<SeedanceTool> resolveTool(
    String apiKey, {
    required ImageCreateMode mode,
    required String baseUrl,
    bool allowFallback = false,
  }) async {
    final primaryToolName = _primaryToolName(mode);
    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/recommend',
      apiKey,
      {'query': _recommendQuery(mode), 'limit': 10},
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

    if (matched == null &&
        allowFallback &&
        mode == ImageCreateMode.textToImage) {
      try {
        return await _resolveFallbackTool(apiKey, baseUrl: baseUrl);
      } on Exception {
        // Fall through to the primary-tool error below.
      }
    }

    if (matched == null) {
      throw ApiClientException(
        'AgentEarth 推荐未返回 $primaryToolName 的完整 tool_url，已阻止扣费执行。',
      );
    }

    return SeedanceTool(
      toolName: matched['tool_name'] is String
          ? matched['tool_name'] as String
          : primaryToolName,
      toolUrl: matched['tool_url'] as String,
      credit: matched['credit'] is num
          ? (matched['credit'] as num).round()
          : 10,
      description: matched['description'] is String
          ? matched['description'] as String
          : _primaryDescription(mode),
      inputProperties: _primaryInputProperties(mode),
      fromRecommendation: true,
    );
  }

  SeedanceRequestPreview buildRequestPreview({
    required ImageCreateMode mode,
    required String prompt,
    required ImageMetadataState metadata,
    required List<Attachment> attachments,
    required String baseUrl,
    SeedanceTool? tool,
  }) {
    final resolvedTool = tool ?? _fallbackImageTool(baseUrl, mode);
    final params = switch (mode) {
      ImageCreateMode.textToImage => _buildTextExecuteParams(
        prompt: prompt,
        metadata: metadata,
      ),
      ImageCreateMode.imageToImage => _buildEditExecuteParams(
        prompt: prompt,
        metadata: metadata,
        attachments: attachments,
      ),
    };
    return _makePreview(resolvedTool, <String, Object?>{'params': params});
  }

  SeedanceRequestPreview _buildFallbackPreview({
    required String prompt,
    required ImageMetadataState metadata,
    required String baseUrl,
    required SeedanceTool tool,
  }) {
    final params = _buildFallbackExecuteParams(
      prompt: prompt,
      metadata: metadata,
    );
    return _makePreview(tool, <String, Object?>{'params': params});
  }

  Future<TaskExecution> execute({
    required String apiKey,
    required ImageCreateMode mode,
    required String prompt,
    required ImageMetadataState metadata,
    required List<Attachment> attachments,
    required String baseUrl,
    SeedanceTool? tool,
    bool allowFallback = false,
  }) async {
    final fallbackAllowed =
        allowFallback && mode == ImageCreateMode.textToImage;

    SeedanceTool resolvedTool;
    try {
      resolvedTool =
          tool ??
          await resolveTool(
            apiKey,
            mode: mode,
            baseUrl: baseUrl,
            allowFallback: fallbackAllowed,
          );
    } on Exception {
      if (fallbackAllowed) {
        resolvedTool = await _resolveFallbackTool(apiKey, baseUrl: baseUrl);
      } else {
        rethrow;
      }
    }

    final isFallback =
        resolvedTool.toolName == 'xl_dumplingai_generate_ai_image';
    final preview = isFallback
        ? _buildFallbackPreview(
            prompt: prompt,
            metadata: metadata,
            baseUrl: baseUrl,
            tool: resolvedTool,
          )
        : buildRequestPreview(
            mode: mode,
            prompt: prompt,
            metadata: metadata,
            attachments: attachments,
            baseUrl: baseUrl,
            tool: resolvedTool,
          );

    Map<String, Object?> response;
    try {
      response = await _clientForBaseUrl(
        baseUrl,
      ).post(resolvedTool.toolUrl, apiKey, preview.body);
    } on Exception catch (error) {
      if (fallbackAllowed && !isFallback) {
        final fallbackTool = await _resolveFallbackTool(
          apiKey,
          baseUrl: baseUrl,
        );
        final fallbackPreview = _buildFallbackPreview(
          prompt: prompt,
          metadata: metadata,
          baseUrl: baseUrl,
          tool: fallbackTool,
        );
        try {
          response = await _clientForBaseUrl(
            baseUrl,
          ).post(fallbackTool.toolUrl, apiKey, fallbackPreview.body);
          final result = parseAgentEarthAsyncResult(response['result']);
          final responseUrl = _firstStringFromMap(result, ['response_url']);
          if (responseUrl == null) {
            throw TaskExecutionException(
              '备用工具执行成功，但未返回 response_url。',
              requestPreview: fallbackPreview,
            );
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

  Future<ImagePolledResult> poll({
    required String apiKey,
    required String responseUrl,
    required String baseUrl,
  }) async {
    late final _ImagePollHttpResult pollResponse;
    try {
      pollResponse = await _requestPollUrl(
        apiKey: apiKey,
        responseUrl: responseUrl,
        baseUrl: baseUrl,
      );
    } on ApiClientException catch (error) {
      return ImagePolledResult(
        status: TaskStatus.failure,
        progress: 0,
        requestPreview: buildPollRequestPreview(responseUrl, baseUrl: baseUrl),
        responsePreview: _prettyJson({'error_msg': error.message}),
        imageUrls: const [],
        statusDetail: '查询失败',
        lastError: error.message,
      );
    }

    var response = pollResponse.response;
    var result = parseAgentEarthAsyncResult(response['result']);
    var imageUrls = _mergeImageUrlLists([
      _extractImageUrls(result),
      _extractImageUrlsFromRawResponse(response),
    ]);
    final rawStatus = result['status'] is String
        ? result['status'] as String
        : null;
    final failure = _extractFailureDetail(result);
    final responseUrlFromResult = _firstStringFromMap(result, ['response_url']);
    final shouldRetryFinalResult =
        imageUrls.isEmpty && failure == null && _isCompletedStatus(rawStatus);

    final finalUrl = (responseUrlFromResult?.trim().isNotEmpty ?? false)
        ? responseUrlFromResult!.trim()
        : responseUrl;

    var requestPreview = pollResponse.requestPreview;
    if (shouldRetryFinalResult) {
      final finalPreview = buildPollRequestPreview(finalUrl, baseUrl: baseUrl);
      requestPreview = _combinePollRequestPreviews([
        pollResponse.requestPreview,
        finalPreview,
      ]);

      try {
        final finalResponse = await _requestPollUrl(
          apiKey: apiKey,
          responseUrl: finalUrl,
          baseUrl: baseUrl,
        );
        final finalResult = parseAgentEarthAsyncResult(
          finalResponse.response['result'],
        );
        final finalImageUrls = _mergeImageUrlLists([
          _extractImageUrls(finalResult),
          _extractImageUrlsFromRawResponse(finalResponse.response),
        ]);
        if (finalImageUrls.isNotEmpty) {
          response = _combinePollResponses(
            statusResponse: response,
            finalResponse: finalResponse.response,
          );
          result = {...result, 'final_result': finalResult};
          imageUrls = finalImageUrls;
        } else {
          response = _combinePollResponses(
            statusResponse: response,
            finalResponse: finalResponse.response,
          );
          result = {...result, 'final_result': finalResult};
          imageUrls = _mergeImageUrlLists([
            _extractImageUrls(result),
            _extractImageUrlsFromRawResponse(response),
          ]);
        }
      } on ApiClientException catch (error) {
        return ImagePolledResult(
          status: TaskStatus.failure,
          progress: 0,
          requestPreview: requestPreview,
          responsePreview: _prettyJson(
            _combinePollResponses(
              statusResponse: response,
              finalResponse: {'error_msg': error.message},
            ),
          ),
          imageUrls: const [],
          statusDetail: '结果查询失败',
          lastError: error.message,
        );
      }
    }

    final mergedFailure = _extractFailureDetail(result);
    final status = _normalizeImageStatus(
      result['status'] is String ? result['status'] as String : rawStatus,
      imageUrls,
    );

    return ImagePolledResult(
      status: status,
      progress: _normalizeImageProgress(result['progress'], status),
      requestPreview: requestPreview,
      responsePreview: _prettyJson(response),
      imageUrls: imageUrls,
      statusDetail: _normalizeImageStatusDetail(
        result['status'] is String ? result['status'] as String : rawStatus,
        imageUrls,
        mergedFailure,
      ),
      lastError: mergedFailure?.message,
      hasAnomaly:
          mergedFailure == null &&
          imageUrls.isEmpty &&
          _isCompletedStatus(
            result['status'] is String ? result['status'] as String : rawStatus,
          ),
      anomalyMessage:
          mergedFailure == null &&
              imageUrls.isEmpty &&
              _isCompletedStatus(
                result['status'] is String
                    ? result['status'] as String
                    : rawStatus,
              )
          ? '上游状态已完成，但没有返回图片 URL，可手动刷新重试。'
          : null,
    );
  }

  Future<_ImagePollHttpResult> _requestPollUrl({
    required String apiKey,
    required String responseUrl,
    required String baseUrl,
  }) async {
    final requestPreview = buildPollRequestPreview(
      responseUrl,
      baseUrl: baseUrl,
    );
    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/execute?tool_name=xl_get_response',
      apiKey,
      {
        'params': {'response_url': responseUrl},
      },
    );
    return _ImagePollHttpResult(
      requestPreview: requestPreview,
      response: response,
    );
  }

  String _combinePollRequestPreviews(List<String> previews) {
    final parsed = <Object?>[];
    for (final preview in previews) {
      parsed.add(_parseEmbeddedJson(preview));
    }
    return _prettyJson({'requests': parsed});
  }

  Map<String, Object?> _combinePollResponses({
    required Map<String, Object?> statusResponse,
    required Map<String, Object?> finalResponse,
  }) {
    return {
      'status_query': statusResponse,
      'final_result_query': finalResponse,
    };
  }

  // -- private helpers --

  String _primaryToolName(ImageCreateMode mode) => switch (mode) {
    ImageCreateMode.textToImage => 'xl_falai_post_openai_gpt_image_2',
    ImageCreateMode.imageToImage => 'xl_falai_post_openai_gpt_image_2_edit',
  };

  String _recommendQuery(ImageCreateMode mode) => switch (mode) {
    ImageCreateMode.textToImage => 'GPT Image 2 text to image generation',
    ImageCreateMode.imageToImage => 'gpt_image_2 编辑图片 image edit',
  };

  String _primaryDescription(ImageCreateMode mode) => switch (mode) {
    ImageCreateMode.textToImage => 'GPT Image 2',
    ImageCreateMode.imageToImage => 'GPT Image 2 Edit',
  };

  Set<String> _primaryInputProperties(ImageCreateMode mode) => switch (mode) {
    ImageCreateMode.textToImage => const {
      'prompt',
      'image_size',
      'num_images',
      'output_format',
      'quality',
      'sync_mode',
    },
    ImageCreateMode.imageToImage => const {
      'prompt',
      'image_urls',
      'image_size',
      'num_images',
      'output_format',
      'quality',
      'sync_mode',
      'mask_url',
    },
  };

  SeedanceTool _fallbackImageTool(String baseUrl, ImageCreateMode mode) {
    final toolName = _primaryToolName(mode);
    return SeedanceTool(
      toolName: toolName,
      toolUrl: '$baseUrl/tool/execute?tool_name=$toolName',
      credit: 10,
      description: _primaryDescription(mode),
      inputProperties: _primaryInputProperties(mode),
      fromRecommendation: false,
    );
  }

  Future<SeedanceTool> _resolveFallbackTool(
    String apiKey, {
    required String baseUrl,
  }) async {
    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/recommend',
      apiKey,
      {'query': 'DumplingAI image generation', 'limit': 5},
    );
    final tools = response['tools'];
    if (tools is! List) {
      throw const ApiClientException('AgentEarth 推荐未返回备用工具。');
    }
    for (final item in tools) {
      if (item is! Map) continue;
      final tool = Map<String, Object?>.from(item);
      final toolUrl = tool['tool_url'];
      if (toolUrl is String &&
          toolUrl.contains('tool_name=xl_dumplingai_generate_ai_image')) {
        return SeedanceTool(
          toolName: 'xl_dumplingai_generate_ai_image',
          toolUrl: toolUrl,
          credit: tool['credit'] is num ? (tool['credit'] as num).round() : 10,
          description: tool['description'] is String
              ? tool['description'] as String
              : 'DumplingAI Image',
          inputProperties: const {
            'prompt',
            'height',
            'width',
            'model',
            'style',
          },
          fromRecommendation: true,
        );
      }
    }
    throw const ApiClientException('AgentEarth 推荐未返回备用工具。');
  }

  Map<String, Object?> _buildTextExecuteParams({
    required String prompt,
    required ImageMetadataState metadata,
  }) {
    final imageSize =
        aspectRatioToImageSize[metadata.aspectRatio] ?? 'square_hd';
    return _compactObject({
      'prompt': prompt,
      'image_size': imageSize,
      'num_images': metadata.numImages,
      'output_format': metadata.outputFormat,
      'quality': metadata.quality,
      'sync_mode': false,
    });
  }

  Map<String, Object?> _buildEditExecuteParams({
    required String prompt,
    required ImageMetadataState metadata,
    required List<Attachment> attachments,
  }) {
    final imageSize =
        aspectRatioToImageSize[metadata.aspectRatio] ?? 'square_hd';
    final imageUrls = attachments
        .map((attachment) => attachment.url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    return _compactObject({
      'prompt': prompt,
      'image_urls': imageUrls,
      'image_size': imageSize,
      'num_images': metadata.numImages,
      'output_format': metadata.outputFormat,
      'quality': metadata.quality,
      'sync_mode': false,
    });
  }

  Map<String, Object?> _buildFallbackExecuteParams({
    required String prompt,
    required ImageMetadataState metadata,
  }) {
    final pixels =
        _ratioToPixels[metadata.aspectRatio] ?? _ratioToPixels['1:1']!;
    return _compactObject({
      'prompt': prompt,
      'width': pixels.$1,
      'height': pixels.$2,
    });
  }

  SeedanceRequestPreview _makePreview(
    SeedanceTool tool,
    Map<String, Object?> body,
  ) {
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

  List<String> _extractImageUrls(Map<String, Object?> result) {
    final urls = <String>[];
    _collectImageUrls(result, urls);
    return _mergeImageUrlLists([urls]);
  }

  List<String> _extractImageUrlsFromRawResponse(Map<String, Object?> response) {
    final urls = <String>[];
    _collectImageUrls(response, urls);
    return _mergeImageUrlLists([urls]);
  }

  List<String> _mergeImageUrlLists(List<List<String>> lists) {
    final merged = <String>[];
    final seen = <String>{};
    for (final list in lists) {
      for (final item in list) {
        final normalized = item.trim();
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        merged.add(normalized);
      }
    }
    return merged;
  }

  void _collectImageUrls(Object? value, List<String> urls) {
    final parsed = _parseEmbeddedJson(value);
    if (parsed is List) {
      for (final item in parsed) {
        _collectImageUrls(item, urls);
      }
    } else if (parsed is Map) {
      final map = Map<String, Object?>.from(parsed);
      const directKeys = ['image_url', 'url', 'download_url', 'file_url'];
      for (final key in directKeys) {
        final candidate = map[key];
        if (candidate is String && _looksLikeImageUrl(candidate)) {
          urls.add(candidate.trim());
        }
      }
      final images = map['images'];
      if (images is List) {
        for (final img in images) {
          if (img is String && _looksLikeImageUrl(img)) {
            urls.add(img.trim());
          } else if (img is Map) {
            final imgMap = Map<String, Object?>.from(img);
            final url = imgMap['url'];
            if (url is String && _looksLikeImageUrl(url)) {
              urls.add(url.trim());
            }
          }
        }
      }
      for (final entry in map.entries) {
        if (entry.key == 'images') continue;
        if (directKeys.contains(entry.key)) continue;
        _collectImageUrls(entry.value, urls);
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
    if (_isCompletedStatus(text)) {
      return TaskStatus.inProgress;
    }
    if (['FAILED', 'FAILURE', 'ERROR', 'CANCELED'].contains(text)) {
      return TaskStatus.failure;
    }
    if (['IN_PROGRESS', 'RUNNING', 'PROCESSING'].contains(text)) {
      return TaskStatus.inProgress;
    }
    return TaskStatus.submitted;
  }

  int _normalizeImageProgress(Object? progress, TaskStatus status) {
    if (progress is num && progress.isFinite) {
      return progress.round().clamp(0, 100);
    }
    if (progress is String) {
      final parsed = num.tryParse(progress.replaceAll('%', '').trim());
      if (parsed != null && parsed.isFinite) {
        return parsed.round().clamp(0, 100);
      }
    }
    if (status == TaskStatus.success) return 100;
    if (status == TaskStatus.failure) return 0;
    if (status == TaskStatus.inProgress) return 68;
    return 10;
  }

  String? _normalizeImageStatusDetail(
    String? rawStatus,
    List<String> imageUrls,
    _FailureDetail? failure,
  ) {
    if (imageUrls.isNotEmpty) {
      return 'SUCCESS (${imageUrls.length} images)';
    }
    if (failure != null) return failure.message;
    if (_isCompletedStatus(rawStatus)) {
      return 'COMPLETED，等待结果文件返回';
    }
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

  _FailureDetail? _extractFailureDetail(Object? value) {
    final parsed = _parseEmbeddedJson(value);
    if (parsed is List) {
      for (final item in parsed) {
        final detail = _extractFailureDetail(item);
        if (detail != null) return detail;
      }
      return null;
    }
    if (parsed is! Map) return null;
    final map = Map<String, Object?>.from(parsed);

    final detailItems = map['detail'];
    if (detailItems is List) {
      for (final entry in detailItems) {
        if (entry is! Map) continue;
        final entryMap = Map<String, Object?>.from(entry);
        final rawMessage = _firstStringFromMap(entryMap, [
          'msg',
          'message',
          'detail',
        ]);
        final rawType = _firstStringFromMap(entryMap, ['type']);
        final ctx = entryMap['ctx'];
        final extraInfo = ctx is Map
            ? Map<String, Object?>.from(ctx)['extra_info']
            : null;
        final reason = extraInfo is Map
            ? _firstStringFromMap(Map<String, Object?>.from(extraInfo), [
                'reason',
              ])
            : null;
        if (rawMessage != null) {
          return _FailureDetail(
            code: _normalizeFailureCode(rawType, reason),
            message: _normalizeFailureMessage(rawMessage),
          );
        }
      }
    }

    final errorMessage = _firstStringFromMap(map, [
      'error_msg',
      'message',
      'error',
    ]);
    if (errorMessage != null) {
      return _FailureDetail(
        code: _normalizeFailureCode(
          _firstStringFromMap(map, ['type', 'code']),
          null,
        ),
        message: _normalizeFailureMessage(errorMessage),
      );
    }

    for (final child in map.values) {
      final detail = _extractFailureDetail(child);
      if (detail != null) return detail;
    }
    return null;
  }

  String _normalizeFailureMessage(String message) {
    return message;
  }

  String? _normalizeFailureCode(String? type, String? reason) {
    final normalizedType = type?.trim().toUpperCase() ?? '';
    final normalizedReason = reason?.trim().toUpperCase() ?? '';
    if (normalizedType.isNotEmpty && normalizedReason.isNotEmpty) {
      return '$normalizedType / $normalizedReason';
    }
    if (normalizedType.isNotEmpty) return normalizedType;
    if (normalizedReason.isNotEmpty) return normalizedReason;
    return null;
  }

  bool _isCompletedStatus(String? status) {
    final text = status?.toUpperCase();
    return ['COMPLETED', 'SUCCESS', 'SUCCEEDED', 'OK'].contains(text);
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

  String _prettyJson(Object? value) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  }
}

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

class _FailureDetail {
  const _FailureDetail({this.code, required this.message});

  final String? code;
  final String message;
}

class _ImagePollHttpResult {
  const _ImagePollHttpResult({
    required this.requestPreview,
    required this.response,
  });

  final String requestPreview;
  final Map<String, Object?> response;
}
