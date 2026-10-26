import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/voice_groups.dart';

typedef V = ({String name, String locale, String? quality});

V v(String name, String locale, [String? quality]) => (name: name, locale: locale, quality: quality);

List<VoiceGroup<V>> agrupar(List<V> voces, {String lang = 'es'}) => groupVoices<V>(
      voces,
      preferredLanguage: lang,
      name: (x) => x.name,
      locale: (x) => x.locale,
      quality: (x) => x.quality,
    );

void main() {
  final voces = [
    v('Bubbles', 'en-US'),
    v('Zarvox', 'en-US'),
    v('Campanas', 'es-ES'),
    v('Mónica', 'es-ES', 'default'),
    v('Mónica', 'es-ES', 'enhanced'),
    v('Paulina', 'es-MX', 'premium'),
    v('Jorge', 'es-ES', 'default'),
    v('Dora (natural)', 'es-ES', 'natural'),
    v('Samantha', 'en-US', 'enhanced'),
    v('Amélie', 'fr-CA', 'default'),
    v('Luciana', 'pt-BR', 'default'),
  ];

  test('oculta las voces de efectos (Bubbles, Zarvox, Campanas…)', () {
    final todas = agrupar(voces).expand((g) => g.voices).map((x) => x.name);
    expect(todas, isNot(contains('Bubbles')));
    expect(todas, isNot(contains('Zarvox')));
    expect(todas, isNot(contains('Campanas')));
  });

  test('recomendadas primero: la natural y las mejores del idioma preferido', () {
    final g = agrupar(voces);
    expect(g.first.title, 'Recomendadas');
    expect(g.first.voices.map((x) => x.name).toList(), ['Dora (natural)', 'Paulina', 'Mónica']);
    expect(g.first.voices[2].quality, 'enhanced');
  });

  test('después el idioma preferido y luego los demás por nombre', () {
    final titulos = agrupar(voces).map((g) => g.title).toList();
    expect(titulos, ['Recomendadas', 'Español', 'Francés', 'Inglés', 'Portugués']);
    expect(agrupar(voces)[1].expanded, isTrue);
    expect(agrupar(voces)[2].expanded, isFalse);
  });

  test('ninguna voz aparece dos veces', () {
    final ids = agrupar(voces).expand((g) => g.voices).map((x) => '${x.name}|${x.locale}|${x.quality}').toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.length, voces.length - 3);
  });

  test('etiqueta legible con país y calidad', () {
    expect(voiceDisplayLabel(name: 'Paulina', locale: 'es-MX', quality: 'premium'), 'Paulina · México · Premium');
    expect(voiceDisplayLabel(name: 'Mónica', locale: 'es-ES', quality: 'enhanced'), 'Mónica · España · Mejorada');
    expect(voiceDisplayLabel(name: 'Jorge', locale: 'es-ES', quality: 'default'), 'Jorge · España · Básica');
    expect(voiceDisplayLabel(name: 'Dora (natural)', locale: 'es-ES', quality: 'natural'), 'Dora · España · Natural');
    expect(voiceDisplayLabel(name: 'es-us-x-sfb-local', locale: 'es-US', quality: null), 'es-us-x-sfb-local · EE. UU. · Alta');
  });
}
