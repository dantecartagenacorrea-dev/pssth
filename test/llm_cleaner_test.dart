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
    final out = await llm.cleanPages(pages);
    expect(out, pages);
    expect(sw.elapsed, lessThan(const Duration(seconds: 6)));
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
    final out = await llm.cleanPages(pages);
    expect(out.first, 'Texto corregido de la página.');
    expect(out.skip(1).toList(), pages.skip(1).toList());
    expect(chats, 2);
    await server.close(force: true);
  });
}
