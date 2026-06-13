import 'dart:convert';

import '../app/models.dart';
import 'api_client.dart';

class SeedanceService {
  // ignore: prefer_initializing_formals
  SeedanceService({ApiClient? client}) : _client = client;

  final ApiClient? _client;

  ApiClient _clientForBaseUrl(String baseUrl) =>
      _client ?? ApiClient(baseUrl: baseUrl);

  Future<SeedanceTool> resolveTool(
    String apiKey,
    ModeId mode, {
    required String baseUrl,
  }) async {
    final fallback = fallbackToolForMode(mode, baseUrl: baseUrl);
    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/recommend',
      apiKey,
      {'query': _toolQueryForMode(mode), 'limit': 10},
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
      if (toolUrl is String &&
          toolUrl.contains('tool_name=${fallback.toolName}')) {
        matched = tool;
        break;
      }
    }

    final toolUrl = matched?['tool_url'];
    if (matched == null || toolUrl is! String || toolUrl.trim().isEmpty) {
      throw ApiClientException(
        'AgentEarth 推荐未返回 ${fallback.toolName} 的完整 tool_url，已阻止扣费执行。',
      );
    }

    final inputSchema = matched['input_schema'];
    final properties = inputSchema is Map ? inputSchema['properties'] : null;
    return SeedanceTool(
      toolName: fallback.toolName,
      toolUrl: toolUrl,
      credit: matched['credit'] is num
          ? (matched['credit'] as num).round()
          : fallback.credit,
      description: matched['description'] is String
          ? matched['description'] as String
          : fallback.description,
      inputProperties: properties is Map
          ? properties.keys.map((key) => key.toString()).toSet()
          : fallback.inputProperties,
      fromRecommendation: true,
    );
  }

  SeedanceRequestPreview buildRequestPreview({
    required ModeId mode,
    required String prompt,
    required MetadataState metadata,
    required List<Attachment> attachments,
    required String baseUrl,
    SeedanceTool? tool,
  }) {
    final resolvedTool = tool ?? fallbackToolForMode(mode, baseUrl: baseUrl);
    final params = buildExecuteParams(
      prompt: prompt,
      metadata: metadata,
      attachments: attachments,
      inputProperties: resolvedTool.inputProperties,
    );
    final body = <String, Object?>{'params': params};
    return SeedanceRequestPreview(
      toolName: resolvedTool.toolName,
      toolUrl: resolvedTool.toolUrl,
      body: body,
      prettyJson: _prettyJson({
        'tool_name': resolvedTool.toolName,
        'tool_url': resolvedTool.toolUrl,
        ...body,
      }),
    );
  }

  Future<TaskExecution> execute({
    required String apiKey,
    required ModeId mode,
    required String prompt,
    required MetadataState metadata,
    required List<Attachment> attachments,
    required String baseUrl,
    SeedanceTool? tool,
  }) async {
    final resolvedTool =
        tool ?? await resolveTool(apiKey, mode, baseUrl: baseUrl);
    final preview = buildRequestPreview(
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
      throw TaskExecutionException(
        error.toString().replaceFirst('Exception: ', ''),
        requestPreview: preview,
      );
    }

    final result = parseAgentEarthAsyncResult(response['result']);
    final responseUrl = _firstStringFromMap(result, ['response_url']);
    final statusUrl = _firstStringFromMap(result, ['status_url']);
    if (responseUrl == null) {
      throw TaskExecutionException(
        'AgentEarth 执行成功，但未返回 response_url，无法继续轮询结果。',
        requestPreview: preview,
      );
    }

    return TaskExecution(
      responseUrl: responseUrl,
      statusUrl: statusUrl,
      toolName: resolvedTool.toolName,
      credit: resolvedTool.credit,
      requestPreview: preview,
      responsePreview: _prettyJson(response),
    );
  }

  Future<TaskPolledResult> poll({
    required String apiKey,
    required String responseUrl,
    required String baseUrl,
    String? finalResponseUrl,
  }) async {
    late final _PollHttpResult pollResponse;
    try {
      pollResponse = await _requestPollUrl(
        apiKey: apiKey,
        responseUrl: responseUrl,
        baseUrl: baseUrl,
      );
    } on ApiClientException catch (error) {
      return TaskPolledResult(
        status: TaskStatus.failure,
        progress: 0,
        requestPreview: _buildPollRequestPreview(responseUrl, baseUrl),
        statusDetail: '查询失败',
        lastError: error.message,
        responsePreview: _prettyJson({
          'error_no': -1,
          'error_msg': error.message,
          'handled_as': 'FAILURE',
        }),
      );
    }
    var response = pollResponse.response;
    var result = parseAgentEarthAsyncResult(response['result']);
    var videoUrl = _extractVideoUrl(result);
    final responseUrlFromResult = _firstStringFromMap(result, ['response_url']);
    final rawStatus = result['status'] is String
        ? result['status'] as String
        : null;
    final isCompleteWithoutVideo =
        videoUrl == null && _isCompletedStatus(rawStatus);
    final finalUrl = finalResponseUrl?.trim().isNotEmpty == true
        ? finalResponseUrl!.trim()
        : responseUrlFromResult;

    if (isCompleteWithoutVideo &&
        finalUrl != null &&
        finalUrl.trim().isNotEmpty &&
        finalUrl != responseUrl) {
      try {
        final finalResponse = await _requestPollUrl(
          apiKey: apiKey,
          responseUrl: finalUrl,
          baseUrl: baseUrl,
        );
        final finalResult = parseAgentEarthAsyncResult(
          finalResponse.response['result'],
        );
        final finalVideoUrl = _extractVideoUrl(finalResult);
        if (finalVideoUrl != null) {
          response = finalResponse.response;
          result = finalResult;
          videoUrl = finalVideoUrl;
        } else {
          response = _combinePollResponses(
            statusResponse: response,
            finalResponse: finalResponse.response,
          );
          result = {...result, 'final_result': finalResult};
        }
      } on ApiClientException catch (error) {
        return TaskPolledResult(
          status: TaskStatus.failure,
          progress: 0,
          requestPreview: _combinePollRequestPreviews([
            pollResponse.requestPreview,
            _buildPollRequestPreview(finalUrl, baseUrl),
          ]),
          statusDetail: '结果查询失败',
          lastError: error.message,
          responsePreview: _prettyJson(
            _combinePollResponses(
              statusResponse: response,
              finalResponse: {
                'error_no': -1,
                'error_msg': error.message,
                'handled_as': 'FAILURE',
              },
            ),
          ),
        );
      }
    }

    final requestPreview =
        isCompleteWithoutVideo && finalUrl != null && finalUrl != responseUrl
        ? _combinePollRequestPreviews([
            pollResponse.requestPreview,
            _buildPollRequestPreview(finalUrl, baseUrl),
          ])
        : pollResponse.requestPreview;
    videoUrl = _extractVideoUrl(result);
    final failure = _extractFailureDetail(result);
    final anomaly = _extractCompletionAnomaly(result, videoUrl, failure);
    final status = _normalizeStatus(
      result['status'],
      videoUrl,
      failure,
      hasCompletionAnomaly: anomaly != null,
    );
    final progress = _normalizeProgress(
      result['progress'],
      status,
      result['queue_position'],
    );
    final nextRawStatus = result['status'] is String
        ? result['status'] as String
        : rawStatus;

    return TaskPolledResult(
      status: status,
      progress: progress,
      requestPreview: requestPreview,
      videoUrl: videoUrl,
      statusDetail: status == TaskStatus.success && videoUrl != null
          ? 'SUCCESS'
          : status == TaskStatus.failure
          ? failure?.code ?? nextRawStatus ?? 'FAILURE'
          : _isCompletedStatus(nextRawStatus)
          ? 'COMPLETED，等待结果文件返回'
          : nextRawStatus,
      lastError: status == TaskStatus.failure
          ? failure?.message ?? nextRawStatus ?? '上游执行失败。'
          : null,
      responsePreview: _prettyJson(response),
      hasAnomaly: anomaly != null,
      anomalyMessage: anomaly,
    );
  }

  Future<_PollHttpResult> _requestPollUrl({
    required String apiKey,
    required String responseUrl,
    required String baseUrl,
  }) async {
    final requestPreview = _buildPollRequestPreview(responseUrl, baseUrl);
    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/execute?tool_name=xl_get_response',
      apiKey,
      {
        'params': {'response_url': responseUrl},
      },
    );
    return _PollHttpResult(requestPreview: requestPreview, response: response);
  }
}

String buildPollRequestPreview(String responseUrl, {String? baseUrl}) =>
    _buildPollRequestPreview(responseUrl, baseUrl ?? agentEarthDefaultBaseUrl);

SeedanceTool fallbackToolForMode(ModeId mode, {String? baseUrl}) {
  final resolvedBaseUrl = normalizeAgentEarthBaseUrl(
    baseUrl ?? agentEarthDefaultBaseUrl,
  );
  switch (mode) {
    case ModeId.text:
      return SeedanceTool(
        toolName: 'xl_falai_post_seedance_2_text_to_video',
        toolUrl:
            '$resolvedBaseUrl/tool/execute?tool_name=xl_falai_post_seedance_2_text_to_video',
        credit: 500,
        description: 'Seedance2 文本生视频',
        inputProperties: {
          'prompt',
          'duration',
          'resolution',
          'aspect_ratio',
          'seed',
          'generate_audio',
        },
        fromRecommendation: false,
      );
    case ModeId.firstFrame:
    case ModeId.firstLast:
      return SeedanceTool(
        toolName: 'xl_falai_post_seedance_2_image_to_video',
        toolUrl:
            '$resolvedBaseUrl/tool/execute?tool_name=xl_falai_post_seedance_2_image_to_video',
        credit: 500,
        description: 'Seedance2 首帧/首尾帧图生视频',
        inputProperties: {
          'prompt',
          'image_url',
          'end_image_url',
          'duration',
          'resolution',
          'aspect_ratio',
          'seed',
          'generate_audio',
        },
        fromRecommendation: false,
      );
    case ModeId.reference:
      return SeedanceTool(
        toolName: 'xl_falai_post_seedance_2_reference_to_video',
        toolUrl:
            '$resolvedBaseUrl/tool/execute?tool_name=xl_falai_post_seedance_2_reference_to_video',
        credit: 500,
        description: 'Seedance2 参考素材生成',
        inputProperties: {
          'prompt',
          'image_urls',
          'video_urls',
          'audio_urls',
          'duration',
          'resolution',
          'aspect_ratio',
          'seed',
          'generate_audio',
        },
        fromRecommendation: false,
      );
  }
}

Map<String, Object?> buildExecuteParams({
  required String prompt,
  required MetadataState metadata,
  required List<Attachment> attachments,
  required Set<String> inputProperties,
}) {
  final uploaded = attachments
      .where((item) => item.url.trim().isNotEmpty)
      .toList();
  final firstFrame =
      _firstWhereOrNull(
        uploaded,
        (item) => item.role == AttachmentRole.firstFrame,
      ) ??
      _firstWhereOrNull(
        uploaded,
        (item) => item.role == AttachmentRole.referenceImage,
      );
  final lastFrame = _firstWhereOrNull(
    uploaded,
    (item) => item.role == AttachmentRole.lastFrame,
  );
  final referenceImagesByRole = uploaded
      .where((item) => item.role == AttachmentRole.referenceImage)
      .toList();
  final referenceVideosByRole = uploaded
      .where((item) => item.role == AttachmentRole.referenceVideo)
      .toList();
  final referenceAudiosByRole = uploaded
      .where((item) => item.role == AttachmentRole.referenceAudio)
      .toList();

  final promptBuild = _buildSubmissionPrompt(prompt, attachments: uploaded);
  final referenceImages = _mergeMentionOrderedAttachments(
    promptBuild.imageAttachments,
    referenceImagesByRole,
  );
  final referenceVideos = _mergeMentionOrderedAttachments(
    promptBuild.videoAttachments,
    referenceVideosByRole,
  );
  final referenceAudios = _mergeMentionOrderedAttachments(
    promptBuild.audioAttachments,
    referenceAudiosByRole,
  );
  final allParams = <String, Object?>{
    'prompt': promptBuild.prompt,
    'duration': metadata.duration.isEmpty || metadata.duration == '-1'
        ? 'auto'
        : metadata.duration,
    'resolution': metadata.resolution == '1080p' ? '720p' : metadata.resolution,
    'aspect_ratio': metadata.ratio == 'adaptive' ? 'auto' : metadata.ratio,
    'seed': metadata.seed.trim().isEmpty ? null : num.tryParse(metadata.seed),
    'generate_audio': metadata.generateAudio,
    'image_url': firstFrame?.url,
    'end_image_url': lastFrame?.url,
    'image_urls': referenceImages.map((item) => item.url).toList(),
    'video_urls': referenceVideos.map((item) => item.url).toList(),
    'audio_urls': referenceAudios.map((item) => item.url).toList(),
  };

  final filtered = inputProperties.isEmpty
      ? allParams
      : Map.fromEntries(
          allParams.entries.where(
            (entry) => inputProperties.contains(entry.key),
          ),
        );
  return _compactObject(filtered);
}

Map<String, Object?> parseAgentEarthAsyncResult(Object? value) {
  final parsed = _parseEmbeddedJson(value);
  if (parsed is Map) {
    return Map<String, Object?>.from(parsed);
  }

  if (parsed is List) {
    for (final item in parsed) {
      if (item is Map && item['type'] == 'text' && item['text'] is String) {
        final textParsed = _parseEmbeddedJson(item['text']);
        if (textParsed is Map) {
          return Map<String, Object?>.from(textParsed);
        }
      }
      if (item is Map) {
        return Map<String, Object?>.from(item);
      }
    }
  }

  return {'value': parsed};
}

String _toolQueryForMode(ModeId mode) {
  switch (mode) {
    case ModeId.text:
      return 'Seedance2 文本生视频 text to video';
    case ModeId.firstFrame:
      return 'Seedance2 首帧图生视频 image to video first frame';
    case ModeId.firstLast:
      return 'Seedance2 首尾帧图生视频 image to video first last frame';
    case ModeId.reference:
      return 'Seedance2 参考素材生成 reference image video audio to video';
  }
}

String _buildPollRequestPreview(String responseUrl, String baseUrl) {
  return _prettyJson({
    'tool_name': 'xl_get_response',
    'tool_url': '$baseUrl/tool/execute?tool_name=xl_get_response',
    'params': {'response_url': responseUrl},
  });
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
  return {'status_query': statusResponse, 'final_result_query': finalResponse};
}

_PromptBuildResult _buildSubmissionPrompt(
  String prompt, {
  required List<Attachment> attachments,
}) {
  final imageAttachments = <Attachment>[];
  final videoAttachments = <Attachment>[];
  final audioAttachments = <Attachment>[];
  final imageTokenById = <String, String>{};
  final videoTokenById = <String, String>{};
  final audioTokenById = <String, String>{};

  String replacementFor(Attachment attachment) {
    switch (attachment.kind) {
      case AttachmentKind.image:
        return imageTokenById.putIfAbsent(attachment.id, () {
          imageAttachments.add(attachment);
          return '@Image${imageAttachments.length}';
        });
      case AttachmentKind.video:
        return videoTokenById.putIfAbsent(attachment.id, () {
          videoAttachments.add(attachment);
          return '@Video${videoAttachments.length}';
        });
      case AttachmentKind.audio:
        return audioTokenById.putIfAbsent(attachment.id, () {
          audioAttachments.add(attachment);
          return '@Audio${audioAttachments.length}';
        });
    }
  }

  final replacedPrompt = prompt.replaceAllMapped(RegExp(r'@\{([^}]+)\}'), (
    match,
  ) {
    final label = match.group(1);
    final attachment = _firstWhereOrNull(
      attachments,
      (item) => item.label == label && item.url.trim().isNotEmpty,
    );
    if (attachment == null) {
      return match.group(0) ?? '';
    }
    return replacementFor(attachment);
  });

  return _PromptBuildResult(
    prompt: replacedPrompt.trim(),
    imageAttachments: imageAttachments,
    videoAttachments: videoAttachments,
    audioAttachments: audioAttachments,
  );
}

List<Attachment> _mergeMentionOrderedAttachments(
  List<Attachment> mentioned,
  List<Attachment> selected,
) {
  final result = <Attachment>[];
  final seen = <String>{};
  for (final attachment in [...mentioned, ...selected]) {
    if (seen.add(attachment.id)) {
      result.add(attachment);
    }
  }
  return result;
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

String? _firstStringFromMap(Map<String, Object?> value, List<String> keys) {
  for (final key in keys) {
    final item = value[key];
    if (item is String && item.trim().isNotEmpty) {
      return item;
    }
  }
  return null;
}

String? _extractVideoUrl(Map<String, Object?> result) {
  return _extractVideoUrlFromValue(result);
}

String? _extractVideoUrlFromValue(Object? value, {String? parentKey}) {
  final parsed = _parseEmbeddedJson(value);
  if (parsed is List) {
    for (final item in parsed) {
      final url = _extractVideoUrlFromValue(item, parentKey: parentKey);
      if (url != null) return url;
    }
    return null;
  }
  if (parsed is! Map) {
    if (parsed is String && _looksLikeDownloadUrl(parsed, parentKey)) {
      return parsed.trim();
    }
    return null;
  }

  final directKeys = [
    'video_url',
    'download_url',
    'media_url',
    'file_url',
    'url',
  ];
  for (final key in directKeys) {
    final candidate = parsed[key];
    if (candidate is String && _looksLikeDownloadUrl(candidate, key)) {
      return candidate.trim();
    }
  }

  for (final entry in parsed.entries) {
    final key = entry.key.toString();
    if (_isQueueControlUrlKey(key)) continue;
    final url = _extractVideoUrlFromValue(entry.value, parentKey: key);
    if (url != null) return url;
  }
  return null;
}

bool _looksLikeDownloadUrl(String value, String? key) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return false;
  }
  final normalizedKey = key?.toLowerCase() ?? '';
  if (_isQueueControlUrlKey(normalizedKey)) return false;
  final lower = trimmed.toLowerCase();
  return normalizedKey.contains('video') ||
      normalizedKey.contains('download') ||
      normalizedKey.contains('media') ||
      normalizedKey.contains('file') ||
      lower.contains('.mp4') ||
      lower.contains('.mov') ||
      lower.contains('.webm') ||
      lower.contains('/video') ||
      lower.contains('/videos');
}

bool _isQueueControlUrlKey(String key) {
  final normalized = key.toLowerCase();
  return normalized == 'response_url' ||
      normalized == 'status_url' ||
      normalized == 'cancel_url';
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

  final detailItems = parsed['detail'];
  if (detailItems is List) {
    for (final entry in detailItems) {
      if (entry is! Map) continue;
      final rawMessage = _firstString([
        entry['msg'],
        entry['message'],
        entry['detail'],
      ]);
      final rawType = _firstString([entry['type']]);
      final ctx = entry['ctx'];
      final extraInfo = ctx is Map ? ctx['extra_info'] : null;
      final reason = extraInfo is Map
          ? _firstString([extraInfo['reason']])
          : null;
      if (rawMessage != null) {
        return _FailureDetail(
          code: _normalizeFailureCode(rawType, reason),
          message: _normalizeFailureMessage(rawMessage),
        );
      }
    }
  }

  final errorMessage = _firstString([
    parsed['error_msg'],
    parsed['message'],
    parsed['error'],
  ]);
  if (errorMessage != null) {
    return _FailureDetail(
      code: _normalizeFailureCode(
        _firstString([parsed['type'], parsed['code']]),
        null,
      ),
      message: _normalizeFailureMessage(errorMessage),
    );
  }

  for (final child in parsed.values) {
    final detail = _extractFailureDetail(child);
    if (detail != null) return detail;
  }
  return null;
}

String _normalizeFailureMessage(String message) {
  if (message.contains('Output audio has sensitive content.')) {
    return '输出音频包含敏感内容，任务已被上游拦截。';
  }
  if (message.contains(
    'Please check if the URL is accessible and try again.',
  )) {
    return '提供的图片链接无法下载，请检查素材 URL 是否可公开访问。';
  }
  return message;
}

String? _normalizeFailureCode(String? type, String? reason) {
  final normalizedType = type?.trim().toUpperCase();
  final normalizedReason = reason?.trim().toUpperCase();
  if (normalizedType != null &&
      normalizedType.isNotEmpty &&
      normalizedReason != null &&
      normalizedReason.isNotEmpty) {
    return '$normalizedType / $normalizedReason';
  }
  if (normalizedType != null && normalizedType.isNotEmpty) {
    return normalizedType;
  }
  if (normalizedReason != null && normalizedReason.isNotEmpty) {
    return normalizedReason;
  }
  return null;
}

TaskStatus _normalizeStatus(
  Object? status,
  String? videoUrl,
  _FailureDetail? failure, {
  bool hasCompletionAnomaly = false,
}) {
  if (videoUrl != null && videoUrl.trim().isNotEmpty) {
    return TaskStatus.success;
  }
  if (failure != null) {
    return TaskStatus.failure;
  }
  if (hasCompletionAnomaly) {
    return TaskStatus.success;
  }
  final text = status is String ? status.toUpperCase() : '';
  if (['COMPLETED', 'SUCCESS', 'SUCCEEDED', 'OK'].contains(text)) {
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

String? _extractCompletionAnomaly(
  Map<String, Object?> result,
  String? videoUrl,
  _FailureDetail? failure,
) {
  if (videoUrl != null && videoUrl.trim().isNotEmpty) {
    return null;
  }
  if (failure != null) {
    return null;
  }
  final rawStatus = result['status'] is String
      ? result['status'] as String
      : null;
  if (_isCompletedStatus(rawStatus)) {
    return '上游状态已完成，但没有返回资源 URL，可手动刷新重试。';
  }
  return null;
}

bool _isCompletedStatus(String? status) {
  final text = status?.toUpperCase();
  return ['COMPLETED', 'SUCCESS', 'SUCCEEDED', 'OK'].contains(text);
}

int _normalizeProgress(
  Object? progress,
  TaskStatus status,
  Object? queuePosition,
) {
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
  if (queuePosition is num && queuePosition >= 0) {
    return queuePosition == 0 ? 18 : 12;
  }
  return 10;
}

String? _firstString(List<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

Attachment? _firstWhereOrNull(
  List<Attachment> items,
  bool Function(Attachment item) test,
) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

class _FailureDetail {
  const _FailureDetail({this.code, required this.message});

  final String? code;
  final String message;
}

class _PollHttpResult {
  const _PollHttpResult({required this.requestPreview, required this.response});

  final String requestPreview;
  final Map<String, Object?> response;
}

class _PromptBuildResult {
  const _PromptBuildResult({
    required this.prompt,
    required this.imageAttachments,
    required this.videoAttachments,
    required this.audioAttachments,
  });

  final String prompt;
  final List<Attachment> imageAttachments;
  final List<Attachment> videoAttachments;
  final List<Attachment> audioAttachments;
}
