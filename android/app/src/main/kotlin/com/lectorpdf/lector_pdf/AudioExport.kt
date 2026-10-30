package com.lectorpdf.lector_pdf

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/// Comprime un WAV (PCM de 16 bits) a M4A (AAC) para exportar audio largo: un
/// capítulo en WAV ocupa unas diez veces más. Todo en el aparato. Canal
/// "lector/audio_export", método "toM4a" (path, out → out, o null si falla),
/// el mismo que usa iOS.
object AudioExport {
    private const val BIT_RATE = 64_000
    private const val TIMEOUT_US = 10_000L

    fun register(messenger: BinaryMessenger) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, "lector/audio_export").setMethodCallHandler { call, result ->
            if (call.method != "toM4a") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path")
            val out = call.argument<String>("out")
            if (path == null || out == null) { result.error("bad_args", "Falta el archivo.", null); return@setMethodCallHandler }
            Thread {
                val ok = try { encode(File(path), File(out)); true } catch (e: Exception) { File(out).delete(); false }
                main.post { result.success(if (ok) out else null) }
            }.start()
        }
    }

    private class Wav(val sampleRate: Int, val channels: Int, val dataStart: Long, val dataSize: Long)

    /// Busca el formato y los datos dentro del WAV (los fragmentos pueden venir
    /// en cualquier orden).
    private fun readHeader(file: RandomAccessFile): Wav {
        val head = ByteArray(12)
        file.readFully(head)
        require(String(head, 0, 4) == "RIFF" && String(head, 8, 4) == "WAVE") { "No es WAV" }
        var sampleRate = 0
        var channels = 0
        val chunk = ByteArray(8)
        while (file.filePointer + 8 <= file.length()) {
            file.readFully(chunk)
            val id = String(chunk, 0, 4)
            val size = ByteBuffer.wrap(chunk, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int.toLong() and 0xFFFFFFFFL
            if (id == "fmt ") {
                val fmt = ByteArray(16)
                file.readFully(fmt)
                val b = ByteBuffer.wrap(fmt).order(ByteOrder.LITTLE_ENDIAN)
                require(b.getShort(0).toInt() == 1 && b.getShort(14).toInt() == 16) { "Solo PCM de 16 bits" }
                channels = b.getShort(2).toInt()
                sampleRate = b.getInt(4)
                file.seek(file.filePointer + size - 16 + (size and 1))
            } else if (id == "data") {
                require(sampleRate > 0) { "Falta el formato" }
                val start = file.filePointer
                return Wav(sampleRate, channels, start, minOf(size, file.length() - start))
            } else {
                file.seek(file.filePointer + size + (size and 1))
            }
        }
        throw IllegalArgumentException("WAV sin datos")
    }

    private fun encode(input: File, output: File) {
        RandomAccessFile(input, "r").use { file ->
            val wav = readHeader(file)
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, wav.sampleRate, wav.channels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
            }
            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            output.delete()
            val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                pump(file, wav, codec, muxer)
            } finally {
                codec.stop()
                codec.release()
                muxer.release()
            }
        }
    }

    private fun pump(file: RandomAccessFile, wav: Wav, codec: MediaCodec, muxer: MediaMuxer) {
        val bytesPerFrame = 2 * wav.channels
        val info = MediaCodec.BufferInfo()
        var track = -1
        var read = 0L
        var inputDone = false
        file.seek(wav.dataStart)
        val chunk = ByteArray(16 * 1024)
        while (true) {
            if (!inputDone) {
                val i = codec.dequeueInputBuffer(TIMEOUT_US)
                if (i >= 0) {
                    val buffer = codec.getInputBuffer(i)!!
                    buffer.clear()
                    val want = minOf(buffer.remaining().toLong(), chunk.size.toLong(), wav.dataSize - read).toInt()
                    val n = if (want > 0) file.read(chunk, 0, want - want % bytesPerFrame) else -1
                    val timeUs = read / bytesPerFrame * 1_000_000L / wav.sampleRate
                    if (n <= 0) {
                        codec.queueInputBuffer(i, 0, 0, timeUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        buffer.put(chunk, 0, n)
                        codec.queueInputBuffer(i, 0, n, timeUs, 0)
                        read += n
                    }
                }
            }
            // Se guarda todo lo que ya salió sin esperar; solo al final (sin más
            // entrada) se espera al códec. Esperar en cada vuelta hacía que un
            // capítulo tardara minutos.
            while (true) {
                val o = codec.dequeueOutputBuffer(info, if (inputDone) TIMEOUT_US else 0L)
                if (o == MediaCodec.INFO_TRY_AGAIN_LATER) break
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    continue
                }
                if (o < 0) continue
                val data = codec.getOutputBuffer(o)!!
                val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                if (!config && info.size > 0 && track >= 0) {
                    data.position(info.offset)
                    data.limit(info.offset + info.size)
                    muxer.writeSampleData(track, data, info)
                }
                codec.releaseOutputBuffer(o, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    if (track >= 0) muxer.stop()
                    return
                }
            }
        }
    }
}
