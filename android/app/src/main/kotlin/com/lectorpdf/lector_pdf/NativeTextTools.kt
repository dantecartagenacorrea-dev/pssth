package com.lectorpdf.lector_pdf

import android.content.Context
import android.net.Uri
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Equivalente Android del canal "lector/native_text" de iOS (Vision/NaturalLanguage):
/// OCR con ML Kit y detección de idioma, todo local y sin red.
object NativeTextTools {
    fun register(context: Context, messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, "lector/native_text")
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val langId = LanguageIdentification.getClient()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(true)
                "detectLanguage" -> {
                    val text = call.argument<String>("text") ?: ""
                    if (text.isBlank()) { result.success(null); return@setMethodCallHandler }
                    langId.identifyLanguage(text)
                        .addOnSuccessListener { code -> result.success(if (code == "und") null else code) }
                        .addOnFailureListener { result.success(null) }
                }
                "recognize" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "Falta path", null); return@setMethodCallHandler
                    }
                    try {
                        val image = InputImage.fromFilePath(context, Uri.fromFile(File(path)))
                        recognizer.process(image)
                            .addOnSuccessListener { visionText ->
                                // Bloques en orden de lectura; una línea por línea detectada.
                                val sb = StringBuilder()
                                for (block in visionText.textBlocks) {
                                    for (line in block.lines) sb.append(line.text).append('\n')
                                    sb.append('\n')
                                }
                                result.success(sb.toString().trim())
                            }
                            .addOnFailureListener { e -> result.error("ocr_failed", e.message, null) }
                    } catch (e: Exception) {
                        result.error("ocr_failed", e.message, null)
                    }
                }
                "recognizeLines" -> {
                    // Cada línea con su lugar en la foto (fracciones 0–1), para
                    // poner el texto buscable encima de la imagen en un PDF.
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "Falta path", null); return@setMethodCallHandler
                    }
                    try {
                        val image = InputImage.fromFilePath(context, Uri.fromFile(File(path)))
                        val w = image.width.toDouble()
                        val h = image.height.toDouble()
                        recognizer.process(image)
                            .addOnSuccessListener { visionText ->
                                val lines = mutableListOf<Map<String, Any>>()
                                for (block in visionText.textBlocks) {
                                    for (line in block.lines) {
                                        val box = line.boundingBox ?: continue
                                        lines.add(mapOf(
                                            "text" to line.text,
                                            "left" to box.left / w, "top" to box.top / h,
                                            "width" to box.width() / w, "height" to box.height() / h,
                                        ))
                                    }
                                }
                                result.success(mapOf("width" to image.width, "height" to image.height, "lines" to lines))
                            }
                            .addOnFailureListener { e -> result.error("ocr_failed", e.message, null) }
                    } catch (e: Exception) {
                        result.error("ocr_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
