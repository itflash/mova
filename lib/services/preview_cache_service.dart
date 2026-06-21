// 预览缓存服务：统一管理图片预览的稳定缓存 key、七牛私有视频兜底下载缓存，
// 以及缓存大小统计与清理。缩略图缓存（mova-thumbs）也纳入统计与清理范围。
//
// 设计要点：
// - 缓存 key 不用完整签名 URL（七牛签名带 e/token 会变），用稳定标识：
//   md5(provider:bucket:objectKey:fileSizeBytes)，图片视频共用同一套。
// - 视频兜底缓存放 applicationSupportDirectory（稳定目录，不会被系统当临时文件清理），
//   用文件 mtime 做 LRU，总大小上限 2GB，超额按最久访问时间清理。
// - 命中缓存时 touch 文件 mtime，等价于更新访问时间。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../app/models.dart';

/// 预览缓存总大小上限（2GB）。超出时按 LRU 清理视频兜底缓存。
const int kPreviewCacheMaxBytes = 2 * 1024 * 1024 * 1024;

/// 生成素材预览缓存的稳定 key。
///
/// 不使用完整签名 URL（七牛私有空间签名含过期时间 e 和 token，刷新后变化），
/// 改用 provider + bucket + objectKey + fileSizeBytes 的组合做 md5，
/// 保证签名 URL 刷新后仍命中同一份缓存。
String previewCacheKey(Attachment attachment) {
  final raw =
      '${attachment.storageProvider.name}'
      ':${attachment.storageBucket ?? ''}'
      ':${attachment.objectKey ?? ''}'
      ':${attachment.fileSizeBytes ?? 0}';
  return md5.convert(utf8.encode(raw)).toString();
}

/// 预览缓存服务。
///
/// 负责视频兜底下载缓存的读写、LRU 清理、大小统计与全量清理。
/// 图片预览的磁盘缓存由 CachedNetworkImage 自身管理，这里只提供 cacheKey。
class PreviewCacheService {
  PreviewCacheService._();

  static final PreviewCacheService instance = PreviewCacheService._();

  /// 视频兜底缓存子目录名。
  static const String _videoCacheDirName = 'preview-video';
  /// CachedNetworkImage 的磁盘缓存目录名（flutter_cache_manager 默认）。
  static const String _cachedImageDirName = 'libCachedImageData';
  /// 缩略图缓存子目录名（与 attachment_media.dart 中 _cachedVideoThumbnail 一致）。
  static const String _thumbsCacheDirName = 'mova-thumbs';

 Directory? _videoCacheDir;
 /// 获取视频兜底缓存目录（懒初始化）。
  Future<Directory> _videoCacheDirectory() async {
    final cached = _videoCacheDir;
    if (cached != null && cached.existsSync()) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_videoCacheDirName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _videoCacheDir = dir;
    return dir;
  }


  /// 获取 CachedNetworkImage 的磁盘缓存目录。
  Future<Directory?> _cachedImageCacheDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_cachedImageDirName');
    return dir.existsSync() ? dir : null;
  }

  /// 获取缩略图缓存目录。
  ///
  /// 优先使用 applicationSupportDirectory 下的稳定目录；
  /// 若 systemTemp 下旧目录已存在（历史数据），一并纳入统计与清理。
  Future<List<Directory>> _thumbsCacheDirectories() async {
    final dirs = <Directory>[];
    final base = await getApplicationSupportDirectory();
    final stable = Directory('${base.path}/$_thumbsCacheDirName');
    if (!stable.existsSync()) {
      stable.createSync(recursive: true);
    }
    dirs.add(stable);
   final legacy = Directory('${Directory.systemTemp.path}/$_thumbsCacheDirName');
   if (legacy.existsSync()) {
     dirs.add(legacy);
   }
   return dirs;
  }

  /// 返回视频兜底缓存文件路径（若存在）。
  ///
  /// 命中时会 touch 文件 mtime 以更新访问时间。
  Future<File?> videoCacheFile(Attachment attachment) async {
    final dir = await _videoCacheDirectory();
    final key = previewCacheKey(attachment);
    final file = File('${dir.path}/$key.mp4');
    if (file.existsSync() && file.lengthSync() > 0) {
      await file.setLastModified(DateTime.now());
      return file;
    }
    return null;
  }

  /// 返回用于写入的视频兜底缓存文件路径（不存在，调用方下载后写入）。
  Future<File> videoCacheFileForWrite(Attachment attachment) async {
    final dir = await _videoCacheDirectory();
    final key = previewCacheKey(attachment);
    return File('${dir.path}/$key.mp4');
  }

  /// 下载 URL 到视频缓存文件，并通过 [onProgress] 回报进度（0-100）。
  ///
  /// 下载完成后触发 LRU 清理。若 [onProgress] 为 null 则不回调。
  Future<File> downloadToVideoCache(
    Attachment attachment,
    String url, {
    void Function(int progress)? onProgress,
  }) async {
    final file = await videoCacheFileForWrite(attachment);
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败（HTTP ${response.statusCode}）', uri: uri);
      }
      final sink = file.openWrite();
      try {
        final total = response.contentLength;
        var downloaded = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (total > 0 && onProgress != null) {
            onProgress(((downloaded / total) * 100).round().clamp(0, 100));
          }
        }
      } finally {
        await sink.close();
      }
    } catch (e) {
      // 下载失败时清理不完整的文件，避免脏缓存。
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close(force: false);
    }
    // 下载完成后异步清理超额缓存，不阻塞播放。
    _enforceCacheLimit();
    return file;
  }

  /// 统计所有预览缓存（视频兜底 + 缩略图）总大小（字节）。
  Future<int> totalCacheSize() async {
    var total = 0;
    final videoDir = await _videoCacheDirectory();
    total += _directorySize(videoDir);
    final thumbDirs = await _thumbsCacheDirectories();
    for (final dir in thumbDirs) {
      total += _directorySize(dir);
    }
    final imageDir = await _cachedImageCacheDirectory();
    if (imageDir != null) {
      total += _directorySize(imageDir);
    }
    return total;
  }

  /// 清理所有预览缓存（视频兜底 + 缩略图），返回释放的字节数。
  Future<int> clearAll() async {
    var freed = 0;
    final videoDir = await _videoCacheDirectory();
    freed += _clearDirectory(videoDir);
    final thumbDirs = await _thumbsCacheDirectories();
    for (final dir in thumbDirs) {
      freed += _clearDirectory(dir);
    }
    final imageDir = await _cachedImageCacheDirectory();
    if (imageDir != null) {
      freed += _clearDirectory(imageDir);
    }
    return freed;
  }

  /// 删除指定素材对应的视频兜底缓存（素材删除时可调用）。
  Future<void> removeVideoCache(Attachment attachment) async {
    final file = await videoCacheFileForWrite(attachment);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  /// LRU 清理：当视频缓存总大小超过上限时，按最久修改时间删除文件直至达标。
  Future<void> _enforceCacheLimit() async {
    try {
      final dir = await _videoCacheDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp4'))
          .toList();
      var total = files.fold<int>(0, (sum, f) => sum + f.lengthSync());
      if (total <= kPreviewCacheMaxBytes) return;
      // 按 mtime 升序（最旧在前）排序，逐个删除直至达标。
      files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      for (final file in files) {
        if (total <= kPreviewCacheMaxBytes) break;
        final size = file.lengthSync();
        try {
          file.deleteSync();
          total -= size;
        } catch (_) {}
      }
    } catch (_) {
      // 清理失败不影响主流程。
    }
  }

  int _directorySize(Directory dir) {
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
    } catch (_) {}
    return total;
  }

  int _clearDirectory(Directory dir) {
    if (!dir.existsSync()) return 0;
    var freed = 0;
    try {
      for (final entity in dir.listSync()) {
        if (entity is File) {
          freed += entity.lengthSync();
          entity.deleteSync();
        }
      }
    } catch (_) {}
    return freed;
  }
}

/// 将字节数格式化为人类可读字符串（如 "1.2 GB"、"340 MB"）。
String formatCacheBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unitIndex]}';
}
