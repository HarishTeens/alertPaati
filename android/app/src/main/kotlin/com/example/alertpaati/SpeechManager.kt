package com.example.alertpaati

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.EventChannel

class SpeechManager(private val context: Context) {

    companion object {
        private const val TAG = "SpeechManager"
    }

    var eventSink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var isActive = false

    fun startListening() {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            eventSink?.success(mapOf("status" to "error", "message" to "Speech recognition not available on this device"))
            return
        }
        isActive = true
        startListeningInternal()
    }

    fun stopListening() {
        isActive = false
        recognizer?.stopListening()
        recognizer?.destroy()
        recognizer = null
        eventSink?.success(mapOf("status" to "idle"))
    }

    private fun startListeningInternal() {
        recognizer?.destroy()
        recognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
            setRecognitionListener(listener)
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        recognizer?.startListening(intent)
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            eventSink?.success(mapOf("status" to "listening"))
        }
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {
            eventSink?.success(mapOf("status" to "rms", "rms" to rmsdB.toDouble()))
        }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {
            eventSink?.success(mapOf("status" to "processing"))
        }
        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull() ?: ""
            if (text.isNotEmpty()) {
                eventSink?.success(mapOf("status" to "result", "text" to text, "isFinal" to false))
            }
        }
        override fun onResults(results: Bundle?) {
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull() ?: ""
            eventSink?.success(mapOf("status" to "result", "text" to text, "isFinal" to true))
            // Auto-restart for continuous transcription
            if (isActive) startListeningInternal()
        }
        override fun onError(error: Int) {
            Log.w(TAG, "Speech error: $error")
            val recoverable = error == SpeechRecognizer.ERROR_NO_MATCH ||
                              error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
            if (isActive && recoverable) {
                startListeningInternal()
            } else {
                isActive = false
                eventSink?.success(mapOf("status" to "error", "code" to error))
            }
        }
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    fun destroy() {
        isActive = false
        recognizer?.destroy()
        recognizer = null
    }
}
