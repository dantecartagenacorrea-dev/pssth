import Flutter
import UIKit
import Vision
import NaturalLanguage
import Speech

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeTextTools") {
      NativeTextTools.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechBridge") {
      SpeechBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OpenFileBridge") {
      OpenFileBridge.register(with: registrar)
    }
  }

  /// "Abrir en Lector" desde Archivos, Mail, Safari, hoja Compartir...
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.isFileURL {
      OpenFileBridge.shared.receive(url: url)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}

/// Copia el archivo recibido a un lugar propio y lo entrega a Flutter
/// por el canal "lector/open_file" (método "opened"); si Flutter aún no
/// está listo, queda pendiente hasta que pregunte con "takePending".
final class OpenFileBridge: NSObject, FlutterPlugin {
  static let shared = OpenFileBridge()
  private var channel: FlutterMethodChannel?
  private var pending: [String: String]?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector/open_file", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePending":
      result(pending)
      pending = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func receive(url: URL) {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let name = url.lastPathComponent
    let target = FileManager.default.temporaryDirectory
      .appendingPathComponent("abrir_\(Int(Date().timeIntervalSince1970))_\(name)")
    do {
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.copyItem(at: url, to: target)
    } catch {
      return
    }
    let payload = ["path": target.path, "name": name]
    if let channel = channel {
      channel.invokeMethod("opened", arguments: payload)
    } else {
      pending = payload
    }
  }
}


/// OCR (Vision) y detección de idioma (NaturalLanguage): local, gratuito y offline.
final class NativeTextTools: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "lector/native_text",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(NativeTextTools(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      result(true)
    case "detectLanguage":
      let args = call.arguments as? [String: Any]
      let text = args?["text"] as? String ?? ""
      result(NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue)
    case "recognize":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "Falta path", details: nil))
        return
      }
      let languages = args["languages"] as? [String] ?? []
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let text = try NativeTextTools.recognize(path: path, languages: languages)
          DispatchQueue.main.async { result(text) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func recognize(path: String, languages: [String]) throws -> String {
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      throw NSError(domain: "lector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Imagen no válida"])
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if !languages.isEmpty {
      request.recognitionLanguages = languages
    } else if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = true
    }
    let handler = VNImageRequestHandler(
      cgImage: cg,
      orientation: orientation(image.imageOrientation),
      options: [:]
    )
    try handler.perform([request])
    let observations = request.results ?? []
    return observations
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }

  private static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch o {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}


/// Transcripción de grabaciones SOLO en el dispositivo (sin enviar audio a Apple).
final class SpeechBridge: NSObject {
  private static var task: SFSpeechRecognitionTask?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector/speech", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      let localeId = args?["locale"] as? String ?? "es-ES"
      let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
      switch call.method {
      case "available":
        result(recognizer?.supportsOnDeviceRecognition ?? false)
      case "transcribe":
        guard let path = args?["path"] as? String, let recognizer = recognizer,
              recognizer.supportsOnDeviceRecognition else {
          result(FlutterError(code: "unavailable", message: "Reconocimiento sin conexión no disponible para este idioma.", details: nil))
          return
        }
        SFSpeechRecognizer.requestAuthorization { status in
          DispatchQueue.main.async {
            guard status == .authorized else {
              result(FlutterError(code: "denied", message: "Permiso de reconocimiento de voz denegado.", details: nil))
              return
            }
            let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            var answered = false
            task = recognizer.recognitionTask(with: request) { res, error in
              if answered { return }
              if let res = res, res.isFinal {
                answered = true
                task = nil
                result(res.bestTranscription.formattedString)
              } else if let error = error {
                answered = true
                task = nil
                result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
              }
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
