package com.example.alertpaati

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Captures call audio as 16-bit PCM mono WAV via [AudioRecord].
 *
 * Source: [MediaRecorder.AudioSource.VOICE_COMMUNICATION] — the correct
 * source for VoIP apps; captures the near-end microphone with AEC applied.
 *
 * Output format: WAV, 16 kHz, mono, 16-bit PCM — compatible with
 * typical speech-to-text pipelines.
 */
class AudioRecordingManager(private val context: Context) {

    companion object {
        private const val TAG = "AudioRecordMgr"

        private const val SAMPLE_RATE = 16_000       // 16 kHz
        private const val CHANNEL_IN = AudioFormat.CHANNEL_IN_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
        private const val AUDIO_SOURCE = MediaRecorder.AudioSource.VOICE_COMMUNICATION
    }

    private var recorder: AudioRecord? = null
    private var recordingThread: Thread? = null
    private val isRecording = AtomicBoolean(false)
    private var outputFile: File? = null

    private val audioManager by lazy {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Start PCM capture. Returns true on success, false if already recording
     * or if [AudioRecord] initialisation fails.
     */
    fun startRecording(): Boolean {
        if (isRecording.get()) {
            Log.w(TAG, "Already recording")
            return false
        }

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_IN, ENCODING)
            .coerceAtLeast(4096)

        val rec = AudioRecord(AUDIO_SOURCE, SAMPLE_RATE, CHANNEL_IN, ENCODING, bufferSize)
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord failed to initialise")
            rec.release()
            return false
        }

        outputFile = createOutputFile()
        recorder = rec
        isRecording.set(true)
        rec.startRecording()

        recordingThread = Thread({ captureLoop(rec, bufferSize) }, "KavachAudio")
            .also { it.start() }

        Log.d(TAG, "Recording started → ${outputFile?.absolutePath}")
        return true
    }

    /**
     * Stop recording and return the path to the WAV file, or null if
     * nothing was recorded.
     */
    fun stopRecording(): String? {
        if (!isRecording.compareAndSet(true, false)) return null

        recordingThread?.join(3_000)
        recorder?.stop()
        recorder?.release()
        recorder = null
        recordingThread = null

        val path = outputFile?.absolutePath
        Log.d(TAG, "Recording stopped → $path")
        return path
    }

    fun setMuted(muted: Boolean) {
        audioManager.isMicrophoneMute = muted
    }

    fun setSpeakerphone(enabled: Boolean) {
        audioManager.isSpeakerphoneOn = enabled
    }

    /**
     * Very lightweight placeholder transcription.
     *
     * In production, swap this for an on-device STT engine (e.g. Whisper via
     * LiteRT, or Android's SpeechRecognizer) that reads [filePath] and returns
     * the transcript string fed into [FraudEngineManager].
     */
    fun transcribeFile(filePath: String): String {
        // TODO: replace with real STT (Whisper-tiny via LiteRT recommended)
        Log.d(TAG, "transcribeFile called for $filePath — returning placeholder")
        return "[Audio recorded at $filePath — connect STT to produce transcript]"
    }

    fun release() {
        stopRecording()
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun captureLoop(rec: AudioRecord, bufferSize: Int) {
        val file = outputFile ?: return
        val pcmBuffer = ByteArray(bufferSize)

        try {
            FileOutputStream(file).use { fos ->
                // Reserve 44 bytes for WAV header — written after capture ends.
                fos.write(ByteArray(44))

                var totalPcmBytes = 0L

                while (isRecording.get()) {
                    val read = rec.read(pcmBuffer, 0, bufferSize)
                    if (read > 0) {
                        fos.write(pcmBuffer, 0, read)
                        totalPcmBytes += read
                    }
                }

                // Patch WAV header now we know the final data size.
                fos.flush()
            }

            writeWavHeader(file)
        } catch (e: Exception) {
            Log.e(TAG, "Capture loop error", e)
        }
    }

    /**
     * Re-writes the first 44 bytes of [file] with a valid RIFF/WAV header
     * based on the actual file size.
     */
    private fun writeWavHeader(file: File) {
        val pcmDataSize = (file.length() - 44).coerceAtLeast(0)
        val header = buildWavHeader(pcmDataSize)

        val raf = java.io.RandomAccessFile(file, "rw")
        raf.seek(0)
        raf.write(header)
        raf.close()
    }

    private fun buildWavHeader(pcmDataSize: Long): ByteArray {
        val totalSize = pcmDataSize + 36
        val byteRate = SAMPLE_RATE * 1 * 2 // sampleRate * channels * bytesPerSample

        return ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            // RIFF chunk
            put("RIFF".toByteArray())
            putInt(totalSize.toInt())
            put("WAVE".toByteArray())
            // fmt sub-chunk
            put("fmt ".toByteArray())
            putInt(16)                    // sub-chunk size
            putShort(1)                   // PCM = 1
            putShort(1)                   // mono
            putInt(SAMPLE_RATE)
            putInt(byteRate)
            putShort(2)                   // block align
            putShort(16)                  // bits per sample
            // data sub-chunk
            put("data".toByteArray())
            putInt(pcmDataSize.toInt())
        }.array()
    }

    private fun createOutputFile(): File {
        val dir = File(context.filesDir, "recordings").also { it.mkdirs() }
        return File(dir, "call_${System.currentTimeMillis()}.wav")
    }
}
