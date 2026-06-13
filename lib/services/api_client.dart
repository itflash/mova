import 'dart:async';
import 'dart:convert';
import 'dart:io';

const agentEarthDefaultBaseUrl = 'https://agentearth.ai/agent-api/v1';

String normalizeAgentEarthBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return agentEarthDefaultBaseUrl;
  return trimmed.replaceAll(RegExp(r'/+$'), '');
}

class ApiClient {
  ApiClient({HttpClient? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? HttpClient(),
      _baseUrl = normalizeAgentEarthBaseUrl(
        baseUrl ?? agentEarthDefaultBaseUrl,
      );

  final HttpClient _httpClient;
  final String _baseUrl;

  Future<Map<String, Object?>> post(
    String pathOrUrl,
    String apiKey,
    Map<String, Object?> body,
  ) async {
    final uri = Uri.parse(_toAbsoluteUrl(pathOrUrl));
    final request = await _httpClient
        .postUrl(uri)
        .timeout(const Duration(seconds: 30));
    request.headers.contentType = ContentType.json;
    request.headers.set('X-Api-Key', apiKey.trim());
    request.write(jsonEncode(body));

    final response = await request.close().timeout(const Duration(seconds: 90));
    final responseText = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiClientException(
        responseText.isEmpty
            ? 'AgentEarth 请求失败（HTTP ${response.statusCode}）'
            : responseText,
      );
    }

    final decoded = jsonDecode(responseText);
    if (decoded is! Map<String, Object?>) {
      throw const ApiClientException('AgentEarth 返回了无法解析的响应。');
    }

    final errorNo = decoded['error_no'];
    if (errorNo is num && errorNo != 0) {
      final message = decoded['error_msg'];
      throw ApiClientException(
        message is String && message.trim().isNotEmpty
            ? message
            : 'AgentEarth 返回失败。',
      );
    }

    return decoded;
  }

  String _toAbsoluteUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    return '$_baseUrl${pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl'}';
  }
}

class ApiClientException implements Exception {
  const ApiClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
