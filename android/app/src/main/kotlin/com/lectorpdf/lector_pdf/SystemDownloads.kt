package com.lectorpdf.lector_pdf

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Descargas grandes (modelos de voz y transcripción) con el gestor de
/// descargas del sistema: siguen aunque la app pase a segundo plano o se
/// cierre, y muestran el avance en la barra de notificaciones. Canal
/// "lector/download": "enqueue" (url, name, title → id y ruta), "query" (id →
/// estado y bytes) y "remove" (id).
object SystemDownloads {
    fun register(context: Context, messenger: BinaryMessenger) {
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        MethodChannel(messenger, "lector/download").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "enqueue" -> {
                        val url = call.argument<String>("url")
                        val name = call.argument<String>("name")
                        if (url == null || name == null) {
                            result.error("bad_args", "Falta la dirección o el nombre.", null)
                            return@setMethodCallHandler
                        }
                        val file = File(context.getExternalFilesDir(null), "models/$name")
                        file.parentFile?.mkdirs()
                        if (file.exists()) file.delete()
                        val request = DownloadManager.Request(Uri.parse(url))
                            .setTitle(call.argument<String>("title") ?: "PSSTH!")
                            .setDescription("PSSTH!")
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            .setDestinationUri(Uri.fromFile(file))
                            .setAllowedOverMetered(true)
                            .setAllowedOverRoaming(true)
                        val id = manager.enqueue(request)
                        result.success(mapOf("id" to id, "path" to file.absolutePath))
                    }
                    "query" -> {
                        val id = (call.argument<Number>("id") ?: -1).toLong()
                        manager.query(DownloadManager.Query().setFilterById(id)).use { c ->
                            if (!c.moveToFirst()) {
                                result.success(mapOf("status" to "missing"))
                                return@use
                            }
                            val status = when (c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                                DownloadManager.STATUS_FAILED -> "failed"
                                DownloadManager.STATUS_PAUSED -> "paused"
                                DownloadManager.STATUS_PENDING -> "pending"
                                else -> "running"
                            }
                            result.success(
                                mapOf(
                                    "status" to status,
                                    "done" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                                    "total" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
                                    "reason" to c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)),
                                )
                            )
                        }
                    }
                    "remove" -> {
                        val id = (call.argument<Number>("id") ?: -1).toLong()
                        if (id >= 0) manager.remove(id)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("download_failed", e.message, null)
            }
        }
    }
}
