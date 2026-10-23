// Limpieza automática de transcripciones antes de mostrar/leer.
// Diccionario local + detección de contexto; sin servidores.
// Aprendizaje: TranscriptCleaner.instance.learn('Urguiado', 'Ur').

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TranscriptCleaner {
  TranscriptCleaner._();
  static final TranscriptCleaner instance = TranscriptCleaner._();

  static const Map<String, List<String>> _contextTriggers = {
    'biblico': [
      'abraham', 'israel', 'moisés', 'moises', 'biblia', 'bíblic', 'biblic',
      'jacob', 'isaac', 'egipto', 'faraón', 'faraon', 'profeta', 'jerusalén',
      'jerusalen', 'templo', 'canaán', 'canaan', 'hebreo', 'judá', 'juda',
    ],
  };

  static const Map<String, Map<String, String>> _contextDicts = {
    'biblico': {
      'canadá': 'Canaán', 'canada': 'Canaán',
      'urguiado': 'Ur', 'urguiada': 'Ur',
      'abrahán': 'Abraham', 'isac': 'Isaac',
      'moises': 'Moisés', 'faraon': 'Faraón', 'jerusalen': 'Jerusalén',
      'belen': 'Belén', 'sinai': 'Sinaí', 'salomon': 'Salomón',
      'elias': 'Elías', 'esau': 'Esaú', 'jose': 'José', 'levi': 'Leví',
      'ruben': 'Rubén', 'simeon': 'Simeón', 'benjamin': 'Benjamín',
      'efrain': 'Efraín', 'manases': 'Manasés',
    },
  };

  static const Map<String, String> _globalDict = {
    'fertil': 'fértil',
    'exponeran': 'expulsarán',
    'exponerán': 'expulsarán',
  };

  final Map<String, String> _learned = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tc_learned');
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _learned.addAll(m.map((k, v) => MapEntry(k, v.toString())));
    }
    _loaded = true;
  }

  Future<void> learn(String wrong, String right) async {
    _learned[wrong.toLowerCase()] = right;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tc_learned', jsonEncode(_learned));
  }

  Future<void> forget(String wrong) async {
    _learned.remove(wrong.toLowerCase());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tc_learned', jsonEncode(_learned));
  }

  Map<String, String> get learned => Map.unmodifiable(_learned);

  Set<String> detectContexts(String text) {
    final lower = text.toLowerCase();
    final found = <String>{};
    _contextTriggers.forEach((ctx, triggers) {
      if (triggers.where(lower.contains).length >= 2) found.add(ctx);
    });
    return found;
  }

  Map<String, String> _dictFor(String text) {
    final dict = <String, String>{}..addAll(_globalDict);
    for (final ctx in detectContexts(text)) {
      dict.addAll(_contextDicts[ctx] ?? const {});
    }
    dict.addAll(_learned);
    return dict;
  }

  RegExp _patternFor(Map<String, String> dict) => RegExp(
        r'(?<![\p{L}\p{N}_])(' + dict.keys.map(RegExp.escape).join('|') + r')(?![\p{L}\p{N}_])',
        caseSensitive: false,
        unicode: true,
      );

  /// Limpia [text]. [context] opcional: texto mayor para detectar el tema
  /// (p. ej. el documento completo cuando se limpia por bloques).
  String clean(String text, {String? context}) {
    if (!_loaded) load();
    final dict = _dictFor(context ?? text);
    if (dict.isEmpty) return text;
    return text.replaceAllMapped(_patternFor(dict), (m) {
      final orig = m.group(0)!;
      final rep = dict[orig.toLowerCase()] ?? orig;
      if (orig[0] == orig[0].toUpperCase() && rep[0] == rep[0].toLowerCase()) {
        return rep[0].toUpperCase() + rep.substring(1);
      }
      return rep;
    });
  }

  List<(String, String)> diff(String text, {String? context}) {
    final dict = _dictFor(context ?? text);
    if (dict.isEmpty) return const [];
    return [
      for (final m in _patternFor(dict).allMatches(text))
        (m.group(0)!, dict[m.group(0)!.toLowerCase()]!),
    ];
  }
}
