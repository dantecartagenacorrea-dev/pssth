import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/voice_ranking.dart';

void main() {
  test('prefiere voces locales neuronales sobre red y genéricas', () {
    final voces = ['es-ES-language', 'es-es-x-eed-network', 'es-es-x-eed-local', 'es-us-x-sfb-local'];
    final r = rankVoices<String>(voces, name: (v) => v, locale: (v) => v.startsWith('es-us') ? 'es-US' : 'es-ES');
    expect(r.first, 'es-us-x-sfb-local');
    expect(r.last, 'es-es-x-eed-network');
  });
  test('en iOS premium > enhanced > default', () {
    final voces = [('Mónica', 'default'), ('Mónica', 'premium'), ('Mónica', 'enhanced')];
    final r = rankVoices<(String, String)>(voces, name: (v) => v.$1, locale: (_) => 'es-ES', quality: (v) => v.$2);
    expect(r.map((v) => v.$2).toList(), ['premium', 'enhanced', 'default']);
  });
}
