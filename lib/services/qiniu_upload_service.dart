import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:qiniu_flutter_sdk/qiniu_flutter_sdk.dart' as qiniu;

import '../app/models.dart';
import 'native_file_picker.dart';
import 'storage_upload_result.dart';

const qiniuUcApiHost = 'https://uc.qiniuapi.com';

class QiniuUploadService {
  Future<List<String>> fetchBuckets(SettingsState settings) async {
    final config = _QiniuConfig.fromSettings(settings);
    final response = await _requestManagementJson(
      config: config,
      method: 'GET',
      pathWithQuery: '/buckets',
    );
    if (response is List) {
      return response.whereType<String>().toList();
    }
    throw const FormatException('七牛 Bucket 列表返回格式无法解析。');
  }

  Future<List<String>> fetchBucketDomains(
    SettingsState settings,
    String bucket,
  ) async {
    final config = _QiniuConfig.fromSettings(settings);
    final response = await _requestManagementJson(
      config: config,
      method: 'GET',
      pathWithQuery: '/v2/domains?tbl=${Uri.encodeComponent(bucket)}',
    );
    if (response is List) {
      return response.whereType<String>().map(normalizePublicUrlBase).toList();
    }
    throw const FormatException('七牛域名列表返回格式无法解析。');
  }

  Future<StorageUploadResult> upload({
    required SettingsState settings,
    required PickedNativeFile file,
    void Function(int progress)? onProgress,
  }) async {
    final config = _QiniuConfig.fromSettings(settings);
    final inferred = inferStorageUploadFileInfo(file);
    final key = createStorageObjectKey(inferred.role, file.name);
    final token = _createUploadToken(config, key);

    final localFile = await _localUploadFile(file);
    final controller = qiniu.PutController();
    void Function()? removeProgressListener;
    if (onProgress != null) {
      removeProgressListener = controller.addProgressListener((percent) {
        onProgress((percent * 100).round().clamp(0, 100).toInt());
      });
    }

    final response = await qiniu.Storage().putFile(
      localFile,
      token,
      options: qiniu.PutOptions(
        key: key,
        mimeType: file.mimeType,
        controller: controller,
      ),
    );
    removeProgressListener?.call();

    final storedKey = response.key ?? response.rawData['key'] as String? ?? key;
    return StorageUploadResult(
      objectKey: storedKey,
      etag: response.hash ?? response.rawData['hash'] as String?,
      fileName: file.name,
      url:
          '${normalizePublicUrlBase(config.domain)}/${encodeObjectKeyForUrl(storedKey)}',
      kind: inferred.kind,
      role: inferred.role,
      category: inferred.category,
      storageBucket: config.bucket,
      storageDomain: config.domain,
      fileSizeBytes: file.bytes.length,
    );
  }

  /// 查询 bucket 是否为私有空间。
  /// 七牛管理 API：GET `/bucket/<bucket>/private`，返回 {"private": 0|1}。
  Future<bool> fetchBucketPrivate(SettingsState settings) async {
    final config = _QiniuConfig.fromSettings(settings);
    final response = await _requestManagementJson(
      config: config,
      method: 'GET',
      pathWithQuery: '/bucket/${Uri.encodeComponent(config.bucket)}/private',
    );
    final value = response is Map ? response['private'] : null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.trim() == '1' || value.trim() == 'true';
    return false;
  }

  /// 为私有空间生成带签名的下载 URL。
  /// 签名规则：downloadUrl = domain + '/' + key + '?e=' + deadline，
  /// sign = urlSafeBase64(HMAC-SHA1(secretKey, downloadUrl))，
  /// 最终 URL = downloadUrl + '&token=' + ak + ':' + sign。
  /// 注意：签名串必须是完整 downloadUrl（含协议与 host），与最终请求 URL 一致，
  /// 否则七牛服务端校验不通过。deadline 是秒级 Unix 时间戳。
  String createPrivateDownloadUrl({
    required SettingsState settings,
    required String objectKey,
    required Duration expiresIn,
    String? domain,
  }) {
    final config = _QiniuConfig.fromSettings(settings);
    final resolvedDomain = normalizePublicUrlBase(
      domain?.trim() ?? config.domain,
    );
    final deadline =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn.inSeconds;
    final encodedKey = encodeObjectKeyForUrl(objectKey);
    final downloadUrl = '$resolvedDomain/$encodedKey?e=$deadline';
    final signature = _hmacSha1Base64Url(config.secretKey, downloadUrl);
    final token = '${config.accessKey}:$signature';
    return '$downloadUrl&token=$token';
  }

  Future<void> deleteObject({
    required SettingsState settings,
    required String bucket,
    required String objectKey,
  }) async {
    final config = _QiniuConfig.fromSettings(
      settings.copyWith(qiniuBucket: bucket),
    );
    final encodedEntryUri = _base64UrlEncode(utf8.encode('$bucket:$objectKey'));
    await _requestManagement(
      config: config,
      method: 'POST',
      host: 'rs.qiniuapi.com',
      baseUrl: 'https://rs.qiniuapi.com',
      pathWithQuery: '/delete/$encodedEntryUri',
    );
  }

  Future<Object?> _requestManagementJson({
    required _QiniuConfig config,
    required String method,
    required String pathWithQuery,
  }) async {
    final qiniuDate = _createQiniuDateHeader();
    final auth = _buildManagementAuthorization(
      config: config,
      method: method,
      pathWithQuery: pathWithQuery,
      host: 'uc.qiniuapi.com',
      qiniuDate: qiniuDate,
    );
    final uri = Uri.parse('$qiniuUcApiHost$pathWithQuery');
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers.set('Authorization', 'Qiniu $auth');
      request.headers.set('X-Qiniu-Date', qiniuDate);
      request.headers.set('Host', 'uc.qiniuapi.com');

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          responseText.isEmpty
              ? '七牛请求失败（HTTP ${response.statusCode}）'
              : responseText,
          uri: uri,
        );
      }
      return jsonDecode(responseText);
    } finally {
      client.close(force: false);
    }
  }

  Future<void> _requestManagement({
    required _QiniuConfig config,
    required String method,
    required String host,
    required String baseUrl,
    required String pathWithQuery,
  }) async {
    final qiniuDate = _createQiniuDateHeader();
    final auth = _buildManagementAuthorization(
      config: config,
      method: method,
      pathWithQuery: pathWithQuery,
      host: host,
      qiniuDate: qiniuDate,
    );
    final uri = Uri.parse('$baseUrl$pathWithQuery');
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers.set('Authorization', 'Qiniu $auth');
      request.headers.set('X-Qiniu-Date', qiniuDate);
      request.headers.set('Host', host);

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          responseText.isEmpty
              ? '七牛删除失败（HTTP ${response.statusCode}）'
              : responseText,
          uri: uri,
        );
      }
    } finally {
      client.close(force: false);
    }
  }

  String _buildManagementAuthorization({
    required _QiniuConfig config,
    required String method,
    required String pathWithQuery,
    required String host,
    required String qiniuDate,
  }) {
    final signingStr =
        '${method.toUpperCase()} $pathWithQuery\nHost: $host\nX-Qiniu-Date: $qiniuDate\n\n';
    final signature = _hmacSha1Base64Url(config.secretKey, signingStr);
    return '${config.accessKey}:$signature';
  }

  String _createQiniuDateHeader() {
    final value = DateTime.now().toUtc().toIso8601String();
    return value
        .replaceAll('-', '')
        .replaceAll(':', '')
        .replaceFirst(RegExp(r'\.\d{3}Z$'), 'Z');
  }

  String _createUploadToken(_QiniuConfig config, String key) {
    final putPolicy = {
      'scope': '${config.bucket}:$key',
      'deadline': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'returnBody':
          '{"key":"\$(key)","hash":"\$(etag)","fname":"\$(fname)","bucket":"\$(bucket)"}',
    };
    final encodedPutPolicy = _base64UrlEncode(
      utf8.encode(jsonEncode(putPolicy)),
    );
    final encodedSign = _hmacSha1Base64Url(config.secretKey, encodedPutPolicy);
    return '${config.accessKey}:$encodedSign:$encodedPutPolicy';
  }

  String _hmacSha1Base64Url(String secret, String value) {
    final digest = Hmac(sha1, utf8.encode(secret)).convert(utf8.encode(value));
    return _base64UrlEncode(digest.bytes);
  }

  Future<File> _localUploadFile(PickedNativeFile file) async {
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      final localFile = File(path);
      if (await localFile.exists()) return localFile;
    }

    final safeName = file.name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final fallbackName = safeName.isEmpty ? 'asset' : safeName;
    final localFile = File(
      '${Directory.systemTemp.path}/${DateTime.now().microsecondsSinceEpoch}-$fallbackName',
    );
    await localFile.writeAsBytes(file.bytes, flush: true);
    return localFile;
  }

  String _base64UrlEncode(List<int> bytes) {
    return base64Encode(bytes).replaceAll('+', '-').replaceAll('/', '_');
  }
}

class _QiniuConfig {
  const _QiniuConfig({
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    required this.domain,
  });

  final String accessKey;
  final String secretKey;
  final String bucket;
  final String domain;

  factory _QiniuConfig.fromSettings(SettingsState settings) {
    return _QiniuConfig(
      accessKey: settings.qiniuAccessKey.trim(),
      secretKey: settings.qiniuSecretKey.trim(),
      bucket: settings.qiniuBucket.trim(),
      domain: settings.qiniuDomain.trim(),
    );
  }
}
