import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../core/app_exception.dart';
import '../domain/study.dart';

/// Puente con la IA del propio equipo para estudiar (por ahora la de Apple,
/// iOS 26 con Apple Intelligence). El texto no sale del teléfono.
class StudyAi {
  static const _channel = MethodChannel('lector/ai');

  /// null si se puede usar; si no, por qué no, en palabras del usuario.
  Future<String?> unavailableReason() async {
    String status;
    try {
      status = await _channel.invokeMethod<String>('status') ?? 'unavailable';
    } on MissingPluginException {
      status = 'unsupported';
    } on PlatformException {
      status = 'unavailable';
    }
    return switch (status) {
      'available' => null,
      'deviceNotEligible' => 'Este iPhone no tiene Apple Intelligence (hace falta un iPhone 15 Pro o posterior).',
      'appleIntelligenceNotEnabled' => 'Activa Apple Intelligence en Ajustes > Apple Intelligence y Siri.',
      'modelNotReady' => 'Apple Intelligence todavía se está descargando. Prueba en unos minutos.',
      'unsupported' when Platform.isIOS => 'Hace falta iOS 26 con Apple Intelligence.',
      'unsupported' => 'Por ahora esta función está solo en iPhone.',
      _ => 'La IA del equipo no está disponible ahora.',
    };
  }

  Future<StudySummary> summarize(String text) async {
    final raw = await _call('summarize', {'text': text});
    return StudySummary.fromMap(raw);
  }

  /// Hasta [count] preguntas válidas sobre [text] (pueden venir menos).
  Future<List<QuizQuestion>> quiz(String text, {required int count, required QuizLevel level, math.Random? rnd}) async {
    final raw = await _call('quiz', {'text': text, 'count': count, 'level': level.name});
    final r = rnd ?? math.Random();
    return [
      for (final q in raw is List ? raw : const [])
        ?QuizQuestion.fromMap(q, r),
    ];
  }

  Future<Object?> _call(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<Object>(method, args);
    } on MissingPluginException {
      throw AppException('Por ahora esta función está solo en iPhone.');
    } on PlatformException catch (e) {
      throw AppException(e.message ?? 'La IA del equipo no pudo responder.');
    }
  }
}
