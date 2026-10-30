import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/services/llm_cleaner.dart';

void main() {
  final llm = LlmCleaner.instance;

  tearDown(() {
    llm.enabled = false;
    llm.url = '';
  });

  test('si el PC no responde, no espera página por página', () async {
    // Puerto cerrado en este equipo: la conexión se rechaza.
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    llm.enabled = true;
    llm.url = 'http://127.0.0.1:$port';
    final pages = List.generate(37, (i) => 'Página $i con texto.');
    final sw = Stopwatch()..start();
    final out = await llm.cleanInBackground(pages, startPage: 0).toList();
    expect(out, isEmpty);
    expect(sw.elapsed, lessThan(const Duration(seconds: 6)));
  });

  test('en segundo plano: empieza por la página actual, salta las ya corregidas y avisa una a una', () async {
    final pedidas = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/api/tags') {
        req.response.write('{"models":[]}');
      } else {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        final texto = ((body['messages'] as List).last as Map)['content'] as String;
        pedidas.add(texto);
        req.response.write(jsonEncode({
          'message': {'content': '$texto (ok)'},
        }));
      }
      await req.response.close();
    });
    llm.enabled = true;
    llm.url = 'http://127.0.0.1:${server.port}';
    final pages = ['Página cero.', 'Página uno.', '', 'Página tres.', 'Página cuatro.'];
    final got = await llm.cleanInBackground(pages, startPage: 3, skip: {4}).toList();
    expect(pedidas, ['Página tres.', 'Página cero.', 'Página uno.']);
    expect(got, [(3, 'Página tres. (ok)'), (0, 'Página cero. (ok)'), (1, 'Página uno. (ok)')]);
    await server.close(force: true);
  });

  test('si falla una página, deja de pedir las siguientes y conserva el original', () async {
    var chats = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/api/tags') {
        req.response.write('{"models":[]}');
      } else {
        chats++;
        req.response.statusCode = chats == 1 ? 200 : 500;
        req.response.write(jsonEncode({
          'message': {'content': 'Texto corregido de la página.'},
        }));
      }
      await req.response.close();
    });
    llm.enabled = true;
    llm.url = 'http://127.0.0.1:${server.port}';
    final pages = ['Texto corejido de la pájina.', 'Segunda pájina.', 'Tercera.', 'Cuarta.'];
    final out = await llm.cleanInBackground(pages, startPage: 0).toList();
    expect(out, [(0, 'Texto corregido de la página.')]);
    expect(chats, 2);
    await server.close(force: true);
  });

  test('el estudio pasa adelante: corta la página en curso y la retoma después', () async {
    final pedidas = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      try {
        if (req.uri.path == '/api/tags') {
          req.response.write('{"models":[]}');
        } else {
          final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
          final texto = ((body['messages'] as List).last as Map)['content'] as String;
          pedidas.add(texto);
          if (body.containsKey('format')) {
            req.response.write(jsonEncode({
              'message': {'content': '{"ok":true}'},
            }));
          } else {
            await Future<void>.delayed(const Duration(seconds: 3)); // página lenta
            req.response.write(jsonEncode({
              'message': {'content': '$texto (ok)'},
            }));
          }
        }
        await req.response.close();
      } on Exception {
        // el cliente cortó el pedido
      }
    });
    llm.enabled = true;
    llm.url = 'http://127.0.0.1:${server.port}';
    final pages = ['Página cero.', 'Página uno.'];
    final cleaning = llm.cleanInBackground(pages, startPage: 0).toList();
    while (pedidas.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final sw = Stopwatch()..start();
    expect(await llm.generateJson('s', 'estudio', {}), {'ok': true});
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(await cleaning, [(0, 'Página cero. (ok)'), (1, 'Página uno. (ok)')]);
    expect(pedidas, ['Página cero.', 'estudio', 'Página cero.', 'Página uno.']);
    await server.close(force: true);
  });
}
