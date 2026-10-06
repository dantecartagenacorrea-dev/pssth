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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lector/open_file")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> { result.success(pending); pending = null }
                else -> result.notImplemented()
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
            if (ch != null) ch.invokeMethod("opened", payload) else pending = payload
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
