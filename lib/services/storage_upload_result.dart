import '../app/models.dart';
import 'native_file_picker.dart';

class StorageUploadResult {
  const StorageUploadResult({
    required this.fileName,
    required this.url,
    required this.kind,
    required this.role,
    required this.category,
    this.objectKey,
    this.etag,
    this.storageBucket,
    this.storageEndpoint,
    this.storageRegion,
  });

  final String fileName;
  final String url;
  final AttachmentKind kind;
  final AttachmentRole role;
  final String category;
  final String? objectKey;
  final String? etag;
  final String? storageBucket;
  final String? storageEndpoint;
  final String? storageRegion;
}

class StorageUploadFileInfo {
  const StorageUploadFileInfo({
    required this.kind,
    required this.role,
    required this.category,
  });

  final AttachmentKind kind;
  final AttachmentRole role;
  final String category;
}

StorageUploadFileInfo inferStorageUploadFileInfo(PickedNativeFile file) {
  if (file.mimeType.startsWith('image/')) {
    return const StorageUploadFileInfo(
      kind: AttachmentKind.image,
      role: AttachmentRole.referenceImage,
      category: '角色',
    );
  }
  if (file.mimeType.startsWith('video/')) {
    return const StorageUploadFileInfo(
      kind: AttachmentKind.video,
      role: AttachmentRole.referenceVideo,
      category: '分镜',
    );
  }
  if (file.mimeType.startsWith('audio/')) {
    return const StorageUploadFileInfo(
      kind: AttachmentKind.audio,
      role: AttachmentRole.referenceAudio,
      category: '音效',
    );
  }
  throw const FormatException('暂只支持图片、视频、音频文件上传。');
}

String createStorageObjectKey(AttachmentRole role, String fileName) {
  final extension = fileName.contains('.')
      ? fileName.substring(fileName.lastIndexOf('.'))
      : '';
  final baseName = fileName
      .replaceFirst(RegExp(r'\.[^.]+$'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9-_]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final normalizedBaseName = baseName.isEmpty ? 'asset' : baseName;
  return 'seedance-materials/${storageRoleKey(role)}/${DateTime.now().millisecondsSinceEpoch}-$normalizedBaseName$extension';
}

String storageRoleKey(AttachmentRole role) {
  switch (role) {
    case AttachmentRole.firstFrame:
      return 'first_frame';
    case AttachmentRole.lastFrame:
      return 'last_frame';
    case AttachmentRole.referenceImage:
      return 'reference_image';
    case AttachmentRole.referenceVideo:
      return 'reference_video';
    case AttachmentRole.referenceAudio:
      return 'reference_audio';
  }
}

String normalizePublicUrlBase(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return 'http://$trimmed';
}

String encodeObjectKeyForUrl(String key) {
  return key.split('/').map(Uri.encodeComponent).join('/');
}
