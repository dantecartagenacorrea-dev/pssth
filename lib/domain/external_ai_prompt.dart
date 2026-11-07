// Lo que se manda a DeepSeek (con la clave de la persona) para que haga el resumen.

/// Lo más largo que se resume de una vez: más de dos horas de clase.
const externalAiMaxChars = 200000;

const _intro =
    'Eres un tutor. Abajo está un texto para estudiar. Si es la transcripción automática de una clase, trae palabras '
    'mal oídas, trozos en otro idioma, saludos y muletillas.\n\n';

const _task =
    'Prepara un resumen para estudiar, en el idioma del texto, para quien no asistió:\n'
    '1. En pocas palabras: de qué trata y qué se aprende (2 a 4 frases).\n'
    '2. Conceptos clave: cada término con su significado.\n'
    '3. Ideas y pasos principales, en orden, con sus fechas, cantidades y ejemplos.\n\n';

const _rules =
    'Reglas:\n'
    '- Usa solo lo que dice el texto. No agregues datos de tu conocimiento ni busques en internet.\n'
    '- Corrige una palabra solo si el contexto deja claro cuál es, y márcalo así: «dice X; probablemente Y».\n'
    '- Lo que deduzcas y no esté dicho, márcalo con «(deducido)».\n'
    '- Copia tal cual los números, nombres, fórmulas y el orden entre pasos o tareas (qué va antes de qué).\n'
    '- Si un dato, sigla o fórmula quedó cortado o no se entiende, no lo adivines: escribe «(no se entiende)».\n'
    '- Deja fuera saludos, presentaciones, certificados y comentarios sobre el micrófono o la pantalla.\n\n';

const _json =
    'Responde solo con JSON de esta forma: {"brief": "punto 1", "concepts": [{"term": "...", "meaning": "..."}], '
    '"ideas": ["una idea o paso por elemento, en orden"]}.\n\n';

/// Las instrucciones del resumen, con la respuesta en JSON para mostrarla en la app.
String jsonSummaryPrompt(String text) => '$_intro$_task$_rules${_json}TEXTO:\n${text.trim()}';

/// Segundo paso: que la IA compare su propio resumen con el texto. En la
/// primera pasada (2026-11-06) copió mal qué tarea va después de cuál.
String jsonReviewPrompt(String text, String summaryJson) =>
    'Abajo están un TEXTO y un RESUMEN hecho a partir de él. Revisa el resumen contra el texto, frase por frase:\n'
    '- Para cada número, nombre, fecha, fórmula y cada relación de orden («la tarea X va después de la Y», «depende '
    'de»), busca en el texto la frase que lo dice y corrige el resumen para que diga exactamente lo mismo.\n'
    '- Quita saludos, presentaciones del docente, organizadores, horas académicas, registros y certificados.\n'
    '- Mantén las marcas «dice X; probablemente Y», «(deducido)» y «(no se entiende)».\n'
    '- No agregues nada que no esté en el texto.\n\n'
    '${_json}RESUMEN:\n$summaryJson\n\nTEXTO:\n${text.trim()}';

bool fitsExternalAi(String text) {
  final clean = text.trim();
  return clean.isNotEmpty && clean.length <= externalAiMaxChars;
}
