import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/core/app_exception.dart';
import 'package:lector_pdf/services/deepseek_client.dart';

String _chat(Object? content, {String finish = 'stop'}) => jsonEncode({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': finish,
    },
  ],
});

void main() {
  test('lee el JSON que el modelo escribió en la respuesta', () {
    final r = chatJsonContent(_chat('{"brief":"Trata de proyectos.","concepts":[],"ideas":["Paso 1"]}'));
    expect(r, isA<Map<String, dynamic>>());
    expect((r! as Map)['ideas'], ['Paso 1']);
  });

  test('una respuesta cortada por largo se avisa en vez de mostrarse a medias', () {
    expect(() => chatJsonContent(_chat('{"brief":"Tra', finish: 'length')), throwsA(isA<AppException>()));
  });

  test('una respuesta vacía o rota se avisa con un mensaje simple', () {
    expect(() => chatJsonContent(_chat('')), throwsA(isA<AppException>()));
    expect(() => chatJsonContent('no es json'), throwsA(isA<AppException>()));
    expect(() => chatJsonContent(_chat('{roto')), throwsA(isA<AppException>()));
  });

  test('suma los tokens que informa cada respuesta', () {
    final u = DeepSeekUsage();
    String withUsage(int i, int c, int o) => jsonEncode({
      'usage': {'prompt_tokens': i, 'prompt_cache_hit_tokens': c, 'completion_tokens': o},
    });
    u.add(withUsage(1000, 0, 300));
    u.add(withUsage(1200, 900, 400));
    u.add('sin json');
    expect((u.calls, u.input, u.cachedInput, u.output), (2, 2200, 900, 700));
  });

  test('lee el texto corregido de la respuesta', () {
    expect(chatTextContent(_chat('  Hola mundo  ')), 'Hola mundo');
  });

  test('explica en palabras simples los errores de la cuenta', () {
    expect(deepSeekError(200), isNull);
    expect(deepSeekError(401), contains('clave'));
    expect(deepSeekError(402), contains('saldo'));
    expect(deepSeekError(429), contains('minuto'));
    expect(deepSeekError(503), contains('más tarde'));
    expect(deepSeekError(400), contains('400'));
  });

  test('la clave pegada con espacios, saltos, comillas o invisibles queda limpia', () {
    expect(cleanDeepSeekKey('  sk-abc123\n'), 'sk-abc123');
    expect(cleanDeepSeekKey('"sk-abc 123"'), 'sk-abc123');
    expect(cleanDeepSeekKey('Bearer sk-abc123'), 'sk-abc123');
    expect(cleanDeepSeekKey('sk-abc\u200b123\u00a0'), 'sk-abc123');
  });
}
