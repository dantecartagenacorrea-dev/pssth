import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/playback/engines/fallback_tts_engine.dart';
import 'package:lector_pdf/playback/tts_engine.dart';

class FakeEngine extends TtsEngine {
  FakeEngine(
    this.id, {
    this.failInit = false,
    this.failSpeak = false,
    this.locales = const ['es-ES'],
    this.renders = true,
  });
  @override
  final String id;
  final bool failInit;
  bool failSpeak;
  final List<String> locales;
  final bool renders;

  /// Textos cuyo audio todavía no está listo (voz natural sintetizando).
  final notReady = <String>{};
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
  Future<List<VoiceOption>> voices() async => [for (final l in locales) VoiceOption(name: '$id-$l', locale: l)];
  @override
  Future<void> setVoice(VoiceOption voice) async => calls.add('voice:${voice.name}');
  @override
  Future<void> setLanguage(String locale) async => calls.add('lang:$locale');
  @override
  void prefetch(List<String> upcoming) => prefetched.add(upcoming);
  @override
  Future<bool> canSpeakNow(String text) async => !notReady.contains(text);
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
    expect(p.prefetched, [
      ['b'],
    ]);
  });

  test('mientras la voz natural prepara un fragmento, lo lee la del sistema (nunca en silencio)', () async {
    final p = FakeEngine('neural')..notReady.add('uno');
    final f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f);
    await e.init();
    await e.speak('uno');
    e.prefetch(['dos']);
    await e.speak('dos');
    expect(f.spoken, ['uno']);
    expect(p.spoken, ['dos']);
    expect(p.prefetched, [
      ['dos'],
    ]); // la natural sigue preparando lo que viene
    expect(e.usingFallback, isFalse);
  });

  test('si la voz natural oculta voces, la lista se actualiza y se avisa', () async {
    final p = FakeEngine('neural', locales: ['es-ES']), f = FakeEngine('apple');
    final e = FallbackTtsEngine(primary: p, fallback: f);
    final avisos = <String>[];
    e.onVoicesChanged = avisos.add;
    await e.init();
    expect((await e.voices()).map((v) => v.name), contains('neural-es-ES'));
    p.locales.clear();
    p.onVoicesChanged?.call('no alcanzan');
    await Future<void>.delayed(Duration.zero);
    expect((await e.voices()).map((v) => v.name), ['apple-es-ES']);
    expect(avisos, ['no alcanzan']);
  });

  group('la misma voz en toda la lectura', () {
    test('espera el audio de la voz natural en vez de cubrir con la del sistema', () async {
      final p = FakeEngine('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      p.notReady.add('pregunta');
      await e.speakSameVoice('pregunta');
      expect(p.spoken, ['pregunta']);
      expect(f.spoken, isEmpty);
    });

    test('si la voz natural falla, sigue la del sistema: no se queda callada', () async {
      final p = FakeEngine('neural', failSpeak: true), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      await e.speakSameVoice('pregunta');
      expect(f.spoken, ['pregunta']);
    });

    test('si este equipo no alcanza a leer con ella, no la espera', () async {
      final p = _NotWorthWaiting('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      p.notReady.add('pregunta');
      await e.speakSameVoice('pregunta');
      expect(f.spoken, ['pregunta']);
      expect(p.spoken, isEmpty);
    });

    test('la lectura normal sigue sin esperar: la cubre la del sistema', () async {
      final p = FakeEngine('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      p.notReady.add('frase');
      await e.speak('frase');
      expect(f.spoken, ['frase']);
    });
  });

  group('una sola voz a la vez', () {
    test('detener mientras se mira si el audio está listo: esa frase ya no suena', () async {
      final p = _GatedEngine('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      p.notReady.add('vieja');
      final old = e.speak('vieja');
      await e.stop();
      p.gate.complete();
      await old;
      expect(f.spoken, isEmpty, reason: 'sonaría encima de lo que se lea después');
      expect(p.spoken, isEmpty);
    });

    test('una frase pedida después deja sin efecto a la que todavía esperaba', () async {
      final p = _GatedEngine('neural'), f = FakeEngine('apple');
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();
      p.notReady.add('vieja');
      final old = e.speak('vieja');
      p.gateOff = true;
      await e.speak('nueva');
      p.gate.complete();
      await old;
      expect(f.spoken, isEmpty);
      expect(p.spoken, ['nueva']);
    });

    test('la voz del sistema calla a la natural antes de hablar, y al revés', () async {
      final log = <String>[];
      final p = _LogEngine('neural', log), f = _LogEngine('apple', log);
      final e = FallbackTtsEngine(primary: p, fallback: f);
      await e.init();

      p.notReady.add('sin audio');
      await e.speak('sin audio');
      expect(log, ['neural:stop', 'apple:speak']);

      log.clear();
      await e.speak('con audio');
      expect(log, ['apple:stop', 'neural:speak']);
    });
  });
}

class _NotWorthWaiting extends FakeEngine {
  _NotWorthWaiting(super.id);
  @override
  bool get worthWaiting => false;
}

/// Se queda mirando si el audio está listo hasta que la prueba lo suelte.
class _GatedEngine extends FakeEngine {
  _GatedEngine(super.id);
  final gate = Completer<void>();
  bool gateOff = false;
  @override
  Future<bool> canSpeakNow(String text) async {
    if (!gateOff) await gate.future;
    return super.canSpeakNow(text);
  }
}

class _LogEngine extends FakeEngine {
  _LogEngine(super.id, this.log);
  final List<String> log;
  @override
  Future<void> speak(String text) async {
    log.add('$id:speak');
    await super.speak(text);
  }

  @override
  Future<void> stop() async {
    log.add('$id:stop');
    await super.stop();
  }
}
