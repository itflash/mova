import 'package:flutter/services.dart';

class NativeFilePicker {
  static const _channel = MethodChannel('mova/native_files');

  Future<List<PickedNativeFile>> pickMediaFiles() async {
    final result = await _channel.invokeMethod<List<Object?>>('pickMediaFiles');
    if (result == null) return const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(PickedNativeFile.fromPlatformMap)
        .toList();
  }

  Future<PickedLocalMediaFile?> pickSingleVideoFile() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickSingleVideoFile',
    );
    if (result == null) return null;
    return PickedLocalMediaFile.fromPlatformMap(result);
  }

  Future<PickedLocalMediaFile?> pickSingleAudioFile() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickSingleAudioFile',
    );
    if (result == null) return null;
    return PickedLocalMediaFile.fromPlatformMap(result);
  }
}

class PickedNativeFile {
  const PickedNativeFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  factory PickedNativeFile.fromPlatformMap(Map<Object?, Object?> value) {
    return PickedNativeFile(
      name: value['name'] as String? ?? 'asset',
      mimeType: value['mimeType'] as String? ?? 'application/octet-stream',
      bytes: value['bytes'] as Uint8List? ?? Uint8List(0),
    );
  }

  factory PickedNativeFile.fromBytes({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) {
    return PickedNativeFile(name: name, mimeType: mimeType, bytes: bytes);
  }
}

class PickedLocalMediaFile {
  const PickedLocalMediaFile({
    required this.name,
    required this.mimeType,
    required this.uri,
    this.path,
    this.durationMs,
  });

  final String name;
  final String mimeType;
  final String uri;
  final String? path;
  final int? durationMs;

  factory PickedLocalMediaFile.fromPlatformMap(Map<Object?, Object?> value) {
    return PickedLocalMediaFile(
      name: value['name'] as String? ?? 'asset',
      mimeType: value['mimeType'] as String? ?? 'application/octet-stream',
      uri: value['uri'] as String? ?? '',
      path: value['path'] as String?,
      durationMs: (value['durationMs'] as num?)?.round(),
    );
  }
}
