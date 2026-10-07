import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/playback/engines/fallback_tts_engine.dart';
import 'package:lector_pdf/playback/tts_engine.dart';

class FakeEngine extends TtsEngine {
  FakeEngine(this.id, {this.failInit = false, this.failSpeak = false});
  @override
  final String id;
  final bool failInit;
  bool failSpeak;
  final spoken = <String>[];
  double rate = -1;
  double volume = -1;

  @override
  Future<void> init() async {
    if (failInit) throw StateError('init');
  }

  @override
  Future<List<VoiceOption>> voices() async =>
      [VoiceOption(name: id, locale: 'es-ES')];
  @override
  Future<void> setVoice(VoiceOption voice) async {}
  @override
  Future<void> setLanguage(String locale) async {}
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
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
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
}
