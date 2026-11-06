import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_exception.dart';
import '../domain/deepseek_quota.dart';

/// DeepSeek por internet, con la clave que la persona pone en Ajustes. La
/// clave se guarda cifrada en el equipo, nunca en el código. Es para probar:
/// antes de publicar, las llamadas deben pasar por un intermediario para no
/// repartir la clave dentro de la app.
class DeepSeekClient {
  DeepSeekClient._();
  static final instance = DeepSeekClient._();

  static const _base = 'https://api.deepseek.com';
  static const model = 'deepseek-chat';
  static const _keyName = 'deepseek_api_key';

  /// Respuesta larga: un resumen completo de una clase de dos horas.
  static const _maxTokens = 8000;
  static const _timeout = Duration(minutes: 5);

  final _storage = const FlutterSecureStorage();
  String _key = '';
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _key = (await _storage.read(key: _keyName)) ?? '';
    _loaded = true;
  }

  bool get hasKey => _key.isNotEmpty;

  Future<void> saveKey(String key) async {
    _key = key.trim();
    _loaded = true;
    if (_key.isEmpty) {
      await _storage.delete(key: _keyName);
    } else {
      await _storage.write(key: _keyName, value: _key);
    }
  }

  /// null si la clave sirve; si no, qué pasa en palabras simples.
  Future<String?> ping() async {
    try {
      await _send('GET', '/models', null, const Duration(seconds: 15));
      return null;
    } on AppException catch (e) {
      return e.message;
    }
  }

  /// Pide a DeepSeek un JSON. [user] debe decir la palabra "JSON" y su forma.
  Future<Object?> json(String system, String user) async {
    final body = await _send('POST', '/chat/completions', {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'response_format': {'type': 'json_object'},
      'temperature': 0.2,
      'max_tokens': _maxTokens,
    }, _timeout);
    usage.add(body);
    return chatJsonContent(body);
  }

  /// El modelo que ve fotos (docs oficiales, 2026-11-06).
  static const visionModel = 'deepseek-flash';

  /// Transcribe una página escaneada mirando la foto ([jpeg]). null si no hay
  /// texto, no hay clave o se llegó al tope de hoy: quien llama usa el lector común.
  Future<String?> readPage(List<int> jpeg) async {
    if (!await available()) return null;
    try {
      final body = await _send('POST', '/chat/completions', {
        'model': visionModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': _readPagePrompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(jpeg)}', 'detail': 'high'},
              },
            ],
          },
        ],
        'temperature': 0,
        'max_tokens': _maxTokens,
      }, _timeout);
      usage.add(body);
      await countUse();
      final text = chatTextContent(body);
      return text.trim() == 'NONE' ? null : text;
    } on AppException {
      return null;
    }
  }

  static const _readPagePrompt =
      'Transcribe exactamente todo el texto de esta hoja, renglón por renglón, en su idioma original. La hoja puede '
      'estar arrugada, torcida o con sombras: lee cada palabra tal como está impresa. No traduzcas, no resumas, no '
      'corrijas ni agregues nada, y no describas la imagen. Responde solo con el texto. Si la imagen no tiene texto, '
      'responde solo: NONE.';

  /// Tokens gastados desde que se abrió la app, para calcular el costo.
  final usage = DeepSeekUsage();

  static const _dayKey = 'deepseek_quota_day';
  static const _usesKey = 'deepseek_quota_uses';

  /// Resúmenes hechos hoy, para el margen diario.
  Future<int> usedToday() async {
    final p = await SharedPreferences.getInstance();
    return usesToday(storedDay: p.getString(_dayKey), storedUses: p.getInt(_usesKey) ?? 0, now: DateTime.now());
  }

  /// Suma un uso y devuelve cuántos van hoy.
  Future<int> countUse() async {
    final used = await usedToday() + 1;
    final p = await SharedPreferences.getInstance();
    await p.setString(_dayKey, dayKey(DateTime.now()));
    await p.setInt(_usesKey, used);
    return used;
  }

  /// Hay clave y no se llegó al tope de hoy.
  Future<bool> available() async {
    await load();
    return hasKey && quotaPhase(await usedToday()) != QuotaPhase.blocked;
  }

  Future<String> _send(String method, String path, Map<String, Object?>? body, Duration timeout) async {
    await load();
    if (!hasKey) throw AppException('Falta la clave de DeepSeek (Ajustes → DeepSeek).');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, Uri.parse('$_base$path'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_key');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final problem = deepSeekError(res.statusCode);
      if (problem != null) throw AppException(problem);
      return text;
    } on HandshakeException {
      throw AppException('No se pudo conectar de forma segura con DeepSeek.');
    } on IOException {
      throw AppException('Sin internet: no se pudo llegar a DeepSeek.');
    } on TimeoutException {
      throw AppException('DeepSeek tardó demasiado en responder. Prueba de nuevo.');
    } finally {
      client.close(force: true);
    }
  }
}

/// Qué decirle a la persona según el código de respuesta; null si salió bien.
String? deepSeekError(int status) {
  if (status < 300) return null;
  return switch (status) {
    401 => 'La clave de DeepSeek no es válida. Revísala en Ajustes → DeepSeek.',
    402 => 'Tu cuenta de DeepSeek no tiene saldo.',
    429 => 'DeepSeek está recibiendo demasiados pedidos. Prueba en un minuto.',
    >= 500 => 'DeepSeek tiene problemas ahora. Prueba más tarde.',
    _ => 'DeepSeek no aceptó el pedido (código $status).',
  };
}

/// Lo que el modelo escribió en la respuesta de chat.
String chatTextContent(String body) {
  try {
    final root = jsonDecode(body);
    final choices = root is Map ? root['choices'] : null;
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) throw const FormatException('Sin contenido');
    if (first is Map && first['finish_reason'] == 'length') {
      throw AppException('La respuesta salió demasiado larga y quedó cortada. Prueba con una parte del documento.');
    }
    return content.trim();
  } on FormatException {
    throw AppException('No se pudo leer la respuesta de DeepSeek. Prueba de nuevo.');
  }
}

/// El JSON que el modelo escribió dentro de la respuesta de chat.
Object? chatJsonContent(String body) {
  final content = chatTextContent(body);
  try {
    return jsonDecode(content);
  } on FormatException {
    throw AppException('No se pudo leer la respuesta de DeepSeek. Prueba de nuevo.');
  }
}

/// Suma de los tokens que informa DeepSeek en cada respuesta.
class DeepSeekUsage {
  int calls = 0;
  int input = 0;
  int cachedInput = 0;
  int output = 0;

  void add(String body) {
    try {
      final root = jsonDecode(body);
      final u = root is Map ? root['usage'] : null;
      if (u is! Map) return;
      calls++;
      input += (u['prompt_tokens'] as num?)?.toInt() ?? 0;
      cachedInput += (u['prompt_cache_hit_tokens'] as num?)?.toInt() ?? 0;
      output += (u['completion_tokens'] as num?)?.toInt() ?? 0;
      // Solo cantidades, nunca texto ni la clave: para medir el gasto en pruebas.
      print('deepseek_uso llamadas=$calls entrada=$input cache=$cachedInput salida=$output'); // ignore: avoid_print
    } on FormatException {
      return;
    }
  }
}
