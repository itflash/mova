import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../app/models.dart';
import 'native_file_picker.dart';
import 'storage_upload_result.dart';

class BitifulS4UploadService {
  Future<void> testConfig(SettingsState settings) async {
    final config = _BitifulConfig.fromSettings(settings);
    final request = _createSignedRequest(
      config: config,
      method: 'HEAD',
      pathSegments: [config.bucket],
      payload: Uint8List(0),
    );
    await _sendRequest(request);
  }

  Future<StorageUploadResult> upload({
    required SettingsState settings,
    required PickedNativeFile file,
    void Function(int progress)? onProgress,
  }) async {
    final config = _BitifulConfig.fromSettings(settings);
    final inferred = inferStorageUploadFileInfo(file);
    final key = createStorageObjectKey(inferred.role, file.name);
    final request = _createSignedRequest(
      config: config,
      method: 'PUT',
      pathSegments: [config.bucket, ...key.split('/')],
      payload: file.bytes,
      contentType: file.mimeType,
    );
    final response = await _sendRequest(request, onProgress: onProgress);
    final etag = response.headers
        .value(HttpHeaders.etagHeader)
        ?.replaceAll('"', '');
    return StorageUploadResult(
      objectKey: key,
      etag: etag,
      fileName: file.name,
      url: '${_publicBaseUrl(config)}/${encodeObjectKeyForUrl(key)}',
      kind: inferred.kind,
      role: inferred.role,
      category: inferred.category,
      storageBucket: config.bucket,
      storageDomain: _publicBaseUrl(config),
      storageEndpoint: config.endpoint,
      storageRegion: config.region,
      fileSizeBytes: file.bytes.length,
    );
  }

  Future<void> deleteObject({
    required SettingsState settings,
    required String objectKey,
    String? bucket,
    String? endpoint,
    String? region,
  }) async {
    final config = _BitifulConfig.fromSettings(
      settings.copyWith(
        bitifulBucket: bucket ?? settings.bitifulBucket,
        bitifulEndpoint: endpoint ?? settings.bitifulEndpoint,
        bitifulRegion: region ?? settings.bitifulRegion,
      ),
    );
    final request = _createSignedRequest(
      config: config,
      method: 'DELETE',
      pathSegments: [config.bucket, ...objectKey.split('/')],
      payload: Uint8List(0),
    );
    await _sendRequest(request);
  }

  String createPresignedGetUrl({
    required SettingsState settings,
    required String objectKey,
    String? bucket,
    String? endpoint,
    String? region,
    Duration expiresIn = const Duration(hours: 1),
  }) {
    final config = _BitifulConfig.fromSettings(settings);
    final resolvedBucket = (bucket ?? config.bucket).trim();
    final resolvedEndpoint = normalizePublicUrlBase(
      endpoint ?? config.endpoint,
    );
    final resolvedRegion = (region ?? config.region).trim();
    final endpointUri = Uri.parse(resolvedEndpoint);
    final normalizedPathSegments = [
      ...endpointUri.pathSegments.where((segment) => segment.isNotEmpty),
      resolvedBucket,
      ...objectKey.split('/').where((segment) => segment.isNotEmpty),
    ];
    final uri = endpointUri.replace(
      pathSegments: normalizedPathSegments,
      queryParameters: null,
      fragment: null,
    );
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = _formatDateStamp(now);
    final credentialScope = '$dateStamp/$resolvedRegion/s3/aws4_request';
    final host = _hostHeaderValue(uri);
    final expires = expiresIn.inSeconds.clamp(1, 604800);

    final queryParameters = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '${config.accessKey}/$credentialScope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '$expires',
      'X-Amz-SignedHeaders': 'host',
    };
    final canonicalQueryString = queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final queryString = canonicalQueryString
        .map(
          (entry) =>
              '${_encodeQueryComponent(entry.key)}=${_encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final canonicalRequest = [
      'GET',
      '/${normalizedPathSegments.map(_encodeCanonicalSegment).join('/')}',
      queryString,
      'host:$host\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final signingKey = _signingKey(
      secretKey: config.secretKey,
      dateStamp: dateStamp,
      region: resolvedRegion,
      service: 's3',
    );
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();
    final finalQueryEntries = [
      ...queryParameters.entries,
      MapEntry('X-Amz-Signature', signature),
    ]..sort((a, b) => a.key.compareTo(b.key));
    final finalQueryString = finalQueryEntries
        .map(
          (entry) =>
              '${_encodeQueryComponent(entry.key)}=${_encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return uri.replace(query: finalQueryString).toString();
  }

  _SignedRequest _createSignedRequest({
    required _BitifulConfig config,
    required String method,
    required List<String> pathSegments,
    required Uint8List payload,
    String? contentType,
  }) {
    final endpoint = Uri.parse(config.endpoint);
    final normalizedPathSegments = [
      ...endpoint.pathSegments.where((segment) => segment.isNotEmpty),
      ...pathSegments.where((segment) => segment.isNotEmpty),
    ];
    final uri = endpoint.replace(
      pathSegments: normalizedPathSegments,
      query: null,
      fragment: null,
    );
    final host = _hostHeaderValue(uri);
    final payloadHash = sha256.convert(payload).toString();
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = _formatDateStamp(now);

    final canonicalHeaders = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };
    if (contentType != null && contentType.trim().isNotEmpty) {
      canonicalHeaders['content-type'] = contentType.trim();
    }

    final sortedHeaderKeys = canonicalHeaders.keys.toList()..sort();
    final canonicalHeadersText = sortedHeaderKeys
        .map((key) => '$key:${canonicalHeaders[key]!}\n')
        .join();
    final signedHeaders = sortedHeaderKeys.join(';');
    final canonicalUri =
        '/${normalizedPathSegments.map(_encodeCanonicalSegment).join('/')}';
    final credentialScope = '$dateStamp/${config.region}/s3/aws4_request';
    final canonicalRequest = [
      method.toUpperCase(),
      canonicalUri,
      '',
      canonicalHeadersText,
      signedHeaders,
      payloadHash,
    ].join('\n');
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final signingKey = _signingKey(
      secretKey: config.secretKey,
      dateStamp: dateStamp,
      region: config.region,
      service: 's3',
    );
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();
    final authorization =
        'AWS4-HMAC-SHA256 Credential=${config.accessKey}/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    final headers = <String, String>{
      HttpHeaders.hostHeader: host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      HttpHeaders.authorizationHeader: authorization,
    };
    if (contentType != null && contentType.trim().isNotEmpty) {
      headers[HttpHeaders.contentTypeHeader] = contentType.trim();
    }
    return _SignedRequest(
      uri: uri,
      headers: headers,
      payload: payload,
      method: method,
    );
  }

  Future<HttpClientResponse> _sendRequest(
    _SignedRequest request, {
    void Function(int progress)? onProgress,
  }) async {
    // 调用方会读取响应头/响应体，此处不在返回前 close client，否则会中断
    // 响应流的消费；HttpClient 实例失去引用后由 GC 回收，连接在响应被
    // 完整消费后会回到连接池。如需更严格的资源管理，应重构为调用方持有 client。
    final client = HttpClient();
    final httpRequest = await client.openUrl(request.method, request.uri);
    request.headers.forEach(httpRequest.headers.set);
    if (request.payload.isNotEmpty) {
      httpRequest.contentLength = request.payload.length;
      await _writeRequestPayload(
        httpRequest,
        request.payload,
        onProgress: onProgress,
      );
    }
    final response = await httpRequest.close();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    final responseText = await response.transform(utf8.decoder).join();
    throw HttpException(
      responseText.isEmpty
          ? '缤纷云（Bitiful）S4 请求失败（HTTP ${response.statusCode}）'
          : responseText,
      uri: request.uri,
    );
  }

  Future<void> _writeRequestPayload(
    HttpClientRequest request,
    Uint8List payload, {
    void Function(int progress)? onProgress,
  }) async {
    if (payload.isEmpty) return;

    const chunkSize = 64 * 1024;
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = offset + chunkSize < payload.length
          ? offset + chunkSize
          : payload.length;
      request.add(Uint8List.sublistView(payload, offset, end));
      if (onProgress != null) {
        onProgress(
          ((end / payload.length) * 100).round().clamp(0, 100).toInt(),
        );
      }
      await request.flush();
    }
  }

  String _publicBaseUrl(_BitifulConfig config) {
    final custom = normalizePublicUrlBase(config.publicDomain);
    if (custom.isNotEmpty) {
      return custom;
    }
    final endpoint = Uri.parse(config.endpoint);
    return normalizePublicUrlBase(
      endpoint
          .replace(
            pathSegments: [
              ...endpoint.pathSegments.where((segment) => segment.isNotEmpty),
              config.bucket,
            ],
            query: null,
            fragment: null,
          )
          .toString(),
    );
  }

  String _hostHeaderValue(Uri uri) {
    final defaultPort =
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
    return defaultPort ? uri.host : '${uri.host}:${uri.port}';
  }

  String _encodeCanonicalSegment(String segment) {
    return Uri.encodeComponent(
      segment,
    ).replaceAll('+', '%20').replaceAll('*', '%2A').replaceAll('%7E', '~');
  }

  String _encodeQueryComponent(String value) {
    return Uri.encodeQueryComponent(
      value,
    ).replaceAll('+', '%20').replaceAll('*', '%2A').replaceAll('%7E', '~');
  }

  String _formatAmzDate(DateTime value) {
    return '${_formatDateStamp(value)}T${_twoDigits(value.hour)}${_twoDigits(value.minute)}${_twoDigits(value.second)}Z';
  }

  String _formatDateStamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}${_twoDigits(value.month)}${_twoDigits(value.day)}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  List<int> _signingKey({
    required String secretKey,
    required String dateStamp,
    required String region,
    required String service,
  }) {
    final kDate = Hmac(
      sha256,
      utf8.encode('AWS4$secretKey'),
    ).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode(service)).bytes;
    return Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
  }
}

class _SignedRequest {
  const _SignedRequest({
    required this.uri,
    required this.headers,
    required this.payload,
    required this.method,
  });

  final Uri uri;
  final Map<String, String> headers;
  final Uint8List payload;
  final String method;
}

class _BitifulConfig {
  const _BitifulConfig({
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    required this.endpoint,
    required this.region,
    required this.publicDomain,
  });

  final String accessKey;
  final String secretKey;
  final String bucket;
  final String endpoint;
  final String region;
  final String publicDomain;

  factory _BitifulConfig.fromSettings(SettingsState settings) {
    return _BitifulConfig(
      accessKey: settings.bitifulAccessKey.trim(),
      secretKey: settings.bitifulSecretKey.trim(),
      bucket: settings.bitifulBucket.trim(),
      endpoint: normalizePublicUrlBase(settings.bitifulEndpoint),
      region: settings.bitifulRegion.trim(),
      publicDomain: settings.bitifulPublicDomain.trim(),
    );
  }
}
