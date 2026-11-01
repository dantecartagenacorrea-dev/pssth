import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/playback/tts_engine.dart';

import 'playback_loop_test.dart' show SlowEngine, handlerWith, settle, until;

const _dora = VoiceOption(name: 'Dora (natural)', locale: 'es-ES', quality: 'natural');
const _alex = VoiceOption(name: 'Alex (natural)', locale: 'es-ES', quality: 'natural');

/// Motor de prueba que anota con qué voz dice cada cosa; detener corta la
/// frase que suena, y preparar una voz espera a que la prueba lo permita.
class SwitchEngine extends SlowEngine {
  VoiceOption voice = _dora;
  final said = <String>[];
  final prepared = <String>[];
  Completer<void>? preparing;

  List<VoiceOption> offered = const [_dora, _alex];
  @override
  Future<List<VoiceOption>> voices() async => offered;
  @override
  Future<void> setVoice(VoiceOption voice) async => this.voice = voice;
  @override
  Future<void> prepare(VoiceOption voice, String text) {
    prepared.add('${voice.name}: $text');
    preparing = Completer<void>();
    return preparing!.future;
  }

  @override
  Future<void> speak(String text) {
    said.add('${voice.name}: $text');
    return super.speak(text);
  }

  @override
  Future<void> stop() async {
    while (pending.isNotEmpty) {
      finishCurrent();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('al cambiar de voz sigue sonando la anterior y la nueva sigue desde la misma palabra', () async {
    final engine = SwitchEngine();
    final (h, tmp) = await handlerWith(engine, ['Uno dos tres cuatro.', 'Cinco.']);
    unawaited(h.play());
    await until(() => engine.pending.length == 1);
    engine.onProgress?.call('Uno dos tres cuatro.', 8, 12); // suena "tres"
    final change = h.setVoice(_alex);
    await until(() => engine.prepared.isNotEmpty);
    // Mientras se prepara la voz nueva, la anterior no se calla.
    expect(engine.prepared, ['Alex (natural): tres cuatro.']);
    expect(engine.pending, hasLength(1));
    expect(engine.said, ['Dora (natural): Uno dos tres cuatro.']);
    engine.preparing!.complete();
    await change;
    await until(() => engine.said.length == 2);
    expect(engine.said.last, 'Alex (natural): tres cuatro.');
    expect(h.chunkIndex, 0);
    // La palabra marcada se ubica en el fragmento entero.
    engine.onProgress?.call('tres cuatro.', 5, 11);
    expect(h.wordRange.value, (13, 19));
    engine.finishCurrent();
    await until(() => engine.said.length == 3);
    expect(engine.said.last, 'Alex (natural): Cinco.');
    await h.stop();
    tmp.deleteSync(recursive: true);
  });

  test('si eligen otra voz mientras se prepara una, gana la última', () async {
    final engine = SwitchEngine();
    final (h, tmp) = await handlerWith(engine, ['Uno dos tres.', 'Cuatro.']);
    unawaited(h.play());
    await until(() => engine.pending.length == 1);
    final first = h.setVoice(_alex);
    await settle();
    final firstPrep = engine.preparing!;
    final second = h.setVoice(_dora);
    await settle();
    engine.preparing!.complete();
    firstPrep.complete();
    await Future.wait([first, second]);
    await settle();
    expect(engine.said.last, 'Dora (natural): Uno dos tres.');
    expect(engine.said.where((s) => s.startsWith('Alex')), isEmpty);
    expect(h.chunkIndex, 0);
    await h.stop();
    tmp.deleteSync(recursive: true);
  });

  test('si se oculta la voz elegida, pasa a otra sin dejar de leer y avisa', () async {
    final engine = SwitchEngine();
    final (h, tmp) = await handlerWith(engine, ['Uno dos tres.', 'Cuatro.']);
    await h.applyDocumentLanguage('es');
    final change = h.setVoice(_dora);
    await settle();
    engine.preparing?.complete();
    await change;
    unawaited(h.play());
    await until(() => engine.pending.length == 1);
    engine.offered = const [_alex];
    engine.onVoicesChanged?.call('Dora no alcanza');
    await settle();
    expect(engine.voice, _alex);
    expect(h.snapshot.value.message, 'Dora no alcanza');
    expect(engine.pending, hasLength(1)); // la frase sigue sonando
    await h.stop();
    tmp.deleteSync(recursive: true);
  });
}
