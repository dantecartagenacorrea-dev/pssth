import Flutter
import UIKit
import Vision
import NaturalLanguage
import Speech
import AVFoundation
import VisionKit
#if canImport(FoundationModels)
import FoundationModels
#endif

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioExportBridge") {
      AudioExportBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareBridge") {
      ShareBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DocumentScanBridge") {
      DocumentScanBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StudyAIBridge") {
      StudyAIBridge.register(with: registrar)
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
  /// Dart ya escucha el canal (lo sabemos cuando pide "takePending").
  /// Antes de eso un "opened" se perdería: el archivo queda pendiente.
  private var dartListo = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector/open_file", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePending":
      dartListo = true
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
    if let channel = channel, dartListo {
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
    case "requestPersonalVoice":
      if #available(iOS 17.0, *) {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
          DispatchQueue.main.async { result(status == .authorized) }
        }
      } else {
        result(false)
      }
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
      let correction = args["languageCorrection"] as? Bool ?? true
      let minHeight = (args["minimumTextHeight"] as? NSNumber)?.floatValue
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let text = try NativeTextTools.recognize(
            path: path, languages: languages, correction: correction, minimumTextHeight: minHeight
          )
          DispatchQueue.main.async { result(text) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "recognizeLines":
      // Cada línea con su lugar en la foto (fracciones 0–1, origen arriba a la
      // izquierda), para poner el texto buscable encima de la imagen en un PDF.
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "Falta path", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let lines = try NativeTextTools.recognizeLines(path: path)
          DispatchQueue.main.async { result(lines) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "barcodes":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "Falta path", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let codes = (try? NativeTextTools.barcodes(path: path)) ?? []
        DispatchQueue.main.async { result(codes) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Contenido de los códigos QR (y otros 2D) que aparecen en la imagen.
  private static func barcodes(path: String) throws -> [String] {
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else { return [] }
    let request = VNDetectBarcodesRequest()
    let handler = VNImageRequestHandler(
      cgImage: cg,
      orientation: orientation(image.imageOrientation),
      options: [:]
    )
    try handler.perform([request])
    return (request.results ?? []).compactMap { $0.payloadStringValue }
  }

  private static func recognize(
    path: String, languages: [String], correction: Bool = true, minimumTextHeight: Float? = nil
  ) throws -> String {
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      throw NSError(domain: "lector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Imagen no válida"])
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = correction
    if let minimumTextHeight { request.minimumTextHeight = minimumTextHeight }
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

  private static func recognizeLines(path: String) throws -> [String: Any] {
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      throw NSError(domain: "lector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Imagen no válida"])
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(iOS 16.0, *) { request.automaticallyDetectsLanguage = true }
    let handler = VNImageRequestHandler(
      cgImage: cg,
      orientation: orientation(image.imageOrientation),
      options: [:]
    )
    try handler.perform([request])
    // Vision mide desde abajo a la izquierda; el PDF se arma desde arriba.
    let lines: [[String: Any]] = (request.results ?? []).compactMap { obs in
      guard let text = obs.topCandidates(1).first?.string else { return nil }
      let b = obs.boundingBox
      return ["text": text, "left": b.minX, "top": 1 - b.maxY, "width": b.width, "height": b.height]
    }
    return ["width": Int(image.size.width), "height": Int(image.size.height), "lines": lines]
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

/// Convierte un audio local (CAF/WAV de la voz del sistema o de Kokoro) a M4A
/// para compartirlo como nota de voz. Canal "lector/audio_export", método "toM4a".
final class AudioExportBridge: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector/audio_export", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AudioExportBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "toM4a",
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          let out = args["out"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      result(nil)
      return
    }
    let outURL = URL(fileURLWithPath: out)
    try? FileManager.default.removeItem(at: outURL)
    session.outputURL = outURL
    session.outputFileType = .m4a
    session.exportAsynchronously {
      DispatchQueue.main.async {
        result(session.status == .completed ? out : nil)
      }
    }
  }
}

/// Hoja Compartir del sistema para un archivo local. Canal "lector/share", método "shareFile".
final class ShareBridge: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector/share", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ShareBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "shareFile",
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    var items: [Any] = [URL(fileURLWithPath: path)]
    if let text = args["text"] as? String, !text.isEmpty { items.append(text) }
    DispatchQueue.main.async {
      guard let root = UIApplication.shared.connectedScenes
        .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
        .first?.rootViewController else {
        result(false)
        return
      }
      let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
      if let pop = vc.popoverPresentationController {
        pop.sourceView = root.view
        pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        pop.permittedArrowDirections = []
      }
      vc.completionWithItemsHandler = { _, _, _, _ in result(true) }
      root.present(vc, animated: true)
    }
  }
}

/// Escáner de documentos del sistema (VisionKit, el mismo de Notas): detecta los
/// bordes, endereza y permite varias páginas. Canal "lector/scan", método
/// "scan": devuelve las rutas de las páginas en JPEG (vacío si se cancela).
final class DocumentScanBridge: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector/scan", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DocumentScanBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "scan" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard VNDocumentCameraViewController.isSupported else {
      result(FlutterError(code: "unsupported", message: "Este equipo no puede escanear documentos.", details: nil))
      return
    }
    DispatchQueue.main.async {
      guard let root = UIApplication.shared.connectedScenes
        .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
        .first?.rootViewController else {
        result(FlutterError(code: "no_view", message: "No se pudo abrir la cámara.", details: nil))
        return
      }
      self.pending = result
      let scanner = VNDocumentCameraViewController()
      scanner.delegate = self
      root.present(scanner, animated: true)
    }
  }

  private func finish(_ value: Any?, _ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    pending?(value)
    pending = nil
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("escaneo", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    var paths: [String] = []
    for i in 0..<scan.pageCount {
      let url = dir.appendingPathComponent("pagina_\(stamp)_\(i).jpg")
      if let data = scan.imageOfPage(at: i).jpegData(compressionQuality: 0.92), (try? data.write(to: url)) != nil {
        paths.append(url.path)
      }
    }
    finish(paths, controller)
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    finish([String](), controller)
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    finish(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil), controller)
  }
}

/// IA de Apple en el propio iPhone (iOS 26 con Apple Intelligence) para
/// resúmenes y preguntas de estudio. Canal "lector/ai": "status", "summarize"
/// (texto → conceptos, ideas y resumen breve) y "quiz" (texto, cantidad,
/// nivel → preguntas de opción múltiple). Sin red: el texto no sale del equipo.
final class StudyAIBridge: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector/ai", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(StudyAIBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      StudyAI.handle(call, result: result)
      return
    }
    #endif
    if call.method == "status" {
      result("unsupported")
    } else {
      result(FlutterError(code: "unsupported", message: "Esta función necesita iOS 26 con Apple Intelligence.", details: nil))
    }
  }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct StudyConcept {
  @Guide(description: "Concepto o término clave, tal como aparece en el texto")
  var term: String
  @Guide(description: "Qué significa según el texto, en una frase clara y breve")
  var meaning: String
}

@available(iOS 26.0, *)
@Generable
struct StudySummary {
  @Guide(description: "Entre tres y seis conceptos clave que un estudiante debe dominar")
  var concepts: [StudyConcept]
  @Guide(description: "Entre tres y seis ideas principales, una frase cada una, en el orden del texto")
  var ideas: [String]
  @Guide(description: "Resumen breve de dos a cuatro frases que explique de qué trata el texto")
  var brief: String
}

@available(iOS 26.0, *)
@Generable
struct StudyQuestion {
  @Guide(description: "Pregunta clara sobre el contenido del texto")
  var question: String
  @Guide(description: "Exactamente cuatro respuestas posibles, una sola correcta, todas creíbles")
  var options: [String]
  @Guide(description: "Posición de la respuesta correcta dentro de options: 0, 1, 2 o 3")
  var answer: Int
  @Guide(description: "Por qué esa respuesta es la correcta, apoyándose en el texto")
  var explanation: String
}

@available(iOS 26.0, *)
@Generable
struct StudyQuiz {
  @Guide(description: "Las preguntas pedidas, sin repetir")
  var questions: [StudyQuestion]
}

@available(iOS 26.0, *)
enum StudyAI {
  static let tutor = """
    Eres un tutor que ayuda a estudiantes a comprender lo que leen. Respondes en el \
    mismo idioma del texto, con frases claras y precisas. Usas solo lo que dice el \
    texto: nunca inventas datos, nombres ni cifras.
    """

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status":
      result(status())
    case "summarize":
      guard let text = args["text"] as? String else {
        result(FlutterError(code: "bad_args", message: "Falta el texto.", details: nil))
        return
      }
      run(result) { try await summarize(text) }
    case "quiz":
      guard let text = args["text"] as? String else {
        result(FlutterError(code: "bad_args", message: "Falta el texto.", details: nil))
        return
      }
      let count = args["count"] as? Int ?? 5
      let level = args["level"] as? String ?? "basico"
      run(result) { try await quiz(text, count: count, level: level) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func status() -> String {
    switch SystemLanguageModel.default.availability {
    case .available:
      return "available"
    case .unavailable(.deviceNotEligible):
      return "deviceNotEligible"
    case .unavailable(.appleIntelligenceNotEnabled):
      return "appleIntelligenceNotEnabled"
    case .unavailable(.modelNotReady):
      return "modelNotReady"
    default:
      return "unavailable"
    }
  }

  private static func run(_ result: @escaping FlutterResult, _ work: @escaping () async throws -> Any) {
    Task {
      do {
        let value = try await work()
        DispatchQueue.main.async { result(value) }
      } catch {
        let message = "\(error)"
        DispatchQueue.main.async {
          result(FlutterError(code: "ai_failed", message: message, details: nil))
        }
      }
    }
  }

  static func summarize(_ text: String) async throws -> [String: Any] {
    let session = LanguageModelSession(instructions: tutor)
    let prompt = """
      Resume este texto para estudiarlo: identifica los conceptos clave con su \
      significado, las ideas principales y escribe un resumen breve.

      TEXTO:
      \(text)
      """
    let s = try await session.respond(to: prompt, generating: StudySummary.self).content
    return [
      "concepts": s.concepts.map { ["term": $0.term, "meaning": $0.meaning] },
      "ideas": s.ideas,
      "brief": s.brief,
    ]
  }

  static func quiz(_ text: String, count: Int, level: String) async throws -> [[String: Any]] {
    let kind: String
    switch level {
    case "experto":
      kind = "de nivel experto: que exijan inferir, comparar, aplicar o evaluar ideas del texto"
    case "medio":
      kind = "de nivel medio: sobre relaciones, causas, consecuencias y el sentido de las ideas"
    default:
      kind = "de nivel básico: sobre datos, definiciones y hechos que el texto dice explícitamente"
    }
    let session = LanguageModelSession(instructions: tutor)
    let prompt = """
      Escribe \(count) preguntas de opción múltiple \(kind). Cada una con cuatro \
      respuestas y una sola correcta; las incorrectas deben ser creíbles. Cubre \
      partes distintas del texto y no repitas preguntas.

      TEXTO:
      \(text)
      """
    let q = try await session.respond(to: prompt, generating: StudyQuiz.self).content
    return q.questions.map { item -> [String: Any] in
      ["question": item.question, "options": item.options, "answer": item.answer, "explanation": item.explanation]
    }
  }
}
#endif
