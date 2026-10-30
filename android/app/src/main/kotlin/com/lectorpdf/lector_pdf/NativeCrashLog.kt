package com.lectorpdf.lector_pdf

import android.content.Context
import android.os.Build
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Si la parte nativa (Kotlin/Java) se cierra, anota el error en el aparato
/// (errores_nativos.log, junto al registro de Dart). Nada se envía: la persona
/// lo comparte desde «Enviar informe de errores» si quiere.
object NativeCrashLog {
    private const val FILE = "errores_nativos.log"
    private const val MAX_BYTES = 100 * 1024
    private var installed = false

    fun install(context: Context) {
        if (installed) return
        installed = true
        val dir = context.applicationContext.filesDir
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val stack = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
                val lines = stack.lineSequence().take(30).joinToString("\n")
                val file = File(dir, FILE)
                if (file.length() > MAX_BYTES) file.delete()
                file.appendText(
                    "=== ${SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())} · android ${Build.VERSION.RELEASE} (${Build.MODEL}) · nativo, hilo ${thread.name}\n$lines\n\n"
                )
            } catch (_: Throwable) {
                // Anotar nunca debe impedir el cierre normal.
            }
            previous?.uncaughtException(thread, error)
        }
    }
}
