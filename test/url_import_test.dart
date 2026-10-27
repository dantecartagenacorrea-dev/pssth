import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/core/app_exception.dart';
import 'package:lector_pdf/data/url_import.dart';

void main() {
  late HttpServer server;
  late Directory tmp;
  final articulo = '<html><head><title>Mi nota</title></head><body><nav>Menú</nav><article><p>'
      '${List.filled(10, 'La caja del mes quedó cuadrada después de revisar todo.').join(' ')}'
      '</p></article></body></html>';

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('url');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      switch (req.uri.path) {
        case '/nota':
          res.headers.contentType = ContentType.html;
          res.add(utf8.encode(articulo));
        case '/latin':
          res.headers.contentType = ContentType('text', 'html', charset: 'iso-8859-1');
          res.add(latin1.encode('<p>${List.filled(40, 'canción').join(' ')}</p>'));
        case '/vacia':
          res.headers.contentType = ContentType.html;
          res.write('<body><nav>Home</nav><div id="root"></div><script>x()</script></body>');
        case '/doc.pdf':
          res.headers.contentType = ContentType('application', 'pdf');
          res.add(utf8.encode('%PDF-1.4 falso'));
        case '/clase.mp3':
          res.headers.contentType = ContentType('audio', 'mpeg');
          res.add(List.filled(100, 1));
        case '/video':
          res.headers.contentType = ContentType('video', 'mp4');
          res.add(List.filled(10, 0));
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('una página se convierte en texto con su título', () async {
    final r = await downloadUrl(url('/nota'), tempDir: tmp);
    expect(r, isA<UrlText>());
    expect(r.title, 'Mi nota');
    expect((r as UrlText).text, startsWith('La caja del mes'));
    expect(r.text.contains('Menú'), isFalse);
  });

  test('respeta el charset latin1', () async {
    final r = await downloadUrl(url('/latin'), tempDir: tmp) as UrlText;
    expect(r.text, startsWith('canción canción'));
  });

  test('PDF y audio se tratan como archivos', () async {
    final pdf = await downloadUrl(url('/doc.pdf'), tempDir: tmp) as UrlDocument;
    expect(pdf.fileName, 'doc.pdf');
    expect(pdf.title, 'doc');
    final audio = await downloadUrl(url('/clase.mp3'), tempDir: tmp) as UrlAudio;
    expect(audio.title, 'clase');
    expect(audio.path, endsWith('.mp3'));
    expect(File(audio.path).lengthSync(), 100);
  });

  test('avisa con un mensaje claro en vez de fallar en silencio', () async {
    for (final path in ['/vacia', '/video', '/no-existe']) {
      await expectLater(downloadUrl(url(path), tempDir: tmp), throwsA(isA<AppException>()), reason: path);
    }
  });

  test('parseUserUrl acepta enlaces sin https y rechaza texto suelto', () {
    expect(parseUserUrl('  ejemplo.com/nota ').toString(), 'https://ejemplo.com/nota');
    expect(parseUserUrl('http://a.bo/x')?.scheme, 'http');
    expect(parseUserUrl('hola mundo'), isNull);
    expect(parseUserUrl('ftp://a.com/x'), isNull);
    expect(parseUserUrl(''), isNull);
  });
}
