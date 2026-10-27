import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show BytesBuilder;

import '../core/app_exception.dart';
import '../domain/html_text.dart';
import 'batch_import.dart' show audioExtensions;
import 'youtube_transcript.dart';

/// Límites de descarga por tipo (un artículo largo pesa menos de 1 MB).
const maxPageBytes = 10 * 1024 * 1024;
const maxPdfBytes = 50 * 1024 * 1024;
const maxAudioBytes = 200 * 1024 * 1024;

/// Menos palabras que esto: la página no tiene texto para leer.
const minPageWords = 30;

/// Lo descargado de un enlace, listo para la biblioteca.
sealed class UrlContent {
  const UrlContent(this.title);
  final String title;
}

/// Página web convertida a texto.
final class UrlText extends UrlContent {
  const UrlText(super.title, this.text);
  final String text;
}

/// PDF o EPUB: se importa como un archivo más.
final class UrlDocument extends UrlContent {
  const UrlDocument(super.title, this.fileName, this.bytes);
  final String fileName;
  final List<int> bytes;
}

/// Audio guardado en [path] (temporal) para transcribirlo.
final class UrlAudio extends UrlContent {
  const UrlAudio(super.title, this.path);
  final String path;
}

/// Convierte lo que pegó el usuario en una URL http(s), o null si no lo es.
Uri? parseUserUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty || s.contains(' ')) return null;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || !uri.host.contains('.')) {
    return null;
  }
  return uri;
}

/// Descarga [uri] y decide qué es por el tipo que declara el servidor (o la
/// extensión). Los audios se guardan en [tempDir].
Future<UrlContent> downloadUrl(
  Uri uri, {
  required Directory tempDir,
  HttpClient? client,
  void Function(int received, int? total)? onProgress,
}) async {
  final http = client ?? HttpClient();
  http.connectionTimeout = const Duration(seconds: 15);
  http.userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
  try {
    // Un video de YouTube no tiene texto en la página: se lee su transcripción.
    final videoId = youtubeVideoId(uri);
    if (videoId != null) {
      final video = await fetchYoutubeTranscript(videoId, http);
      return UrlText(video.title, video.text);
    }
    final req = await http.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) {
      throw AppException('La página respondió con un error (${res.statusCode}). Revisa el enlace.');
    }
    final type = res.headers.contentType?.mimeType.toLowerCase() ?? '';
    final ext = _extension(uri);
    final name = _fileName(uri);

    if (type == 'application/pdf' || ext == 'pdf' || type == 'application/epub+zip' || ext == 'epub') {
      final isPdf = type == 'application/pdf' || ext == 'pdf';
      final bytes = await _read(res, maxPdfBytes, 'El documento', onProgress);
      final fileName = name.contains('.') ? name : '$name.${isPdf ? 'pdf' : 'epub'}';
      return UrlDocument(_withoutExt(fileName), fileName, bytes);
    }
    if (type.startsWith('audio/') || audioExtensions.contains(ext)) {
      final audioExt = audioExtensions.contains(ext) ? ext : _audioExtFor(type);
      final bytes = await _read(res, maxAudioBytes, 'El audio', onProgress);
      final file = File('${tempDir.path}/enlace_${DateTime.now().millisecondsSinceEpoch}.$audioExt');
      await file.writeAsBytes(bytes, flush: true);
      return UrlAudio(_withoutExt(name), file.path);
    }
    if (type.startsWith('video/') || type.startsWith('image/')) {
      throw AppException('Ese enlace es un video o una imagen, no una página con texto.');
    }

    final bytes = await _read(res, maxPageBytes, 'La página', onProgress);
    final charset = res.headers.contentType?.charset?.toLowerCase();
    final body = (charset == 'iso-8859-1' || charset == 'latin1' || charset == 'windows-1252')
        ? latin1.decode(bytes)
        : utf8.decode(bytes, allowMalformed: true);
    if (type == 'text/plain') return UrlText(_withoutExt(name), body.trim());
    // En otro isolate: una página grande no congela la pantalla.
    final page = await Isolate.run(() => extractHtmlText(body));
    if (page.wordCount < minPageWords) {
      throw AppException(
        'No se encontró texto para leer en este enlace. Puede ser un video, una página que '
        'pide iniciar sesión o una que arma el texto con JavaScript.',
      );
    }
    final title = page.title.isNotEmpty ? page.title : uri.host;
    return UrlText(title, page.text);
  } on AppException {
    rethrow;
  } on Exception {
    throw AppException('No se pudo descargar el enlace. Revisa la conexión y que la dirección sea correcta.');
  } finally {
    if (client == null) http.close(force: true);
  }
}

Future<List<int>> _read(
  HttpClientResponse res,
  int limit,
  String what,
  void Function(int received, int? total)? onProgress,
) async {
  final total = res.contentLength > 0 ? res.contentLength : null;
  final tooBig = AppException('$what pesa más de ${limit ~/ (1024 * 1024)} MB, el máximo para un enlace.');
  if (total != null && total > limit) throw tooBig;
  final out = BytesBuilder(copy: false);
  await for (final part in res.timeout(const Duration(seconds: 60))) {
    out.add(part);
    if (out.length > limit) throw tooBig;
    onProgress?.call(out.length, total);
  }
  return out.takeBytes();
}

String _fileName(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty);
  final last = segs.isEmpty ? uri.host : segs.last;
  return Uri.decodeComponent(last).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _extension(Uri uri) {
  final name = _fileName(uri);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String _withoutExt(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String _audioExtFor(String type) => switch (type) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
      'audio/aac' => 'aac',
      _ => 'm4a',
    };
