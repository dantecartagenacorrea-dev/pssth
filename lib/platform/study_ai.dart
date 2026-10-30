import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../core/app_exception.dart';
import '../domain/study.dart';
import '../services/llm_cleaner.dart';

/// Qué IA hace los resúmenes y las preguntas: la del iPhone (Apple) o la de
/// la computadora de la casa por Wi-Fi (Ollama). Sin ninguna, salen del
/// propio texto al instante (una IA chica dentro de la tablet se probó y no
/// respetaba el formato: se quitó).
enum StudyEngine {
  apple('Hecho por la IA de tu iPhone, sin salir del equipo.'),
  computer('Hecho por la IA de tu computadora, en tu red Wi-Fi.');

  const StudyEngine(this.label);
  final String label;
}

/// Puente con la IA para estudiar. Elige sola la mejor disponible. Ninguna
/// manda el texto a servidores externos.
class StudyAi {
  static const _apple = MethodChannel('lector/ai');
  static const _tutor =
      'Eres un tutor que ayuda a estudiantes a comprender lo que leen. Respondes en el mismo '
      'idioma del texto, con frases claras y precisas. Usas solo lo que dice el texto: nunca inventas datos.';

  StudyEngine? _engine;
  bool _picked = false;

  /// La mejor IA disponible ahora, o null si no hay ninguna.
  Future<StudyEngine?> engine() async {
    if (_picked) return _engine;
    _picked = true;
    if (await _appleStatus() == 'available') return _engine = StudyEngine.apple;
    final pc = LlmCleaner.instance;
    await pc.load();
    if (pc.ready && await pc.ping() == null) return _engine = StudyEngine.computer;
    return null;
  }

  Future<String> _appleStatus() async {
    try {
      return await _apple.invokeMethod<String>('status') ?? 'unavailable';
    } on MissingPluginException {
      return 'unsupported';
    } on PlatformException {
      return 'unavailable';
    }
  }

  /// null si hay alguna IA; si no, qué hacer para tener una.
  Future<String?> unavailableReason() async {
    if (await engine() != null) return null;
    if (Platform.isAndroid) return 'Conecta la IA de tu computadora (⋮ → Corrección avanzada).';
    return switch (await _appleStatus()) {
      'deviceNotEligible' => 'Este iPhone no tiene Apple Intelligence (hace falta un iPhone 15 Pro o posterior).',
      'appleIntelligenceNotEnabled' => 'Activa Apple Intelligence en Ajustes > Apple Intelligence y Siri.',
      'modelNotReady' => 'Apple Intelligence todavía se está descargando. Prueba en unos minutos.',
      'unsupported' => 'Hace falta iOS 26 con Apple Intelligence.',
      _ => 'La IA del equipo no está disponible ahora.',
    };
  }

  Future<StudySummary> summarize(String text) async {
    switch (await engine()) {
      case StudyEngine.apple:
        return StudySummary.fromMap(await _callApple('summarize', {'text': text}));
      case StudyEngine.computer:
        return StudySummary.fromMap(
          await LlmCleaner.instance.generateJson(
            _tutor,
            'Resume este texto para estudiarlo: conceptos clave con su significado, ideas principales y un '
            'resumen breve.\n\nTEXTO:\n$text',
            _summarySchema,
          ),
        );
      case null:
        throw AppException((await unavailableReason())!);
    }
  }

  /// Hasta [count] preguntas válidas sobre [text] (pueden venir menos). Sin
  /// IA, las preguntas salen del propio texto (quiz_local.dart).
  Future<List<QuizQuestion>> quiz(String text, {required int count, required QuizLevel level, math.Random? rnd}) async {
    final r = rnd ?? math.Random();
    final kind = switch (level) {
      QuizLevel.experto => 'de nivel experto (inferir, comparar, aplicar)',
      QuizLevel.medio => 'de nivel medio (relaciones, causas y consecuencias)',
      QuizLevel.basico => 'de nivel básico (datos y definiciones que el texto dice)',
    };
    List<Object?> raw;
    switch (await engine()) {
      case StudyEngine.apple:
        final res = await _callApple('quiz', {'text': text, 'count': count, 'level': level.name});
        raw = res is List ? res : const [];
      case StudyEngine.computer:
        final res = await LlmCleaner.instance.generateJson(
          _tutor,
          'Escribe $count preguntas de opción múltiple $kind sobre el texto. Cuatro opciones, una sola '
          'correcta (answer = su posición, de 0 a 3), y una explicación breve.\n\nTEXTO:\n$text',
          _quizSchema,
        );
        raw = res is Map && res['questions'] is List ? res['questions'] as List : const [];
      case null:
        throw AppException((await unavailableReason())!);
    }
    return [for (final q in raw) ?QuizQuestion.fromMap(q, r)];
  }

  Future<Object?> _callApple(String method, Map<String, Object> args) async {
    try {
      return await _apple.invokeMethod<Object>(method, args);
    } on PlatformException catch (e) {
      throw AppException(e.message ?? 'La IA del equipo no pudo responder.');
    }
  }

  static const _summarySchema = {
    'type': 'object',
    'properties': {
      'concepts': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'term': {'type': 'string'},
            'meaning': {'type': 'string'},
          },
          'required': ['term', 'meaning'],
        },
      },
      'ideas': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'brief': {'type': 'string'},
    },
    'required': ['concepts', 'ideas', 'brief'],
  };

  static const _quizSchema = {
    'type': 'object',
    'properties': {
      'questions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'question': {'type': 'string'},
            'options': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'answer': {'type': 'integer'},
            'explanation': {'type': 'string'},
          },
          'required': ['question', 'options', 'answer', 'explanation'],
        },
      },
    },
    'required': ['questions'],
  };
}
