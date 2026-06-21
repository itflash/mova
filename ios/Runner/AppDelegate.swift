import Flutter
import AVFoundation
import Photos
import PhotosUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var fileChannel: FlutterMethodChannel?
  private var videoFramesChannel: FlutterMethodChannel?
  private var mediaChannel: FlutterMethodChannel?
  private var storageChannel: FlutterMethodChannel?
 private var documentPickerResult: FlutterResult?
 private var photoPickerResult: FlutterResult?
 private var mediaPickerResult: FlutterResult?
 private var exportStateResult: FlutterResult?
  private var exportStatePayload: String?
  private var importStateResult: FlutterResult?
  private var pickerMode: PickerMode = .media

  private enum PickerMode {
    case media
    case video
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    let fileChannel = FlutterMethodChannel(name: "mova/native_files", binaryMessenger: messenger)
    fileChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "pickSingleVideoFile":
        self.presentVideoPicker(result: result)
      case "pickMediaFiles":
        self.presentMediaPicker(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.fileChannel = fileChannel

    let videoFramesChannel = FlutterMethodChannel(name: "mova/video_frames", binaryMessenger: messenger)
    videoFramesChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "captureFrame":
        guard
          let args = call.arguments as? [String: Any],
          let source = args["source"] as? String
        else {
          result(
            FlutterError(code: "capture_failed", message: "缺少视频来源。", details: nil)
          )
          return
        }
        let positionMs = (args["positionMs"] as? NSNumber)?.intValue ?? 0
        let suggestedFileName = args["suggestedFileName"] as? String
        do {
          result(try self.captureFrame(source: source, positionMs: positionMs, suggestedFileName: suggestedFileName))
        } catch {
          result(
            FlutterError(
              code: "capture_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.videoFramesChannel = videoFramesChannel

    let mediaChannel = FlutterMethodChannel(name: "mova/media", binaryMessenger: messenger)
    mediaChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "media_failed", message: "缺少媒体参数。", details: nil))
        return
      }
      let sourcePath = args["sourcePath"] as? String
      let fileName = args["fileName"] as? String
      switch call.method {
      case "saveImageToGallery":
        self.saveImageToGallery(sourcePath: sourcePath, fileName: fileName, result: result)
      case "saveVideoToGallery":
        self.saveVideoToGallery(sourcePath: sourcePath, fileName: fileName, result: result)
      case "openMedia":
        result(FlutterMethodNotImplemented)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.mediaChannel = mediaChannel

    let storageChannel = FlutterMethodChannel(name: "mova/storage", binaryMessenger: messenger)
    storageChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "readState":
        result(UserDefaults.standard.string(forKey: "mova_app_state"))
      case "writeState":
        let value = args["value"] as? String ?? ""
        UserDefaults.standard.set(value, forKey: "mova_app_state")
        result(true)
      case "exportState":
        self.exportState(
          value: args["value"] as? String ?? "",
          suggestedFileName: args["suggestedFileName"] as? String ?? "mova-backup.json",
          result: result
        )
      case "importState":
        self.importState(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.storageChannel = storageChannel
  }

  // MARK: - State persistence (mova/storage)

  private func exportState(value: String, suggestedFileName: String, result: @escaping FlutterResult) {
    guard exportStateResult == nil else {
      result(FlutterError(code: "export_busy", message: "导出窗口正在打开。", details: nil))
      return
    }
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFileName)
    do {
      try value.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
      result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
      return
    }
    exportStateResult = result
    exportStatePayload = value
    let picker = UIDocumentPickerViewController(forExporting: [tempURL])
    picker.delegate = self
    rootViewController?.present(picker, animated: true)
  }

  private func importState(result: @escaping FlutterResult) {
    guard importStateResult == nil else {
      result(FlutterError(code: "import_busy", message: "导入窗口正在打开。", details: nil))
      return
    }
    importStateResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
    picker.delegate = self
    rootViewController?.present(picker, animated: true)
  }


  private func videoDurationMs(_ url: URL) -> Int {
    let asset = AVURLAsset(url: url)
    let duration = CMTimeGetSeconds(asset.duration)
    return duration > 0 ? Int(duration * 1000) : 0
  }

  private func saveImageToGallery(sourcePath: String?, fileName: String?, result: @escaping FlutterResult) {
    guard let sourcePath, !sourcePath.isEmpty else {
      result(FlutterError(code: "save_failed", message: "缺少图片路径。", details: nil))
      return
    }
    let url = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(FlutterError(code: "save_failed", message: "源图片不存在。", details: nil))
      return
    }
    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
    }) { success, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
          return
        }
        if success {
          result(["path": fileName ?? url.lastPathComponent, "uri": url.absoluteString])
        } else {
          result(FlutterError(code: "save_failed", message: "保存图片失败。", details: nil))
        }
      }
    }
  }

  private func saveVideoToGallery(sourcePath: String?, fileName: String?, result: @escaping FlutterResult) {
    guard let sourcePath, !sourcePath.isEmpty else {
      result(FlutterError(code: "save_failed", message: "缺少视频路径。", details: nil))
      return
    }
    let url = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(FlutterError(code: "save_failed", message: "源视频不存在。", details: nil))
      return
    }
    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
    }) { success, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
          return
        }
        if success {
          result(["path": fileName ?? url.lastPathComponent, "uri": url.absoluteString])
        } else {
          result(FlutterError(code: "save_failed", message: "保存视频失败。", details: nil))
        }
      }
    }
  }

  private func presentMediaPicker(result: @escaping FlutterResult) {
    if let stale = documentPickerResult { documentPickerResult = nil; stale(nil) }
    if let stale = photoPickerResult { photoPickerResult = nil; stale(nil) }
    if let stale = mediaPickerResult { mediaPickerResult = nil; stale(nil) }
    if #available(iOS 14, *) {
      mediaPickerResult = result
      var configuration = PHPickerConfiguration(photoLibrary: .shared())
      configuration.filter = .any(of: [.images, .videos])
      configuration.selectionLimit = 20
      configuration.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      rootViewController?.present(picker, animated: true)
      return
    }
    result(FlutterMethodNotImplemented)
  }

  private func presentVideoPicker(result: @escaping FlutterResult) {
    // Clean up any stale results from previous pickers that may not have fired their delegate.
    if let stale = documentPickerResult { documentPickerResult = nil; stale(nil) }
    if let stale = photoPickerResult { photoPickerResult = nil; stale(nil) }
    if let stale = mediaPickerResult { mediaPickerResult = nil; stale(nil) }
    if #available(iOS 14, *) {
      photoPickerResult = result
      var configuration = PHPickerConfiguration(photoLibrary: .shared())
      configuration.filter = .videos
      configuration.selectionLimit = 1
      configuration.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      rootViewController?.present(picker, animated: true)
      return
    }
    photoPickerResult = result
    documentPickerResult = result
    photoPickerResult = nil
    pickerMode = .video
    let picker = UIDocumentPickerViewController(
      documentTypes: ["public.movie", "public.video"],
      in: .import
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    rootViewController?.present(picker, animated: true)
  }

  private var rootViewController: UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
  }

  private func captureFrame(
    source: String,
    positionMs: Int,
    suggestedFileName: String?
  ) throws -> [String: Any] {
    let url: URL
    if source.hasPrefix("file://") {
      guard let parsed = URL(string: source) else {
        throw NSError(domain: "mova", code: 1, userInfo: [NSLocalizedDescriptionKey: "视频地址无效。"])
      }
      url = parsed
    } else if source.hasPrefix("/") {
      url = URL(fileURLWithPath: source)
    } else {
      guard let parsed = URL(string: source) else {
        throw NSError(domain: "mova", code: 1, userInfo: [NSLocalizedDescriptionKey: "视频地址无效。"])
      }
      url = parsed
    }

    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceAfter = .zero
    generator.requestedTimeToleranceBefore = .zero
    let time = CMTimeMake(value: Int64(positionMs), timescale: 1000)
    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
    let image = UIImage(cgImage: cgImage)
    guard let data = image.jpegData(compressionQuality: 0.92) else {
      throw NSError(domain: "mova", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法生成截帧图片。"])
    }
    let safeName = (suggestedFileName ?? "frame-\(Date().timeIntervalSince1970).jpg")
      .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
    try data.write(to: output, options: .atomic)
    return [
      "path": output.path,
      "uri": output.absoluteString,
      "width": Int(image.size.width),
      "height": Int(image.size.height),
      "positionMs": positionMs,
    ]
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    // Video picker
    let dpResult = documentPickerResult
    documentPickerResult = nil
    dpResult?(nil)
    // Export
    if let expResult = exportStateResult {
      exportStateResult = nil
      exportStatePayload = nil
      expResult(nil)
    }
    // Import
    if let impResult = importStateResult {
      importStateResult = nil
      impResult(nil)
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    // Export: user picked a destination, payload already written to temp file
    if let expResult = exportStateResult {
      exportStateResult = nil
      exportStatePayload = nil
      if let url = urls.first {
        expResult(["path": url.path, "uri": url.absoluteString])
      } else {
        expResult(nil)
      }
      return
    }

    // Import: read selected file content as JSON string
    if let impResult = importStateResult {
      importStateResult = nil
      guard let url = urls.first else {
        impResult(nil)
        return
      }
      do {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
          if startedAccessing {
            url.stopAccessingSecurityScopedResource()
          }
        }
        let data = try String(contentsOf: url, encoding: .utf8)
        impResult(data)
      } catch {
        impResult(
          FlutterError(code: "import_failed", message: error.localizedDescription, details: nil)
        )
      }
      return
    }

    // Video picker
    let result = documentPickerResult
    documentPickerResult = nil
    guard let url = urls.first else {
      result?(nil)
      return
    }

    let localUrl: URL
    if url.isFileURL {
      localUrl = url
    } else {
      let target = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
      do {
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: url, to: target)
      } catch {
        result?(
          FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil)
        )
        return
      }
      localUrl = target
    }

    result?([
      "name": localUrl.lastPathComponent,
      "mimeType": "video/mp4",
      "uri": localUrl.absoluteString,
      "path": localUrl.path,
    ])
  }
}

@available(iOS 14, *)
extension AppDelegate: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    // Media multi-picker
    if let mediaResult = mediaPickerResult {
      mediaPickerResult = nil
      handleMediaPickerResults(results, result: mediaResult)
      return
    }

    // Single video picker
    let result = photoPickerResult
    photoPickerResult = nil

    guard let item = results.first else {
      result?(nil)
      return
    }

    if item.itemProvider.hasItemConformingToTypeIdentifier("public.movie") {
      item.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
        if let error {
          DispatchQueue.main.async {
            result?(
              FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil)
            )
          }
          return
        }

        guard let url else {
          DispatchQueue.main.async {
            result?(nil)
          }
          return
        }

        let target = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        do {
          if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
          }
          try FileManager.default.copyItem(at: url, to: target)
          let durationMs = self.videoDurationMs(target)
          DispatchQueue.main.async {
            result?([
              "name": target.lastPathComponent,
              "mimeType": "video/mp4",
              "uri": target.absoluteString,
              "path": target.path,
              "durationMs": durationMs,
            ])
          }
        } catch {
          DispatchQueue.main.async {
            result?(
              FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil)
            )
          }
        }
      }
      return
    }

    result?(nil)
  }

  private func handleMediaPickerResults(_ results: [PHPickerResult], result: @escaping FlutterResult) {
    guard !results.isEmpty else {
      result([])
      return
    }

    let group = DispatchGroup()
    var files: [[String: Any]] = []
    var errors: [String] = []
    let lock = NSLock()

    for item in results {
      group.enter()
      let provider = item.itemProvider

      if provider.hasItemConformingToTypeIdentifier("public.movie") {
        provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
          defer { group.leave() }
          if let error {
            lock.lock()
            errors.append(error.localizedDescription)
            lock.unlock()
            return
          }
          guard let url else { return }
          self.copyPickedFile(url: url, mimeType: "video/mp4", files: &files, lock: lock)
        }
      } else if provider.hasItemConformingToTypeIdentifier("public.image") {
        provider.loadFileRepresentation(forTypeIdentifier: "public.image") { url, error in
          defer { group.leave() }
          if let error {
            lock.lock()
            errors.append(error.localizedDescription)
            lock.unlock()
            return
          }
          guard let url else { return }
          let mimeType = self.mimeTypeForPath(url.path)
          self.copyPickedFile(url: url, mimeType: mimeType, files: &files, lock: lock)
        }
      } else {
        group.leave()
      }
    }

    group.notify(queue: .main) {
      if files.isEmpty && !errors.isEmpty {
        result(
          FlutterError(code: "pick_failed", message: errors.joined(separator: "; "), details: nil)
        )
      } else {
        result(files)
      }
    }
  }

  private func copyPickedFile(url: URL, mimeType: String, files: inout [[String: Any]], lock: NSLock) {
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
    do {
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.copyItem(at: url, to: target)
      let fileData = try Data(contentsOf: target)
      lock.lock()
      files.append([
        "name": target.lastPathComponent,
        "mimeType": mimeType,
        "bytes": FlutterStandardTypedData(bytes: fileData),
        "uri": target.absoluteString,
        "path": target.path,
      ])
      lock.unlock()
    } catch {
      lock.lock()
      files.append([
        "name": target.lastPathComponent,
        "mimeType": mimeType,
        "bytes": FlutterStandardTypedData(bytes: Data()),
        "uri": target.absoluteString,
        "path": target.path,
      ])
      lock.unlock()
    }
  }

  private func mimeTypeForPath(_ path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "gif": return "image/gif"
    case "heic": return "image/heic"
    case "webp": return "image/webp"
    case "mp4": return "video/mp4"
    case "mov": return "video/quicktime"
    default: return "application/octet-stream"
    }
  }
}
