import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'api_client.dart';

/// AgentEarth 官方托管的临时文件通道。
///
/// 通过 `xl_file_service_get_upload_addr` 拿到预签名 uploadURL + 公网 downloadURL，
/// 然后 PUT 原始字节即可。适合"临时素材直传"的场景：用户不想把这次任务用
/// 的素材永久存到自己的对象存储时使用。
///
/// 与 `bitiful_s4_upload_service` / `qiniu_upload_service` 并列，两者互不影响。
class AgentEarthFileService {
  AgentEarthFileService({ApiClient? client, HttpClient? httpClient})
    : _client = client, // ignore: prefer_initializing_formals
      _httpClient = httpClient ?? HttpClient();

  final ApiClient? _client;
  final HttpClient _httpClient;

  ApiClient _clientForBaseUrl(String baseUrl) =>
      _client ?? ApiClient(baseUrl: baseUrl);

  /// 请求一个预签名上传地址。上传地址通常只在 [ttlMinutes] 内有效，
  /// 下载地址是长期公网可访问的直链，可以直接喂给 `ae_*` 下游工具。
  Future<AgentEarthUploadAddress> requestUploadAddress({
    required String apiKey,
    required String baseUrl,
    required String ext,
    required int sizeBytes,
    int ttlMinutes = 60,
  }) async {
    final normalizedExt = _normalizeExt(ext);
    final response = await _clientForBaseUrl(baseUrl).post(
      '/tool/execute?tool_name=xl_file_service_get_upload_addr',
      apiKey,
      {
        'params': {
          'ext': normalizedExt,
          'size_bytes': sizeBytes,
          'ttl_minutes': ttlMinutes,
        },
      },
    );

    final result = response['result'];
    Map<String, Object?>? payload;
    if (result is List) {
      for (final item in result) {
        if (item is Map && item['type'] == 'text' && item['text'] is String) {
          try {
            final decoded = jsonDecode(item['text'] as String);
            if (decoded is Map) {
              payload = Map<String, Object?>.from(decoded);
              break;
            }
          } catch (_) {
            // ignore malformed payloads
          }
        }
      }
    } else if (result is Map) {
      payload = Map<String, Object?>.from(result);
    }

    if (payload == null) {
      throw const ApiClientException('AgentEarth 未返回可解析的上传地址。');
    }

    final err = payload['error'];
    if (err is num && err != 0) {
      final msg = payload['msg'] ?? payload['message'] ?? 'AgentEarth 上传地址请求失败。';
      throw ApiClientException(msg.toString());
    }

    final uploadUrl = payload['uploadURL'];
    final downloadUrl = payload['downloadURL'];
    if (uploadUrl is! String ||
        uploadUrl.trim().isEmpty ||
        downloadUrl is! String ||
        downloadUrl.trim().isEmpty) {
      throw const ApiClientException('AgentEarth 未返回有效的 uploadURL / downloadURL。');
    }

    return AgentEarthUploadAddress(
      uploadUrl: uploadUrl.trim(),
      downloadUrl: downloadUrl.trim(),
      ext: normalizedExt,
      sizeBytes: sizeBytes,
      ttlMinutes: ttlMinutes,
    );
  }

  /// 上传原始字节。AgentEarth 侧只接受 `PUT`，body 直接是文件内容。
  Future<void> putBytes({
    required AgentEarthUploadAddress address,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse(address.uploadUrl);
    final request = await _httpClient
        .putUrl(uri)
        .timeout(const Duration(seconds: 30));
    request.headers.contentType = ContentType.parse(contentType);
    request.headers.contentLength = bytes.length;

    // 分块写入以便上层展示进度。块大小 64KB 是本地网络上一个平衡的经验值。
    const chunkSize = 64 * 1024;
    var offset = 0;
    while (offset < bytes.length) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      request.add(bytes.sublist(offset, end));
      offset = end;
      onProgress?.call(offset, bytes.length);
    }

    final response = await request.close().timeout(
      const Duration(minutes: 15),
    );
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiClientException(
        body.isEmpty
            ? 'AgentEarth 文件上传失败（HTTP ${response.statusCode}）'
            : body,
      );
    }

    // 服务端返回 `{"error":0,"msg":"Upload success"}`；显式校验一下。
    if (body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final err = decoded['error'];
          if (err is num && err != 0) {
            final msg = decoded['msg']?.toString() ?? '上传失败';
            throw ApiClientException(msg);
          }
        }
      } catch (error) {
        if (error is ApiClientException) rethrow;
        // 非 JSON 响应但 HTTP 2xx 视为成功。
      }
    }
  }

  String _normalizeExt(String raw) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^\.+'), '').toLowerCase();
    if (trimmed.isEmpty) return 'bin';
    final cleaned = trimmed.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return cleaned.isEmpty ? 'bin' : cleaned;
  }
}

class AgentEarthUploadAddress {
  const AgentEarthUploadAddress({
    required this.uploadUrl,
    required this.downloadUrl,
    required this.ext,
    required this.sizeBytes,
    required this.ttlMinutes,
  });

  final String uploadUrl;
  final String downloadUrl;
  final String ext;
  final int sizeBytes;
  final int ttlMinutes;

  DateTime get expiresAt =>
      DateTime.now().add(Duration(minutes: ttlMinutes));
}

/// 常见 MIME → 扩展名，用于 `PickedNativeFile` 里没有明确扩展名的情况。
String extForMimeType(String mimeType) {
  final normalized = mimeType.toLowerCase().trim();
  const map = <String, String>{
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'image/gif': 'gif',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/aac': 'aac',
    'audio/mp4': 'm4a',
    'audio/ogg': 'ogg',
  };
  return map[normalized] ?? 'bin';
}
