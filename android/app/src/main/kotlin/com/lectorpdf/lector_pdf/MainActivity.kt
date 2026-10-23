package com.lectorpdf.lector_pdf

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Recibe archivos compartidos/abiertos desde otras apps (ACTION_VIEW / ACTION_SEND)
/// y los entrega a Flutter por el canal "lector/open_file". Todo local.
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null
    /// Dart ya escucha el canal (lo sabemos cuando pide "takePending").
    /// Antes de eso un "opened" se perdería: el archivo se guarda como pendiente.
    private var dartListo = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NativeTextTools.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lector/open_file")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> { dartListo = true; result.success(pending); pending = null }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lector/share").setMethodCallHandler { call, result ->
            if (call.method != "shareFile") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val path = call.argument<String>("path")!!
                val text = call.argument<String>("text") ?: ""
                val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.compartir", File(path))
                val mime = if (path.endsWith(".wav")) "audio/wav" else "audio/*"
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = mime
                    putExtra(Intent.EXTRA_STREAM, uri)
                    if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(send, "Compartir audio"))
                result.success(true)
            } catch (e: Exception) {
                result.error("share", e.message, null)
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        // Relanzar desde el icono/recientes reutiliza el intent original: no reabrir.
        if (intent != null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val uri: Uri? = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } ?: return
        try {
            val name = displayName(uri!!)
            val target = File(cacheDir, "abrir_" + System.currentTimeMillis() + "_" + name)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { input.copyTo(it) }
            } ?: return
            val payload = mapOf("path" to target.absolutePath, "name" to name)
            val ch = channel
            if (ch != null && dartListo) ch.invokeMethod("opened", payload) else pending = payload
            // Evitar reabrir el mismo archivo al rotar/recrear la actividad.
            intent?.action = Intent.ACTION_MAIN
        } catch (_: Exception) {
        }
    }

    private fun displayName(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        }
        if (name.isNullOrBlank()) name = uri.lastPathSegment?.substringAfterLast('/')
        return (name ?: "documento").replace(Regex("[\\\\/:*?\"<>|]"), "_")
    }
}
