import 'dart:convert';
import 'dart:io';

import '../core/app_exception.dart';
import '../domain/html_text.dart' show decodeHtmlEntities;

/// Id de un video de YouTube (watch, youtu.be, shorts, live, embed), o null.
String? youtubeVideoId(Uri uri) {
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.|music\.)'), '');
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
    final segs = uri.pathSegments;
    if (segs.isNotEmpty && segs.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (segs.length >= 2 && const {'shorts', 'live', 'embed', 'v'}.contains(segs.first)) {
      id = segs[1];
    }
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}

/// Elige los subtítulos a leer: español escrito por una persona, luego español
/// automático, luego cualquier otro escrito, luego el primero.
Map<String, dynamic>? pickCaptionTrack(List<Map<String, dynamic>> tracks) {
  if (tracks.isEmpty) return null;
  bool es(Map<String, dynamic> t) => (t['languageCode'] as String? ?? '').startsWith('es');
  bool auto(Map<String, dynamic> t) => t['kind'] == 'asr';
  return tracks.where((t) => es(t) && !auto(t)).firstOrNull ??
      tracks.where(es).firstOrNull ??
      tracks.where((t) => !auto(t)).firstOrNull ??
      tracks.first;
}

/// Texto corrido de una transcripción en XML de YouTube (`<text>…</text>`).
String parseTranscriptXml(String xml) {
  final parts = RegExp(r'<text\b[^>]*>([\s\S]*?)</text>')
      .allMatches(xml)
      // Algunas entidades llegan escapadas dos veces (&amp;#39;).
      .map((m) => decodeHtmlEntities(decodeHtmlEntities(m.group(1)!)))
      .map((s) => s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((s) => s.isNotEmpty && !RegExp(r'^\[[^\]]*\]$').hasMatch(s)); // [Música]
  return parts.join(' ');
}

/// Título y transcripción del video [videoId]. Usa la misma API que la app
/// oficial de Android, que entrega los subtítulos sin iniciar sesión.
Future<({String title, String text})> fetchYoutubeTranscript(String videoId, HttpClient http) async {
  final req = await http.postUrl(Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'));
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({
    'context': {
      'client': {'clientName': 'ANDROID', 'clientVersion': '20.10.38', 'hl': 'es'},
    },
    'videoId': videoId,
  })));
  final res = await req.close().timeout(const Duration(seconds: 30));
  final body = await utf8.decodeStream(res);
  if (res.statusCode >= 400) {
    throw AppException('YouTube respondió con un error (${res.statusCode}). Prueba de nuevo más tarde.');
  }
  final data = jsonDecode(body) as Map<String, dynamic>;
  final status = (data['playabilityStatus'] as Map?)?['status'];
  if (status != null && status != 'OK') {
    throw AppException('Ese video de YouTube no está disponible (privado, borrado o con restricción de edad).');
  }
  final title = ((data['videoDetails'] as Map?)?['title'] as String?)?.trim() ?? 'Video de YouTube';
  final rawTracks = (((data['captions'] as Map?)?['playerCaptionsTracklistRenderer'] as Map?)?['captionTracks']
          as List?) ??
      const [];
  final track = pickCaptionTrack(rawTracks.whereType<Map<String, dynamic>>().toList());
  final baseUrl = track?['baseUrl'] as String?;
  if (baseUrl == null) {
    throw AppException('Ese video no tiene transcripción (ni subtítulos automáticos) para leer.');
  }
  // Sin fmt=srv3 YouTube devuelve el XML simple de <text>.
  final capReq = await http.getUrl(Uri.parse(baseUrl.replaceAll('&fmt=srv3', '')));
  final capRes = await capReq.close().timeout(const Duration(seconds: 30));
  final xml = await utf8.decodeStream(capRes);
  final text = parseTranscriptXml(xml);
  if (capRes.statusCode >= 400 || text.isEmpty) {
    throw AppException('No se pudo descargar la transcripción del video. Prueba de nuevo más tarde.');
  }
  return (title: title, text: text);
}
