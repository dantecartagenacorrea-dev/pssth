// Capa 2 de corrección: modelo local vía Ollama en la red (opcional, apagado
// por defecto). Sin paquetes externos; falla en silencio y devuelve el texto
// original si el servidor no responde.

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class LlmCleaner {
  LlmCleaner._();
  static final LlmCleaner instance = LlmCleaner._();

  static const _urlKey = 'llm_url';
  static const _modelKey = 'llm_model';
  static const _onKey = 'llm_on';
  static const defaultModel = 'qwen2.5-coder:14b';

  String url = '';
  String model = defaultModel;
  bool enabled = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    url = p.getString(_urlKey) ?? '';
    model = p.getString(_modelKey) ?? defaultModel;
    enabled = p.getBool(_onKey) ?? false;
  }

  Future<void> save({required String url, required String model, required bool enabled}) async {
    this.url = url.trim();
    this.model = model.trim().isEmpty ? defaultModel : model.trim();
    this.enabled = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setString(_urlKey, this.url);
    await p.setString(_modelKey, this.model);
    await p.setBool(_onKey, this.enabled);
  }

  bool get ready => enabled && url.isNotEmpty;

  /// Prueba rápida de conexión: devuelve null si OK, o el error.
  Future<String?> ping() async {
    try {
      final r = await _post('/api/tags', null, timeout: const Duration(seconds: 5), get: true);
      return r == null ? 'Sin respuesta' : null;
    } catch (e) {
      return '$e';
    }
  }

  /// Corrección en segundo plano, mientras se escucha; cada página por
  /// separado para no superar el contexto. Empieza por [startPage] (lo que se
  /// va a leer primero), sigue hasta el final y luego las anteriores. Salta
  /// páginas vacías y las de [skip] (ya corregidas). Si el servidor no
  /// responde no se intenta página por página; si falla a mitad, se detiene.
  Stream<(int, String)> cleanInBackground(List<String> pages, {required int startPage, Set<int> skip = const {}}) async* {
    if (!ready || pages.isEmpty) return;
    if (await ping() != null) return;
    final start = startPage.clamp(0, pages.length - 1);
    final order = [for (var i = start; i < pages.length; i++) i, for (var i = 0; i < start; i++) i];
    for (final i in order) {
      if (skip.contains(i) || pages[i].trim().isEmpty) continue;
      final fixed = await _cleanOne(pages[i]);
      if (fixed == null) return;
      yield (i, fixed);
    }
  }

  /// Texto corregido, el original si la corrección no es fiable, o null si el
  /// servidor falló.
  Future<String?> _cleanOne(String text) async {
    if (text.trim().isEmpty) return text;
    const system =
        'Eres un corrector de transcripciones de voz en español. Corrige SOLO errores de '
        'reconocimiento: nombres propios mal oídos, tildes, palabras pegadas o partidas, '
        'puntuación evidente. No resumas, no cambies el sentido, no agregues ni quites frases. '
        'Responde únicamente con el texto corregido, sin comentarios.';
    try {
      final r = await _post('/api/chat', {
        'model': model,
        'stream': false,
        'options': {'temperature': 0},
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': text},
        ],
      }, timeout: const Duration(seconds: 120));
      if (r == null) return null;
      final content = (r['message'] as Map?)?['content'] as String?;
      if (content == null || content.trim().isEmpty) return text;
      // Protección: si el modelo recortó demasiado, conservar original.
      if (content.length < text.length * 0.7) return text;
      return content.trim();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic>? body,
      {required Duration timeout, bool get = false}) async {
    final base = url.replaceAll(RegExp(r'/v1/?$'), '').replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base$path');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = get ? await client.getUrl(uri) : await client.postUrl(uri);
      if (!get) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(timeout);
      final s = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 300) return null;
      return jsonDecode(s) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}
