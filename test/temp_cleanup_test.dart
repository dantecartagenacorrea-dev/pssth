import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/temp_cleanup.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('temporales'));
  tearDown(() => dir.deleteSync(recursive: true));

  File file(String name, {int bytes = 10, Duration age = Duration.zero}) {
    final f = File('${dir.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 1));
    f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  test('borra los restos de la IA quitada aunque sean nuevos', () async {
    file('qwen3-0.6b.litertlm_1_2.xnnpack_cache', bytes: 1000);
    file('qwen3-0.6b.litertlm_1_2_mldrift_weight_cache.bin', bytes: 500);
    final freed = await cleanTemporary(dir);
    expect(freed, 1500);
    expect(dir.listSync(), isEmpty);
  });

  test('borra temporales propios de más de un día y deja los recientes', () async {
    const old = Duration(days: 2);
    file('scaled_1000.jpg', age: old);
    file('grabacion_1.wav', age: old);
    file('Libro (editado).pdf', age: old);
    file('grabacion_2.wav'); // de hoy: la app que la recibe quizá la está leyendo
    await cleanTemporary(dir);
    final left = dir.listSync().map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)).toList();
    expect(left, ['grabacion_2.wav']);
  });

  test('no toca la caché de audio ni lo de otras bibliotecas', () async {
    const old = Duration(days: 30);
    file('tts_audio/abc.wav', age: old);
    file('mlkit_docscan_ui_client/x', age: old);
    file('oat_primary/y', age: old);
    expect(await cleanTemporary(dir), 0);
    expect(dir.listSync().length, 3);
  });

  test('carpeta que no existe', () async {
    expect(await cleanTemporary(Directory('${dir.path}/no')), 0);
  });
}
