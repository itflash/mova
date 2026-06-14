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
  private var documentPickerResult: FlutterResult?
  private var photoPickerResult: FlutterResult?
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
        result(FlutterMethodNotImplemented)
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

  private func presentVideoPicker(result: @escaping FlutterResult) {
    guard documentPickerResult == nil && photoPickerResult == nil else {
      result(FlutterError(code: "picker_busy", message: "文件选择器正在打开。", details: nil))
      return
    }
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
    let result = documentPickerResult
    documentPickerResult = nil
    result?(nil)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
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
          DispatchQueue.main.async {
            result?([
              "name": target.lastPathComponent,
              "mimeType": "video/mp4",
              "uri": target.absoluteString,
              "path": target.path,
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
}
