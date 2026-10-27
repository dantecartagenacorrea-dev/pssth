import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/youtube_transcript.dart';
import 'package:lector_pdf/domain/link_finder.dart';

void main() {
  test('reconoce los enlaces de video de YouTube', () {
    for (final u in [
      'https://www.youtube.com/watch?v=17mLa8kbcVo',
      'https://m.youtube.com/watch?v=17mLa8kbcVo&t=30',
      'https://youtu.be/17mLa8kbcVo?si=abc',
      'https://youtube.com/shorts/17mLa8kbcVo',
    ]) {
      expect(youtubeVideoId(Uri.parse(u)), '17mLa8kbcVo', reason: u);
    }
    expect(youtubeVideoId(Uri.parse('https://www.youtube.com/@canal')), isNull);
    expect(youtubeVideoId(Uri.parse('https://ejemplo.com/watch?v=17mLa8kbcVo')), isNull);
  });

  test('prefiere subtítulos en español escritos por una persona', () {
    final tracks = <Map<String, dynamic>>[
      {'languageCode': 'en', 'baseUrl': 'en'},
      {'languageCode': 'es', 'kind': 'asr', 'baseUrl': 'es-auto'},
      {'languageCode': 'es-419', 'baseUrl': 'es'},
    ];
    expect(pickCaptionTrack(tracks)?['baseUrl'], 'es');
    expect(pickCaptionTrack(tracks.sublist(0, 2))?['baseUrl'], 'es-auto');
    expect(pickCaptionTrack(const []), isNull);
  });

  test('la transcripción XML se vuelve texto corrido', () {
    const xml = '<?xml version="1.0" ?><transcript>'
        '<text start="0" dur="5">¿Sabes qué duele más</text>'
        '<text start="3" dur="4">[Música]</text>'
        '<text start="5" dur="5">que las palabras? El\nsilencio &amp;#39;total&amp;#39;</text>'
        '</transcript>';
    expect(parseTranscriptXml(xml), "¿Sabes qué duele más que las palabras? El silencio 'total'");
  });

  test('encuentra la dirección leída de una foto de pantalla', () {
    const ocr = 'ASÍ IMPACTA TU SILENCIO\nyoutube.com/watch?v=17mLa8kbcVo\nInstalar';
    expect(findLinkInText(ocr).toString(), 'https://youtube.com/watch?v=17mLa8kbcVo');
    expect(findLinkInText('Ver https://ejemplo.bo/nota.')?.path, '/nota');
    expect(findLinkInText('Visita www.ejemplo.com, gracias')?.host, 'www.ejemplo.com');
  });

  test('repara los errores típicos del OCR en la dirección', () {
    const id = 'https://youtube.com/watch?v=17mLa8kbcVo';
    expect(findLinkInText('youtube. com/watch?v=17mLa8kbcVo').toString(), id);
    expect(findLinkInText('youtube.corn/watch?v=17mLa8kbcVo').toString(), id);
    expect(findLinkInText('youtube.com/watch?v= 17mLa8kbcVo').toString(), id);
    expect(findLinkInText('youtube.com/ watch?v=17mLa8kbcVo').toString(), id);
    expect(findLinkInText('Hola. Ver más tarde'), isNull);
  });

  test('no confunde abreviaturas con enlaces', () {
    expect(findLinkInText('Empresa S.A. y Cía. Ltda. al fin.de mes'), isNull);
    expect(findLinkInText('Texto sin direcciones'), isNull);
  });

  test('entre varios enlaces elige el video', () {
    const t = 'google.com/search?q=x y luego youtu.be/17mLa8kbcVo';
    expect(findLinkInText(t)?.host, 'youtu.be');
  });
}
