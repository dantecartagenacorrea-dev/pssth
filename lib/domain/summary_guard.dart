import 'study.dart';

/// Revisión sin IA de lo que escribe un modelo: lo que trae una cita, una sigla
/// o una cifra que no están en el texto original no llega al resumen.

/// Parte de las palabras de una cita que debe estar en el texto: la
/// transcripción trae errores y el modelo a veces corrige alguna.
const _minQuoteMatch = 0.8;

const _numberWords = {
  '0': 'cero',
  '1': 'uno|una|un',
  '2': 'dos',
  '3': 'tres',
  '4': 'cuatro',
  '5': 'cinco',
  '6': 'seis',
  '7': 'siete',
  '8': 'ocho',
  '9': 'nueve',
  '10': 'diez',
  '11': 'once',
  '12': 'doce',
  '13': 'trece',
  '14': 'catorce',
  '15': 'quince',
  '20': 'veinte',
  '30': 'treinta',
};

final _acronym = RegExp(r'(?<![\p{L}\d])\p{Lu}{2,6}(?![\p{L}\d])', unicode: true);
final _number = RegExp(r'(?<![\p{L}\d])\d+(?![\p{L}\d])', unicode: true);
final _longWord = RegExp(r'[\p{L}\d]{4,}', unicode: true);
final _anyWord = RegExp(r'[\p{L}\d]+', unicode: true);

/// Los apuntes de [raw] (`{"notes":[{"note","quote"}]}`) que el texto respalda,
/// sin repetidos y en su orden.
List<String> trustedNotes(Object? raw, String source) {
  final notes = raw is Map ? raw['notes'] : null;
  if (notes is! List) return const [];
  final known = _wordsOf(source);
  final seen = <String>{};
  return [
    for (final n in notes)
      if (n is Map)
        if ('${n['note'] ?? ''}'.trim() case final note when note.isNotEmpty)
          if (_quoted('${n['quote'] ?? ''}', known) && !_invents(note, known) && seen.add(note.toLowerCase())) note,
  ];
}

/// [summary] sin los conceptos, las ideas ni las frases del resumen breve que
/// traen siglas o cifras que no están en [source].
StudySummary withoutInvented(StudySummary summary, String source) {
  final known = _wordsOf(source);
  return StudySummary(
    concepts: [
      for (final c in summary.concepts)
        if (!_invents('${c.term} ${c.meaning}', known)) c,
    ],
    ideas: [
      for (final i in summary.ideas)
        if (!_invents(i, known)) i,
    ],
    brief: summary.brief.split(RegExp(r'(?<=[.!?])\s+')).where((s) => !_invents(s, known)).join(' '),
  );
}

Set<String> _wordsOf(String text) => {for (final m in _anyWord.allMatches(text)) m[0]!.toLowerCase()};

bool _quoted(String quote, Set<String> known) {
  final words = [for (final m in _longWord.allMatches(quote)) m[0]!.toLowerCase()];
  if (words.isEmpty) return false;
  return words.where(known.contains).length / words.length >= _minQuoteMatch;
}

bool _invents(String text, Set<String> known) {
  final acronyms = _acronym.allMatches(text).map((m) => m[0]!.toLowerCase());
  if (acronyms.any((a) => !known.contains(a))) return true;
  return _number.allMatches(text).map((m) => m[0]!).any((n) => !_numberKnown(n, known));
}

bool _numberKnown(String number, Set<String> known) =>
    known.contains(number) || (_numberWords[number]?.split('|').any(known.contains) ?? false);
