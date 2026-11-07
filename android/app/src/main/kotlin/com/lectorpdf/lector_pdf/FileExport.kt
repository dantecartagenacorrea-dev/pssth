package com.lectorpdf.lector_pdf

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Saca documentos de la biblioteca. Canal "lector/file_export": "share" (hoja
/// Compartir con uno o varios), "save" (a Descargas/PSSTH, sin pedir permisos;
/// devuelve cuántos guardó, o -1 antes de Android 10, donde hace falta permiso).
object FileExport {
    private const val FOLDER = "PSSTH"

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "lector/file_export").setMethodCallHandler { call, result ->
            val paths = call.argument<List<String>>("paths").orEmpty()
            when (call.method) {
                "share" -> try {
                    share(activity, paths)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("share", e.message, null)
                }
                "save" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(-1)
                        return@setMethodCallHandler
                    }
                    // Copiar un libro grande no debe congelar la pantalla.
                    Thread {
                        try {
                            paths.forEach { saveToDownloads(activity, File(it)) }
                            activity.runOnUiThread { result.success(paths.size) }
                        } catch (e: Exception) {
                            activity.runOnUiThread { result.error("save", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun mimeOf(file: File): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase())
            ?: "application/octet-stream"

    private fun share(activity: Activity, paths: List<String>) {
        val files = paths.map { File(it) }
        val uris = files.map {
            FileProvider.getUriForFile(activity, "${activity.packageName}.compartir", it)
        }
        val send = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = mimeOf(files.first())
                putExtra(Intent.EXTRA_STREAM, uris.first())
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                // Si todos son del mismo tipo, las apps saben si pueden recibirlos.
                type = files.map { mimeOf(it) }.distinct().singleOrNull() ?: "*/*"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList<Uri>(uris))
            }
        }.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(send, "Compartir"))
    }

    private fun saveToDownloads(activity: Activity, file: File) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, file.name)
            put(MediaStore.Downloads.MIME_TYPE, mimeOf(file))
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("No se pudo crear ${file.name}")
        try {
            val out = resolver.openOutputStream(uri) ?: error("No se pudo escribir ${file.name}")
            out.use { output -> file.inputStream().use { it.copyTo(output) } }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            // Sin esto quedaría un archivo a medias e invisible en Descargas.
            resolver.delete(uri, null, null)
            throw e
        }
    }
}
