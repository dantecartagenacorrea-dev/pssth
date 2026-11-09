import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../core/perf_log.dart';
import '../platform/system_download.dart';

/// Modelo descargable (voz natural, transcripción). Siempre opcional: la app
/// funciona sin ellos. Se bajan del repositorio oficial de sherpa-onnx (Apache-2.0),
/// se verifican por SHA-256 y quedan en el dispositivo para uso offline.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.title,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.extractedDir,
    required this.requiredFiles,
    this.prune = const [],
    this.files = const [],
  });

  /// Si no está vacía, el modelo se baja archivo por archivo (sin paquete que
  /// extraer): solo lo que la app usa, cada uno verificado por su huella.
  final List<ModelFile> files;

  final String id;
  final String title;
  final String url;

  /// Tamaño de la descarga (comprimida).
  final int sizeBytes;
  final String sha256;

  /// Carpeta que crea el .tar.bz2 al extraerse.
  final String extractedDir;

  /// Archivos que deben existir para considerar el modelo instalado.
  final List<String> requiredFiles;

  /// Archivos/carpetas sobrantes que se borran tras extraer (p. ej. versiones fp32).
  final List<String> prune;

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).round()} MB';
}

/// Un archivo de un modelo que se baja suelto.
class ModelFile {
  const ModelFile(this.name, this.url, this.sizeBytes, this.sha256);
  final String name;
  final String url;
  final int sizeBytes;
  final String sha256;
}

// Solo los tres archivos que usa la app (los mismos del paquete de sherpa-onnx,
// que además trae una versión grande sin usar): 161 MB en vez de 208.
const _whisperRepo =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc';
const whisperBaseModel = ModelSpec(
  id: 'whisper',
  title: 'Transcripción sin conexión',
  url: _whisperRepo,
  sizeBytes: 29120534 + 130672026 + 816730,
  sha256: '',
  extractedDir: '',
  requiredFiles: ['base-encoder.int8.onnx', 'base-decoder.int8.onnx', 'base-tokens.txt'],
  files: [
    ModelFile(
      'base-encoder.int8.onnx',
      '$_whisperRepo/base-encoder.int8.onnx',
      29120534,
      '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
    ),
    ModelFile(
      'base-decoder.int8.onnx',
      '$_whisperRepo/base-decoder.int8.onnx',
      130672026,
      '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
    ),
    ModelFile(
      'base-tokens.txt',
      '$_whisperRepo/base-tokens.txt',
      816730,
      'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
    ),
  ],
);

/// Dictado en español: FastConformer de NVIDIA entrenado con 1424 horas de
/// español, con puntuación y mayúsculas (CC BY 4.0), reducido por sherpa-onnx.
/// Medido en la PC el 08-11 con dos grabaciones reales: entiende más que
/// Parakeet v3 (639 MB) y que Whisper Base, 2,6 veces más rápido que Parakeet
/// y con la mitad de memoria. Solo se baja si se pide.
const dictationModel = ModelSpec(
  id: 'dictado-es',
  title: 'Dictado en español',
  url:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-fast-conformer-transducer-es-1424-int8.tar.bz2',
  sizeBytes: 107246685,
  sha256: 'd6d29ffd560c366da1b177b71e79d8733a9a9910dd1ace282d9bfae94e056210',
  extractedDir: 'sherpa-onnx-nemo-fast-conformer-transducer-es-1424-int8',
  requiredFiles: ['encoder.int8.onnx', 'decoder.int8.onnx', 'joiner.int8.onnx', 'tokens.txt'],
  prune: ['test_wavs'],
);

/// Archivos de la voz incluida en la app, con su tamaño exacto.
const _claudeFiles = {'es_MX-claude-high.fp16.onnx': 31868630, 'tokens.txt': 940};

/// Voz latinoamericana (Piper, acento mexicano neutro), con los pesos en 16 bits:
/// la mitad de tamaño y la velocidad de la original (int8 era 4 veces más lenta). Viene
/// con la app y es la voz inicial: no se descarga ni se puede quitar. Solo el
/// modelo y sus fonemas: el español se le pasa ya convertido a fonemas.
final piperClaudeModel = ModelSpec(
  id: 'piper-claude',
  title: 'Voz latina: Claude',
  url: '',
  sizeBytes: _claudeFiles.values.reduce((a, b) => a + b),
  sha256: '',
  extractedDir: '',
  requiredFiles: _claudeFiles.keys.toList(),
);
const _supertonicRepo =
    'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-tts-int8-2026-03-06/resolve/5dec5897b86e2b293790eedb5e1f561a3295651f';

/// Supertonic 3 (Supertone; modelo OpenRAIL-M, código MIT), versión reducida de
/// sherpa-onnx: diez voces en un paquete; la app usa la más joven (la 2). En la
/// PC el 08-11: unas 25 veces más rápida que el tiempo real y 42/43 palabras
/// entendidas por el dictado. Lee el texto directo, sin fonemas.
const supertonicModel = ModelSpec(
  id: 'supertonic',
  title: 'Voz joven: Luna',
  url: _supertonicRepo,
  sizeBytes: 1521526 + 27431318 + 40686657 + 25977132 + 8699 + 262144 + 517168,
  sha256: '',
  extractedDir: '',
  requiredFiles: [
    'duration_predictor.int8.onnx',
    'text_encoder.int8.onnx',
    'vector_estimator.int8.onnx',
    'vocoder.int8.onnx',
    'tts.json',
    'unicode_indexer.bin',
    'voice.bin',
  ],
  files: [
    ModelFile(
      'duration_predictor.int8.onnx',
      '$_supertonicRepo/duration_predictor.int8.onnx',
      1521526,
      '6d556b3691165c364be91dc0bd894656b5949f5acd2750d8ec2f954010845011',
    ),
    ModelFile(
      'text_encoder.int8.onnx',
      '$_supertonicRepo/text_encoder.int8.onnx',
      27431318,
      'dd5f535ed629f7df86071043e15f541ce1b2ab7f1bdbce4c7892b307bca79fa3',
    ),
    ModelFile(
      'vector_estimator.int8.onnx',
      '$_supertonicRepo/vector_estimator.int8.onnx',
      40686657,
      '9cce89801068dc998719fbc91777f99f3f4d16ee36592281f8703f32e305daa2',
    ),
    ModelFile(
      'vocoder.int8.onnx',
      '$_supertonicRepo/vocoder.int8.onnx',
      25977132,
      'db99c36fb871fbfb128b903662995f2e22213e875f2434f319f8d10ee0f10e90',
    ),
    ModelFile(
      'tts.json',
      '$_supertonicRepo/tts.json',
      8699,
      'ee531d9af9b80438a2ed703e22155ee6c83b12595ab22fd3bb6de94c7502fe96',
    ),
    ModelFile(
      'unicode_indexer.bin',
      '$_supertonicRepo/unicode_indexer.bin',
      262144,
      '06557ec23778a2c67130a99e28f5f550b9598fc1f04049cbb35d864549913154',
    ),
    ModelFile(
      'voice.bin',
      '$_supertonicRepo/voice.bin',
      517168,
      '12e0919ffc641ff20858026a4c655fbd9e5c414800bb1b756c9d4011e2536325',
    ),
  ],
);

/// Hablante de [supertonicModel] que usa la app (la voz 2, la más aguda).
const supertonicSpeaker = 1;

final piperVoiceModels = [supertonicModel];

const _formulaRelease = 'https://github.com/dantecartagenacorrea-dev/pssth/releases/download/formula-model-v1';

/// Lee fórmulas de una foto: Pix2Text MFR 1.5 (MIT, © 2022 BreezeDeus) con los
/// pesos reducidos a 8 bits, publicado en los lanzamientos de este repositorio.
/// Se baja solo si se pide: no entra en la cola automática.
const formulaModel = ModelSpec(
  id: 'formula-int8',
  title: 'Lector de fórmulas',
  url: _formulaRelease,
  sizeBytes: 23119577 + 8507280 + 113168,
  sha256: '',
  extractedDir: '',
  requiredFiles: ['encoder_model.onnx', 'decoder_model.onnx', 'tokenizer.json'],
  files: [
    ModelFile(
      'encoder_model.onnx',
      '$_formulaRelease/formula-encoder-int8.onnx',
      23119577,
      'd8470acbf0a8735cc3b42084d30e0fd5f261996dcc28ce8c0b8dcb4d86cde2d2',
    ),
    ModelFile(
      'decoder_model.onnx',
      '$_formulaRelease/formula-decoder-int8.onnx',
      8507280,
      '1747fe9355da3d5f2216be31c94fe1ec81fdff1b614ff0e854ba0dc82977f171',
    ),
    ModelFile(
      'tokenizer.json',
      '$_formulaRelease/formula-tokenizer.json',
      113168,
      '4ffbeb2143e6a38324bb6111b7a8109530d38a076a8439aa5777535f0a32758a',
    ),
  ],
);

const _unwarpRepo = 'https://huggingface.co/PaddlePaddle/UVDoc_onnx/resolve/3bcf535371727d11e783101f79a504c68848aae3';

/// Aplana la foto de una hoja arrugada: UVDoc (Apache-2.0). Se baja solo si se pide.
const unwarpModel = ModelSpec(
  id: 'unwarp',
  title: 'Aplanador de hojas',
  url: _unwarpRepo,
  sizeBytes: 31684150,
  sha256: '',
  extractedDir: '',
  requiredFiles: ['inference.onnx'],
  files: [
    ModelFile(
      'inference.onnx',
      '$_unwarpRepo/inference.onnx',
      31684150,
      '54cab30dc2cf347b4f3d6971c833b1c3d84f5ef17280f1f6d15796bff20e63d6',
    ),
  ],
);

/// Todos los modelos que se pueden instalar en este equipo, en el orden de
/// Voces y modelos. La cola de descargas automáticas usa solo algunos
/// ([ModelQueue.all]); retomar descargas pendientes, todos.
/// Los que traen voces: al instalarlos o quitarlos hay que releer las voces
/// (releerlas corta la frase que se está preparando; con Whisper no hace falta).
bool isVoiceModel(ModelSpec m) =>
    m.id != whisperBaseModel.id && m.id != dictationModel.id && m.id != formulaModel.id && m.id != unwarpModel.id;

List<ModelSpec> get optionalModels => [
  ...piperVoiceModels,
  // En Android transcribe el dictado en español; Whisper queda para iPhone
  // (idiomas que el iPhone no transcribe sin conexión).
  if (Platform.isIOS) whisperBaseModel,
  if (Platform.isAndroid) dictationModel,
  // En iPhone todavía no hay cómo correrlo: no se ofrece.
  if (Platform.isAndroid) formulaModel,
  if (Platform.isAndroid) unwarpModel,
];

enum ModelPhase { downloading, verifying, extracting, done }

class ModelProgress {
  const ModelProgress(this.phase, [this.fraction]);
  final ModelPhase phase;

  /// 0-1 durante la descarga; null en las demás fases.
  final double? fraction;

  String get label => switch (phase) {
    ModelPhase.downloading => 'Descargando ${((fraction ?? 0) * 100).round()} %',
    ModelPhase.verifying => 'Comprobando…',
    ModelPhase.extracting => 'Instalando…',
    ModelPhase.done => 'Instalado',
  };
}

class ModelInstallException implements Exception {
  ModelInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// La persona canceló la instalación: no es un error que haya que mostrar.
class ModelInstallCancelled extends ModelInstallException {
  ModelInstallCancelled() : super('Descarga cancelada.');
}

class ModelStore extends ChangeNotifier {
  ModelStore(this.root);

  /// Carpeta raíz (p. ej. la carpeta de documentos de la app + `/models`).
  final Directory root;
  final Map<String, Future<void>> _installing = {};

  /// Instalaciones que la persona pidió cancelar.
  final Set<String> _cancelled = {};

  /// Cancela la instalación en curso de [spec]: se borra lo descargado.
  void cancel(ModelSpec spec) {
    if (!isInstalling(spec)) return;
    _cancelled.add(spec.id);
    notifyListeners();
  }

  bool _stopped(ModelSpec spec) => _cancelled.contains(spec.id);

  void _checkStop(ModelSpec spec) {
    if (_stopped(spec)) throw ModelInstallCancelled();
  }
  final Map<String, ModelProgress> _progress = {};

  /// Avance de la instalación en curso (null si no se está instalando): la
  /// pantalla lo vuelve a mostrar al reabrirse.
  ModelProgress? progressOf(ModelSpec spec) => _progress[spec.id];

  /// ¿Quedó una descarga empezada (p. ej. con la app cerrada) para retomar?
  Future<bool> hasPendingDownload(ModelSpec spec) async {
    if (spec.files.isEmpty) return SystemDownload.hasPending('${spec.id}.tar.bz2', expectedBytes: spec.sizeBytes);
    for (final f in spec.files) {
      if (await SystemDownload.hasPending(_fileKey(spec, f), expectedBytes: f.sizeBytes)) return true;
    }
    return false;
  }

  static String _fileKey(ModelSpec spec, ModelFile f) => '${spec.id}-${f.name}';

  Directory dirFor(ModelSpec spec) => Directory('${root.path}/${spec.id}');

  bool isInstalled(ModelSpec spec) {
    final d = dirFor(spec);
    return spec.requiredFiles.every((f) => FileSystemEntity.typeSync('${d.path}/$f') != FileSystemEntityType.notFound);
  }

  bool isInstalling(ModelSpec spec) => _installing.containsKey(spec.id);

  Future<int> installedBytes(ModelSpec spec) async {
    final d = dirFor(spec);
    if (!await d.exists()) return 0;
    var total = 0;
    await for (final e in d.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> remove(ModelSpec spec) async {
    final d = dirFor(spec);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Modelos que la app ya no usa: la IA chica de estudio (Qwen3, 330 MB)
  /// se quitó porque no respetaba el formato de resúmenes y preguntas; la voz
  /// Piper Ald (62 MB), porque la app deja solo seis voces; el lector de fórmulas
  /// sin reducir (120 MB), porque el de 32 MB acierta igual; Parakeet (639 MB),
  /// porque el dictado en español entiende más con 136 MB.
  /// Kokoro (Dora y Alex, 164 MB), porque Luna la reemplaza y en equipos
  /// modestos no alcanzaba a leer al ritmo; Whisper en Android, porque el
  /// dictado en español entiende más con menos.
  static List<String> get _retired => [
    'whisper-small',
    'qwen3',
    'piper-ald',
    'formula',
    'parakeet',
    'kokoro',
    if (Platform.isAndroid) 'whisper',
  ];

  /// Borra lo que quedó instalado de [_retired] y, en los modelos ya
  /// instalados, lo que [ModelSpec.prune] dice que no se usa (las instalaciones
  /// anteriores a cada poda lo conservaban).
  Future<void> removeRetired() async {
    for (final id in _retired) {
      final d = Directory('${root.path}/$id');
      try {
        if (await d.exists()) await d.delete(recursive: true);
      } on FileSystemException {
        // se reintenta la próxima vez que se abra la app
      }
    }
    for (final spec in optionalModels) {
      for (final p in spec.prune) {
        final path = '${dirFor(spec).path}/$p';
        try {
          switch (FileSystemEntity.typeSync(path)) {
            case FileSystemEntityType.file:
              await File(path).delete();
            case FileSystemEntityType.directory:
              await Directory(path).delete(recursive: true);
            default:
          }
        } on FileSystemException {
          // se reintenta la próxima vez
        }
      }
    }
  }

  /// Deja lista la voz que viene con la app: el motor necesita archivos, no
  /// recursos empaquetados. Solo copia lo que falta y borra la versión grande
  /// que se bajaba antes. Si falla, la app sigue con la voz del sistema.
  Future<void> installBundledVoice(Future<ByteData> Function(String asset) load) async {
    final dir = dirFor(piperClaudeModel);
    try {
      await dir.create(recursive: true);
      for (final name in ['es_MX-claude-high.onnx', 'es_MX-claude-high.int8.onnx']) {
        final old = File('${dir.path}/$name');
        if (await old.exists()) await old.delete();
      }
      for (final MapEntry(key: name, value: size) in _claudeFiles.entries) {
        final target = File('${dir.path}/$name');
        if (await target.exists() && await target.length() == size) continue;
        final data = await load('assets/voz/$name');
        final part = File('${target.path}.part');
        await part.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
        await part.rename(target.path);
      }
    } on Exception catch (e) {
      perfLog('voz incluida: no se pudo preparar: $e');
    }
  }

  /// Descarga, verifica, extrae y deja el modelo listo. Idempotente: si ya
  /// hay una instalación en curso, espera a esa.
  Future<void> install(ModelSpec spec, {void Function(ModelProgress p)? onProgress}) {
    return _installing[spec.id] ??= _install(spec, onProgress).whenComplete(() {
      _installing.remove(spec.id);
    });
  }

  Future<void> _install(ModelSpec spec, void Function(ModelProgress p)? onProgress) async {
    _cancelled.remove(spec.id);
    await root.create(recursive: true);
    final tmp = Directory('${root.path}/.tmp_${spec.id}');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    var archive = File('${tmp.path}/model.tar.bz2');
    void report(ModelProgress p) {
      _progress[spec.id] = p;
      onProgress?.call(p);
      notifyListeners();
    }

    try {
      report(const ModelProgress(ModelPhase.downloading, 0));
      if (spec.files.isNotEmpty) {
        await _installFiles(spec, tmp, report);
        return;
      }
      if (SystemDownload.available) {
        // Android: el gestor del sistema sigue aunque la app se cierre.
        archive = await SystemDownload.fetch(
          spec.url,
          '${spec.id}.tar.bz2',
          title: 'PSSTH! · ${spec.title}',
          expectedBytes: spec.sizeBytes,
          onFraction: (f) => report(ModelProgress(ModelPhase.downloading, f)),
          shouldStop: () => _stopped(spec),
        );
      } else {
        await _download(spec.url, archive, spec.sizeBytes, (f) {
          report(ModelProgress(ModelPhase.downloading, f));
        }, shouldStop: () => _stopped(spec));
      }
      _checkStop(spec);
      report(const ModelProgress(ModelPhase.verifying));
      final digest = await sha256.bind(archive.openRead()).first;
      if (digest.toString() != spec.sha256) {
        await SystemDownload.forget('${spec.id}.tar.bz2');
        throw ModelInstallException('La descarga llegó dañada. Inténtalo de nuevo.');
      }

      report(const ModelProgress(ModelPhase.extracting));
      await compute(_extract, [archive.path, tmp.path]);
      final extracted = Directory('${tmp.path}/${spec.extractedDir}');
      if (!await extracted.exists()) {
        throw ModelInstallException('El paquete no tiene el contenido esperado.');
      }
      for (final p in spec.prune) {
        final t = FileSystemEntity.typeSync('${extracted.path}/$p');
        if (t == FileSystemEntityType.file) await File('${extracted.path}/$p').delete();
        if (t == FileSystemEntityType.directory) await Directory('${extracted.path}/$p').delete(recursive: true);
      }
      final target = dirFor(spec);
      if (await target.exists()) await target.delete(recursive: true);
      await extracted.rename(target.path);
      if (!isInstalled(spec)) {
        await target.delete(recursive: true);
        throw ModelInstallException('Faltan archivos en el modelo descargado.');
      }
      await SystemDownload.forget('${spec.id}.tar.bz2'); // borra el paquete ya instalado
      report(const ModelProgress(ModelPhase.done));
    } on ModelInstallException {
      rethrow;
    } on DownloadCancelled {
      throw ModelInstallCancelled();
    } on TimeoutException {
      throw ModelInstallException(kDownloadStalled);
    } on SocketException catch (e) {
      throw ModelInstallException(
        e.osError == null && e.message.isNotEmpty
            ? e.message
            : 'Sin conexión. La descarga necesita Internet solo esta vez.',
      );
    } on PlatformException catch (e) {
      throw ModelInstallException(e.message ?? 'No se pudo descargar.');
    } catch (e) {
      throw ModelInstallException('No se pudo instalar: $e');
    } finally {
      if (_stopped(spec)) await _forgetDownloads(spec);
      _cancelled.remove(spec.id);
      _progress.remove(spec.id);
      notifyListeners();
      try {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Borra lo que haya quedado de las descargas de [spec] (al cancelar).
  Future<void> _forgetDownloads(ModelSpec spec) async {
    if (spec.files.isEmpty) {
      await SystemDownload.forget('${spec.id}.tar.bz2');
    }
    for (final f in spec.files) {
      await SystemDownload.forget(_fileKey(spec, f));
    }
  }

  /// Baja cada archivo (el avance cuenta los bytes de todos), lo verifica y
  /// recién con todos bien los deja en la carpeta del modelo.
  Future<void> _installFiles(ModelSpec spec, Directory tmp, void Function(ModelProgress) report) async {
    final total = spec.files.fold<int>(0, (a, f) => a + f.sizeBytes);
    var before = 0;
    final ready = <ModelFile, File>{};
    for (final f in spec.files) {
      void progress(double x) => report(ModelProgress(ModelPhase.downloading, (before + x * f.sizeBytes) / total));
      var file = File('${tmp.path}/${f.name}');
      if (SystemDownload.available) {
        file = await SystemDownload.fetch(
          f.url,
          _fileKey(spec, f),
          title: 'PSSTH! · ${spec.title}',
          expectedBytes: f.sizeBytes,
          onFraction: progress,
          shouldStop: () => _stopped(spec),
        );
      } else {
        await _download(f.url, file, f.sizeBytes, progress, shouldStop: () => _stopped(spec));
      }
      _checkStop(spec);
      before += f.sizeBytes;
      ready[f] = file;
    }
    report(const ModelProgress(ModelPhase.verifying));
    for (final MapEntry(key: f, value: file) in ready.entries) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != f.sha256) {
        await SystemDownload.forget(_fileKey(spec, f));
        throw ModelInstallException('La descarga llegó dañada. Inténtalo de nuevo.');
      }
    }
    report(const ModelProgress(ModelPhase.extracting));
    final target = dirFor(spec);
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    for (final MapEntry(key: f, value: file) in ready.entries) {
      // Se copia con otro nombre y se renombra al final: a medio copiar el
      // modelo no parece instalado (la IA intentaba cargar un archivo cortado).
      final part = await file.copy('${target.path}/${f.name}.part');
      await part.rename('${target.path}/${f.name}');
      await SystemDownload.forget(_fileKey(spec, f));
    }
    report(const ModelProgress(ModelPhase.done));
  }

  /// Sin datos en este tiempo, la descarga se da por detenida.
  static const _idleLimit = Duration(seconds: 60);

  static Future<void> _download(
    String url,
    File out,
    int expected,
    void Function(double) onFraction, {
    bool Function()? shouldStop,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      req.maxRedirects = 8;
      final res = await req.close();
      if (res.statusCode != 200) {
        throw ModelInstallException('El servidor respondió ${res.statusCode}.');
      }
      final total = res.contentLength > 0 ? res.contentLength : expected;
      var received = 0;
      final sink = out.openWrite();
      try {
        await for (final chunk in res.timeout(_idleLimit)) {
          if (shouldStop?.call() ?? false) throw const DownloadCancelled();
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onFraction((received / total).clamp(0, 1).toDouble());
        }
      } finally {
        await sink.close();
      }
      if (received < expected ~/ 2) {
        throw ModelInstallException('La descarga se interrumpió.');
      }
    } finally {
      client.close(force: true);
    }
  }
}

Future<void> _extract(List<String> args) async {
  await extractFileToDisk(args[0], args[1]);
}
