import 'package:flutter/services.dart';

class AppStorage {
  static const _channel = MethodChannel('mova/storage');

  Future<String?> readState() {
    return _channel.invokeMethod<String>('readState');
  }

  Future<void> writeState(String value) async {
    await _channel.invokeMethod<bool>('writeState', {'value': value});
  }

  Future<String?> exportState(String value, {String? suggestedFileName}) {
    return _channel.invokeMethod<String>('exportState', {
      'value': value,
      'suggestedFileName': suggestedFileName,
    });
  }

  Future<String?> importState() {
    return _channel.invokeMethod<String>('importState');
  }
}
