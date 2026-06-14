import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../app/models.dart';
import 'native_file_picker.dart';
import 'storage_upload_result.dart';

const qiniuClientUploadHost = 'https://upload.qiniup.com';
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
  }) async {
    final config = _QiniuConfig.fromSettings(settings);
    final inferred = inferStorageUploadFileInfo(file);
    final key = createStorageObjectKey(inferred.role, file.name);
    final token = _createUploadToken(config, key);

    Map<String, Object?> response;
    try {
      response = await _uploadWithMultipart(
        uploadHost: qiniuClientUploadHost,
        file: file,
        key: key,
        token: token,
      );
    } on Exception catch (error) {
      final retryHost = _extractSuggestedUploadHost(error);
      if (retryHost == null) rethrow;
      response = await _uploadWithMultipart(
        uploadHost: retryHost,
        file: file,
        key: key,
        token: token,
      );
    }

    final storedKey = response['key'] is String
        ? response['key'] as String
        : key;
    return StorageUploadResult(
      objectKey: storedKey,
      etag: response['hash'] is String ? response['hash'] as String : null,
      fileName: file.name,
      url:
          '${normalizePublicUrlBase(config.domain)}/${encodeObjectKeyForUrl(storedKey)}',
      kind: inferred.kind,
      role: inferred.role,
      category: inferred.category,
      storageBucket: config.bucket,
      fileSizeBytes: file.bytes.length,
    );
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
    final request = await HttpClient().openUrl(method, uri);
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
    final request = await HttpClient().openUrl(method, uri);
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

  Future<Map<String, Object?>> _uploadWithMultipart({
    required String uploadHost,
    required PickedNativeFile file,
    required String key,
    required String token,
  }) async {
    final boundary = '----mova-${Random().nextInt(1 << 32)}';
    final body = BytesBuilder();
    void addTextField(String name, String value) {
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(
        utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
      );
      body.add(utf8.encode('$value\r\n'));
    }

    addTextField('key', key);
    addTextField('token', token);
    body.add(utf8.encode('--$boundary\r\n'));
    body.add(
      utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="${_escapeHeader(file.name)}"\r\n',
      ),
    );
    body.add(utf8.encode('Content-Type: ${file.mimeType}\r\n\r\n'));
    body.add(file.bytes);
    body.add(utf8.encode('\r\n--$boundary--\r\n'));

    final uri = Uri.parse(uploadHost);
    final request = await HttpClient().postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );
    request.add(body.toBytes());

    final response = await request.close();
    final responseText = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        responseText.isEmpty
            ? '上传失败（HTTP ${response.statusCode}）'
            : responseText,
        uri: uri,
      );
    }
    final decoded = jsonDecode(responseText);
    if (decoded is! Map) {
      throw const FormatException('七牛上传返回了无法解析的响应。');
    }
    return Map<String, Object?>.from(decoded);
  }

  String _base64UrlEncode(List<int> bytes) {
    return base64Encode(bytes).replaceAll('+', '-').replaceAll('/', '_');
  }

  String _escapeHeader(String value) {
    return value
        .replaceAll('"', '\\"')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
  }

  String? _extractSuggestedUploadHost(Object error) {
    final match = RegExp(
      r'please use\s+([a-zA-Z0-9.-]+qiniup\.com)',
      caseSensitive: false,
    ).firstMatch(error.toString());
    final host = match?.group(1);
    return host == null ? null : 'https://$host';
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
