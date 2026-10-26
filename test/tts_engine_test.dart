import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/playback/engines/fallback_tts_engine.dart';
import 'package:lector_pdf/playback/tts_engine.dart';

class FakeEngine extends TtsEngine {
  FakeEngine(this.id, {this.failInit = false, this.failSpeak = false, this.locales = const ['es-ES'], this.renders = true});
  @override
  final String id;
  final bool failInit;
  bool failSpeak;
  final List<String> locales;
  final bool renders;
  final rendered = <String>[];
  final spoken = <String>[];
  final prefetched = <List<String>>[];
  final calls = <String>[];
  double rate = -1;
  double volume = -1;
  bool initOk = false;

  @override
  Future<void> init() async {
    if (failInit && !initOk) throw StateError('init');
    initOk = true;
  }

  @override
  Future<List<VoiceOption>> voices() async =>
      [for (final l in locales) VoiceOption(name: '$id-$l', locale: l)];
  @override
  Future<void> setVoice(VoiceOption voice) async => calls.add('voice:${voice.name}');
  @override
  Future<void> setLanguage(String locale) async => calls.add('lang:$locale');
  @override
  void prefetch(List<String> upcoming) => prefetched.add(upcoming);
  @override
  Future<void> setRate(double r) async => rate = r;
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> speak(String text) async {
    if (failSpeak) throw StateError('speak');
    spoken.add(text);
  }

  @override
  Future<String?> renderToFile(String text, String path) async {
    if (!renders) return null;
    rendered.add(text);
    return '$path.$id';
  }

  int stops = 0;
  int pauses = 0;

  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
}

void main() {
  group('renderToFile (compartir audio)', () {
    test('usa el motor activo y, si no sabe, el del sistema', () async {
      final p = FakeEngine('kokoro', renders: false);
      final f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      await e.setVoice(const VoiceOption(name: 'kokoro-es-ES', locale: 'es-ES'));
      expect(await e.renderToFile('hola', '/t/x.wav'), '/t/x.wav.apple');
      expect(f.rendered, ['hola']);
    });

    test('con voz natural activa renderiza con ella', () async {
      final p = FakeEngine('kokoro');
      final f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      await e.setVoice(const VoiceOption(name: 'kokoro-es-ES', locale: 'es-ES'));
      expect(await e.renderToFile('hola', '/t/x.wav'), '/t/x.wav.kokoro');
      expect(f.rendered, isEmpty);
    });
  });

  test('usa el motor primario si funciona', () async {
    final p = FakeEngine('neural'), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f);
    await e.init();
    await e.speak('hola');
    expect(p.spoken, ['hola']);
    expect(f.spoken, isEmpty);
    expect(e.usingFallback, isFalse);
  });

  test('si falla init del primario, usa Apple', () async {
    final p = FakeEngine('neural', failInit: true), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f);
    await e.init();
    expect(e.usingFallback, isTrue);
    await e.speak('hola');
    expect(f.spoken, ['hola']);
    expect(e.errors, hasLength(1));
  });

  test('si falla speak, reintenta el mismo texto con Apple y conserva velocidad/volumen', () async {
    final p = FakeEngine('neural'), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f);
    var avisado = false;
    e.onFallback = (_) => avisado = true;
    await e.init();
    await e.setRate(0.75);
    await e.setVolume(0.9);
    p.failSpeak = true;
    await e.speak('texto');
    expect(f.spoken, ['texto']);
    expect(f.rate, 0.75);
    expect(f.volume, 0.9);
    expect(avisado, isTrue);
    expect(e.id, 'apple');
  });

  test('si el fallback también falla, el error se propaga', () async {
    final p = FakeEngine('neural', failSpeak: true);
    final f = FakeEngine('apple', failSpeak: true);
    final e = FallbackTtsEngine(primary: p, fallback: f);
    await e.init();
    expect(() => e.speak('x'), throwsA(isA<StateError>()));
  });

  test('lista voces de ambos motores y la voz elegida decide el motor', () async {
    final p = FakeEngine('neural'), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
    await e.init();
    final voces = await e.voices();
    expect(voces.map((v) => v.name), ['neural-es-ES', 'apple-es-ES']);
    await e.speak('a'); // sin voz elegida: motor del sistema
    expect(f.spoken, ['a']);
    await e.setVoice(voces.first); // voz natural
    await e.speak('b');
    expect(p.spoken, ['b']);
    await e.setVoice(voces.last); // vuelve al sistema
    await e.speak('c');
    expect(f.spoken, ['a', 'c']);
  });

  test('modelo no instalado: solo voces del sistema y sin errores para el usuario', () async {
    final p = FakeEngine('neural', failInit: true), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
    await e.init();
    expect((await e.voices()).map((v) => v.name), ['apple-es-ES']);
    expect(e.primaryAvailable, isFalse);
  });

  test('retryPrimary: tras instalar el modelo, aparecen sus voces', () async {
    final p = FakeEngine('neural', failInit: true), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
    await e.init();
    expect(await e.retryPrimary(), isFalse);
    p.initOk = true; // "modelo instalado"
    expect(await e.retryPrimary(), isTrue);
    expect((await e.voices()).map((v) => v.name), ['neural-es-ES', 'apple-es-ES']);
  });

  test('un fragmento en otro idioma sale por el sistema y luego vuelve la voz natural', () async {
    final p = FakeEngine('neural'), f = FakeEngine('apple', locales: ['es-ES', 'en-US']);
    final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
    await e.init();
    await e.setVoice((await e.voices()).first); // Kokoro
    await e.setLanguage('es');
    await e.speak('hola');
    await e.setLanguage('en');
    await e.speak('hello');
    await e.setLanguage('es');
    await e.speak('adiós');
    expect(p.spoken, ['hola', 'adiós']);
    expect(f.spoken, ['hello']);
  });

  group('nunca suenan dos motores a la vez', () {
    test('stop detiene ambos motores aunque el activo sea el del sistema', () async {
      final p = FakeEngine('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
      await e.init();
      await e.stop();
      expect(f.stops, 1);
      expect(p.stops, 1);
    });

    test('pause pausa el activo y detiene el otro', () async {
      final p = FakeEngine('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      await e.pause();
      expect(p.pauses, 1);
      expect(f.stops, 1);
    });

    test('al elegir una voz del sistema se calla la voz natural', () async {
      final p = FakeEngine('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
      await e.init();
      final voces = await e.voices();
      await e.setVoice(voces.first); // natural
      await e.setVoice(voces.last); // sistema
      expect(p.stops, 1);
      expect(f.stops, 1); // y antes, al pasar a la natural, se calló el sistema
    });

    test('un fragmento en otro idioma calla la voz natural antes de pasar al sistema', () async {
      final p = FakeEngine('neural'), f = FakeEngine('apple', locales: ['es-ES', 'en-US']);
      final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
      await e.init();
      await e.setVoice((await e.voices()).first);
      final antes = p.stops;
      await e.setLanguage('en');
      expect(p.stops, antes + 1);
    });
  });

  test('prefetch solo llega al motor activo', () async {
    final p = FakeEngine('neural'), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f, startWithPrimary: false);
    await e.init();
    e.prefetch(['a']);
    await e.setVoice((await e.voices()).first);
    e.prefetch(['b']);
    expect(p.prefetched, [['b']]);
  });
}
