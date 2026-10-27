import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/html_text.dart';

void main() {
  final parrafo = List.filled(20, 'El contador revisa las cuentas del mes con calma.').join(' ');

  test('se queda con el artículo y descarta menú, scripts y pie', () {
    final html = '''
<html><head><title>Cierre de mes &mdash; Blog</title>
<style>p{color:red}</style><script>var x = "no leer";</script></head>
<body>
<nav><a href="/">Inicio</a> <a href="/precios">Precios</a></nav>
<header>Suscríbete</header>
<article><h1>Cierre de mes</h1><p>$parrafo</p><p>Segundo p&aacute;rrafo con <a href="#">enlace</a>, y m&aacute;s.</p>
<ul><li>Uno</li><li>Dos</li></ul></article>
<aside>Publicidad</aside><footer>© 2026</footer>
</body></html>''';
    final r = extractHtmlText(html);
    expect(r.title, 'Cierre de mes — Blog');
    expect(r.text, startsWith('Cierre de mes\n\nEl contador'));
    expect(r.text, contains('Segundo párrafo con enlace, y más.'));
    expect(r.text, contains('Uno\n\nDos'));
    for (final ruido in ['Inicio', 'Precios', 'no leer', 'Suscríbete', 'Publicidad', '2026', 'color']) {
      expect(r.text.contains(ruido), isFalse, reason: ruido);
    }
  });

  test('sin <article> usa el cuerpo y prefiere og:title', () {
    final html = '<meta property="og:title" content="Nota &quot;breve&quot;"><title>x</title>'
        '<body><div>Primera línea</div><div>Segunda&nbsp;línea &#191;sí? &#x00e9;</div></body>';
    final r = extractHtmlText(html);
    expect(r.title, 'Nota "breve"');
    expect(r.text, 'Primera línea\n\nSegunda línea ¿sí? é');
  });

  test('una página armada con JavaScript da muy poco texto', () {
    const html = '<html><body><nav>Home Explore</nav><div id="root"></div>'
        '<script>render()</script></body></html>';
    final r = extractHtmlText(html);
    expect(r.wordCount, 0);
  });
}
