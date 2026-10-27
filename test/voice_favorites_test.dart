import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/voice_groups.dart';

typedef V = ({String name, String locale, String? quality});

V v(String name, String locale, [String? quality]) => (name: name, locale: locale, quality: quality);

String idOf(V x) => '${x.name}|${x.locale}';

void main() {
  final voces = [
    v('Mónica', 'es-ES', 'enhanced'),
    v('Jorge', 'es-ES', 'default'),
    v('Dora (natural)', 'es-ES', 'natural'),
    v('Alex (natural)', 'es-ES', 'natural'),
    v('Samantha', 'en-US', 'enhanced'),
    v('Amélie', 'fr-CA', 'default'),
  ];

  List<VoiceGroup<V>> agrupar({Set<String> favorites = const {}, Map<String, int> uses = const {}}) => groupVoices<V>(
        voces,
        preferredLanguage: 'es',
        name: (x) => x.name,
        locale: (x) => x.locale,
        quality: (x) => x.quality,
        id: idOf,
        favorites: favorites,
        uses: uses,
      );

  test('las favoritas van primero, de cualquier idioma', () {
    final g = agrupar(favorites: {'Samantha|en-US', 'Jorge|es-ES'});
    expect(g.first.title, 'Favoritas');
    expect(g.first.voices.map((x) => x.name), containsAll(['Samantha', 'Jorge']));
  });

  test('después las más usadas, de más a menos', () {
    final g = agrupar(uses: {'Mónica|es-ES': 2, 'Amélie|fr-CA': 5});
    expect(g.first.title, 'Más usadas');
    expect(g.first.voices.map((x) => x.name).toList(), ['Amélie', 'Mónica']);
  });

  test('sin favoritas ni uso, Dora y Alex encabezan las recomendadas', () {
    final g = agrupar();
    expect(g.first.title, 'Recomendadas');
    expect(g.first.voices.take(2).map((x) => x.name), containsAll(['Dora (natural)', 'Alex (natural)']));
  });

  test('la natural más usada pasa delante de la otra', () {
    final g = agrupar(uses: {'Alex (natural)|es-ES': 3});
    expect(g.first.title, 'Más usadas');
    expect(g.first.voices.first.name, 'Alex (natural)');
  });

  test('ninguna voz aparece dos veces aunque sea favorita y usada', () {
    final g = agrupar(favorites: {'Jorge|es-ES'}, uses: {'Jorge|es-ES': 4, 'Mónica|es-ES': 1});
    final ids = g.expand((x) => x.voices).map(idOf).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.length, voces.length);
  });
}
