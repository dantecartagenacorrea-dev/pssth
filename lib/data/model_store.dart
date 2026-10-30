import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

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

const kokoroEsModel = ModelSpec(
  id: 'kokoro',
  title: 'Voz natural (español)',
  url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2',
  // sherpa-onnx reemplazó el paquete el 26-10-2026 (mismo contenido de
  // archivos): tamaño y huella del paquete nuevo, comprobados con GitHub.
  sizeBytes: 132353410,
  sha256: '72c347230107ef8a31098ec4d468a605244beef5f1ed00db97efa13518800653',
  extractedDir: 'kokoro-int8-multi-lang-v1_0',
  requiredFiles: ['model.int8.onnx', 'voices.bin', 'tokens.txt'],
  // Datos de espeak-ng (GPL): el paquete los trae, pero la app ya no los usa.
  // Tampoco el diccionario de chino (dict, fst) ni el léxico británico: la voz
  // solo carga el léxico de inglés de EE. UU. y el de chino (≈20 MB menos).
  prune: [
    'espeak-ng-data',
    'dict',
    'lexicon-gb-en.txt',
    'phone-zh.fst',
    'number-zh.fst',
    'date-zh.fst',
  ],
);

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

/// Voces latinoamericanas (Piper, acento mexicano neutro), convertidas por
/// sherpa-onnx. Solo el modelo y sus fonemas: el español se le pasa ya
/// convertido a fonemas, como a la voz natural.
ModelSpec _piperVoice(
  String id,
  String title,
  String name,
  String commit,
  int onnxBytes,
  String onnxSha,
  int tokensBytes,
  String tokensSha,
) {
  final repo = 'https://huggingface.co/csukuangfj/vits-piper-$name/resolve/$commit';
  return ModelSpec(
    id: id,
    title: title,
    url: repo,
    sizeBytes: onnxBytes + tokensBytes,
    sha256: '',
    extractedDir: '',
    requiredFiles: ['$name.onnx', 'tokens.txt'],
    files: [
      ModelFile('$name.onnx', '$repo/$name.onnx', onnxBytes, onnxSha),
      ModelFile('tokens.txt', '$repo/tokens.txt', tokensBytes, tokensSha),
    ],
  );
}

final piperAldModel = _piperVoice(
  'piper-ald',
  'Voz latina: Ald',
  'es_MX-ald-medium',
  '7e97a71dada30e05c6bdb069f64c9e021401bfef',
  63201426,
  'b5e77074846d97651421244167a11d53c762fa41f953de98ab21957a6036eab4',
  921,
  '87c8ef66eae5473ed0cc0366b3964c736ca6c5f676c979522ea31234e47430b9',
);
final piperClaudeModel = _piperVoice(
  'piper-claude',
  'Voz latina: Claude',
  'es_MX-claude-high',
  '802b53b82c60d3de4f8b965314ac99bbec2499b0',
  63122441,
  'f5eceb904655a60141037d957f21e6257efa93b8c8b7b818c0c57396217bcb1c',
  940,
  'ef3a7e4a8d1af0c9d4dc45aaae1a6242ebe24a7ed6f3d025a49eb29682784c6d',
);
final piperVoiceModels = [piperAldModel, piperClaudeModel];

/// Todos los modelos que se pueden instalar en este equipo, en el orden de
/// Voces y modelos. La cola de descargas automáticas usa solo algunos
/// ([ModelQueue.all]); retomar descargas pendientes, todos.
/// Los que traen voces: al instalarlos o quitarlos hay que releer las voces
/// (releerlas corta la frase que se está preparando; con Whisper no hace falta).
bool isVoiceModel(ModelSpec m) => m.id != whisperBaseModel.id;

List<ModelSpec> get optionalModels => [kokoroEsModel, ...piperVoiceModels, whisperBaseModel];

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

class ModelStore extends ChangeNotifier {
  ModelStore(this.root);

  /// Carpeta raíz (p. ej. la carpeta de documentos de la app + `/models`).
  final Directory root;
  final Map<String, Future<void>> _installing = {};
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
  /// se quitó porque no respetaba el formato de resúmenes y preguntas.
  static const _retired = ['qwen3'];

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

  /// Descarga, verifica, extrae y deja el modelo listo. Idempotente: si ya
  /// hay una instalación en curso, espera a esa.
  Future<void> install(ModelSpec spec, {void Function(ModelProgress p)? onProgress}) {
    return _installing[spec.id] ??= _install(spec, onProgress).whenComplete(() {
      _installing.remove(spec.id);
    });
  }

  Future<void> _install(ModelSpec spec, void Function(ModelProgress p)? onProgress) async {
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
        );
      } else {
        await _download(spec.url, archive, spec.sizeBytes, (f) {
          report(ModelProgress(ModelPhase.downloading, f));
        });
      }
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
      _progress.remove(spec.id);
      notifyListeners();
      try {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      } catch (_) {}
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
        );
      } else {
        await _download(f.url, file, f.sizeBytes, progress);
      }
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

  static Future<void> _download(String url, File out, int expected, void Function(double) onFraction) async {
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
        await for (final chunk in res) {
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
