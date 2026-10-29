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
  });

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
  prune: ['espeak-ng-data'],
);

const whisperBaseModel = ModelSpec(
  id: 'whisper',
  title: 'Transcripción sin conexión',
  url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2',
  sizeBytes: 207557382,
  sha256: '911b2083efd7c0dca2ac3b358b75222660dc09fb716d64fbfc417ba6c99ff3de',
  extractedDir: 'sherpa-onnx-whisper-base',
  requiredFiles: ['base-encoder.int8.onnx', 'base-decoder.int8.onnx', 'base-tokens.txt'],
  prune: ['base-encoder.onnx', 'base-decoder.onnx', 'test_wavs'],
);

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
  Future<bool> hasPendingDownload(ModelSpec spec) => SystemDownload.hasPending('${spec.id}.tar.bz2');

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
        e.osError == null && e.message.isNotEmpty ? e.message : 'Sin conexión. La descarga necesita Internet solo esta vez.',
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
