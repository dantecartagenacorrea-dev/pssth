import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lector_pdf/data/audio_cache.dart';
import 'package:lector_pdf/playback/engines/kokoro_engine.dart';
import 'package:lector_pdf/playback/tts_engine.dart';

/// Se porta como just_audio: al terminar un audio, «playing» sigue en true, y
/// con «playing» en true play() vuelve al instante sin esperar nada.
class _FakePlayer implements AudioPlayer {
  bool isPlaying = false;
  final loaded = <String>[];
  Completer<void>? _run;

  void finishAudio() => _run?.complete();

  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #playing:
        return isPlaying;
      case #setFilePath:
        loaded.add(call.positionalArguments.single as String);
        return Future<Duration?>.value(Duration.zero);
      case #play:
        if (isPlaying) return Future<void>.value();
        isPlaying = true;
        _run = Completer<void>();
        return _run!.future;
      case #stop:
        isPlaying = false;
        if (!(_run?.isCompleted ?? true)) _run!.complete();
        return Future<void>.value();
    }
    return super.noSuchMethod(call);
  }
}

/// Una voz natural cualquiera: su modelo no existe, pero el audio ya está en caché.
const PiperVoice _luna = (
  voice: VoiceOption(name: 'Luna (natural)', locale: 'es-ES', quality: 'natural'),
  onnx: 'no-existe/vocoder.int8.onnx',
  tokens: 'no-existe/tts.json',
  sid: 1,
  supertonic: true,
);

void main() {
  test('la frase siguiente espera a que suene entera, aunque nadie haya detenido la anterior', () async {
    final tmp = Directory.systemTemp.createTempSync('voz');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final cache = AudioCache(tmp);
    for (final text in ['uno', 'dos']) {
      final key = AudioCache.keyFor(text: text, engine: 'kokoro', voice: 'piper-${_luna.voice.name}-vocoder.int8.onnx', speed: 1);
      await cache.put(key, Uint8List(10));
    }
    final player = _FakePlayer();
    final engine = KokoroEngine(cache: cache, player: player, piper: [_luna]);
    await engine.setVoice(_luna.voice);

    Future<void> untilLoaded(int count) async {
      while (player.loaded.length < count) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final first = engine.speak('uno');
    await untilLoaded(1);
    player.finishAudio();
    await first;
    expect(player.isPlaying, isTrue, reason: 'just_audio lo deja así al terminar');

    var secondDone = false;
    final second = engine.speak('dos').then((_) => secondDone = true);
    await untilLoaded(2);
    expect(secondDone, isFalse, reason: 'si vuelve antes, la frase que sigue suena encima de esta');

    player.finishAudio();
    await second;
    expect(secondDone, isTrue);
  });
}
