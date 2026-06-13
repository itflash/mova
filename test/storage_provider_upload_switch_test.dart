import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/app_state.dart';
import 'package:mova/app/mock_data.dart';
import 'package:mova/app/models.dart';
import 'package:mova/services/app_storage.dart';
import 'package:mova/services/bitiful_s4_upload_service.dart';
import 'package:mova/services/native_file_picker.dart';
import 'package:mova/services/qiniu_upload_service.dart';
import 'package:mova/services/storage_upload_result.dart';

void main() {
  test('uploads through qiniu when qiniu is selected', () async {
    final qiniu = _FakeQiniuUploadService(
      result: const StorageUploadResult(
        fileName: 'hero.png',
        url: 'https://cdn.example.com/hero.png',
        kind: AttachmentKind.image,
        role: AttachmentRole.referenceImage,
        category: '角色',
        objectKey: 'seedance-materials/reference_image/hero.png',
        storageBucket: 'qiniu-bucket',
      ),
    );
    final bitiful = _FakeBitifulS4UploadService(
      result: const StorageUploadResult(
        fileName: 'unused.png',
        url: 'https://s3.bitiful.net/demo/unused.png',
        kind: AttachmentKind.image,
        role: AttachmentRole.referenceImage,
        category: '角色',
      ),
    );
    final state = AppState(
      filePicker: _FakeFilePicker.singleImage(),
      qiniuUploadService: qiniu,
      bitifulUploadService: bitiful,
      storage: _MemoryAppStorage(),
    );
    state.updateSettings(
      (current) => current.copyWith(
        storageProvider: StorageProvider.qiniu,
        qiniuAccessKey: 'ak',
        qiniuSecretKey: 'sk',
        qiniuBucket: 'qiniu-bucket',
        qiniuDomain: 'https://cdn.example.com',
      ),
    );

    final uploaded = await state.pickAndUploadFiles();

    expect(uploaded, 1);
    expect(qiniu.uploadCallCount, 1);
    expect(bitiful.uploadCallCount, 0);

    final attachment = state.library.firstWhere(
      (item) => item.fileName == 'hero.png',
    );
    expect(attachment.status, AttachmentStatus.uploaded);
    expect(attachment.storageProvider, StorageProvider.qiniu);
    expect(attachment.storageBucket, 'qiniu-bucket');
    expect(attachment.objectKey, 'seedance-materials/reference_image/hero.png');
    expect(attachment.url, 'https://cdn.example.com/hero.png');
  });

  test('uploads through bitiful when bitiful is selected', () async {
    final qiniu = _FakeQiniuUploadService(
      result: const StorageUploadResult(
        fileName: 'unused.mp4',
        url: 'https://cdn.example.com/unused.mp4',
        kind: AttachmentKind.video,
        role: AttachmentRole.referenceVideo,
        category: '分镜',
      ),
    );
    final bitiful = _FakeBitifulS4UploadService(
      result: const StorageUploadResult(
        fileName: 'scene.mp4',
        url: 'https://s3.bitiful.net/demo/scene.mp4',
        kind: AttachmentKind.video,
        role: AttachmentRole.referenceVideo,
        category: '分镜',
        objectKey: 'seedance-materials/reference_video/scene.mp4',
        storageBucket: 'bitiful-bucket',
        storageEndpoint: 'https://s3.bitiful.net',
        storageRegion: 'cn-east-1',
      ),
    );
    final state = AppState(
      filePicker: _FakeFilePicker.singleVideo(),
      qiniuUploadService: qiniu,
      bitifulUploadService: bitiful,
      storage: _MemoryAppStorage(),
    );
    state.updateSettings(
      (current) => current.copyWith(
        storageProvider: StorageProvider.bitifulS4,
        bitifulAccessKey: 'ak',
        bitifulSecretKey: 'sk',
        bitifulBucket: 'bitiful-bucket',
        bitifulEndpoint: settingsDefaults.bitifulEndpoint,
        bitifulRegion: settingsDefaults.bitifulRegion,
      ),
    );

    final uploaded = await state.pickAndUploadFiles();

    expect(uploaded, 1);
    expect(qiniu.uploadCallCount, 0);
    expect(bitiful.uploadCallCount, 1);

    final attachment = state.library.firstWhere(
      (item) => item.fileName == 'scene.mp4',
    );
    expect(attachment.status, AttachmentStatus.uploaded);
    expect(attachment.kind, AttachmentKind.video);
    expect(attachment.role, AttachmentRole.referenceVideo);
    expect(attachment.storageProvider, StorageProvider.bitifulS4);
    expect(attachment.storageBucket, 'bitiful-bucket');
    expect(attachment.storageEndpoint, 'https://s3.bitiful.net');
    expect(attachment.storageRegion, 'cn-east-1');
    expect(
      attachment.objectKey,
      'seedance-materials/reference_video/scene.mp4',
    );
  });

  test('request preview uses signed bitiful url for private attachments', () async {
    final bitiful = _FakeBitifulS4UploadService(
      result: const StorageUploadResult(
        fileName: 'unused.png',
        url: 'https://s3.bitiful.net/demo/unused.png',
        kind: AttachmentKind.image,
        role: AttachmentRole.referenceImage,
        category: '角色',
      ),
      signedGetUrl:
          'https://signed.example.com/seedance-materials/reference_image/hero.png?X-Amz-Signature=test',
    );
    final state = AppState(
      filePicker: _FakeFilePicker.singleImage(),
      qiniuUploadService: _FakeQiniuUploadService(
        result: const StorageUploadResult(
          fileName: 'unused.png',
          url: 'https://cdn.example.com/unused.png',
          kind: AttachmentKind.image,
          role: AttachmentRole.referenceImage,
          category: '角色',
        ),
      ),
      bitifulUploadService: bitiful,
      storage: _MemoryAppStorage(),
    );
    state.activeMode = ModeId.firstFrame;
    state.updateSettings(
      (current) => current.copyWith(
        storageProvider: StorageProvider.bitifulS4,
        bitifulAccessKey: 'ak',
        bitifulSecretKey: 'sk',
        bitifulBucket: 'bitiful-bucket',
        bitifulEndpoint: settingsDefaults.bitifulEndpoint,
        bitifulRegion: settingsDefaults.bitifulRegion,
      ),
    );
    state.library.insert(
      0,
      Attachment(
        id: 'bitiful-image',
        label: 'hero.png',
        role: AttachmentRole.referenceImage,
        kind: AttachmentKind.image,
        fileName: 'hero.png',
        category: '角色',
        createdAt: DateTime(2026),
        status: AttachmentStatus.uploaded,
        url:
            'https://s3.bitiful.net/bitiful-bucket/seedance-materials/reference_image/hero.png',
        storageProvider: StorageProvider.bitifulS4,
        objectKey: 'seedance-materials/reference_image/hero.png',
        storageBucket: 'bitiful-bucket',
        storageEndpoint: 'https://s3.bitiful.net',
        storageRegion: 'cn-east-1',
      ),
    );
    state.selectedAttachmentIds
      ..clear()
      ..add('bitiful-image');

    final preview = await state.resolveRequestPreview();
    final params = Map<String, Object?>.from(
      preview.body['params'] as Map<Object?, Object?>,
    );

    expect(bitiful.signedGetUrlCallCount, 1);
    expect(
      params['image_url'],
      'https://signed.example.com/seedance-materials/reference_image/hero.png?X-Amz-Signature=test',
    );
  });
}

class _FakeFilePicker extends NativeFilePicker {
  _FakeFilePicker(this.files);

  final List<PickedNativeFile> files;

  factory _FakeFilePicker.singleImage() => _FakeFilePicker([
    PickedNativeFile(
      name: 'hero.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]),
    ),
  ]);

  factory _FakeFilePicker.singleVideo() => _FakeFilePicker([
    PickedNativeFile(
      name: 'scene.mp4',
      mimeType: 'video/mp4',
      bytes: Uint8List.fromList([4, 5, 6]),
    ),
  ]);

  @override
  Future<List<PickedNativeFile>> pickMediaFiles() async => files;
}

class _FakeQiniuUploadService extends QiniuUploadService {
  _FakeQiniuUploadService({required this.result});

  final StorageUploadResult result;
  int uploadCallCount = 0;

  @override
  Future<StorageUploadResult> upload({
    required SettingsState settings,
    required PickedNativeFile file,
  }) async {
    uploadCallCount++;
    return result;
  }
}

class _FakeBitifulS4UploadService extends BitifulS4UploadService {
  _FakeBitifulS4UploadService({required this.result, this.signedGetUrl});

  final StorageUploadResult result;
  final String? signedGetUrl;
  int uploadCallCount = 0;
  int signedGetUrlCallCount = 0;

  @override
  Future<StorageUploadResult> upload({
    required SettingsState settings,
    required PickedNativeFile file,
  }) async {
    uploadCallCount++;
    return result;
  }

  @override
  String createPresignedGetUrl({
    required SettingsState settings,
    required String objectKey,
    String? bucket,
    String? endpoint,
    String? region,
    Duration expiresIn = const Duration(hours: 1),
  }) {
    signedGetUrlCallCount++;
    return signedGetUrl ??
        'https://signed.example.com/$objectKey?X-Amz-Signature=test';
  }
}

class _MemoryAppStorage extends AppStorage {
  String? value;

  @override
  Future<String?> readState() async => value;

  @override
  Future<void> writeState(String nextValue) async {
    value = nextValue;
  }
}
