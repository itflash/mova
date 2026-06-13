import 'package:flutter/services.dart';

import '../app/models.dart';

class VideoFrameService {
  static const _channel = MethodChannel('mova/video_frames');

  Future<CapturedFrameResult> captureFrame({
    required String source,
    required int positionMs,
    String? suggestedFileName,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'captureFrame',
      {
        'source': source,
        'positionMs': positionMs,
        'suggestedFileName': suggestedFileName,
      },
    );
    if (result == null) {
      throw PlatformException(
        code: 'capture_failed',
        message: '原生层没有返回截帧结果。',
      );
    }
    return CapturedFrameResult(
      path: result['path'] as String? ?? '',
      uri: result['uri'] as String? ?? '',
      width: result['width'] is num ? (result['width'] as num).round() : 0,
      height: result['height'] is num ? (result['height'] as num).round() : 0,
      positionMs: result['positionMs'] is num
          ? (result['positionMs'] as num).round()
          : positionMs,
    );
  }
}
