package com.example.alertpaati

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig

class GemmaEngine(private val context: Context) {

    companion object {
        private const val TAG = "GemmaEngine"
    }

    private var engine: Engine? = null
    private var conversation: Conversation? = null

    val isLoaded: Boolean get() = engine != null

    fun loadModel(modelPath: String) {
        Log.d(TAG, "Loading Gemma 4 from $modelPath")
        engine?.close()
        conversation = null

        engine = tryLoadWithBackend(modelPath, Backend.GPU())
            ?: tryLoadWithBackend(modelPath, Backend.CPU())
            ?: error("Failed to load model on both GPU and CPU")
        conversation = engine!!.createConversation()
        Log.d(TAG, "Model loaded ✓")
    }

    private fun tryLoadWithBackend(modelPath: String, backend: Backend): Engine? {
        return try {
            Log.d(TAG, "Trying $backend backend…")
            val config = EngineConfig(
                modelPath = modelPath,
                cacheDir = context.cacheDir.path,
                backend = backend,
            )
            Engine(config).also { it.initialize() }.also {
                Log.d(TAG, "$backend backend initialised ✓")
            }
        } catch (e: Exception) {
            Log.w(TAG, "$backend backend unavailable: ${e.message}")
            null
        }
    }

    fun chat(message: String): String {
        val conv = conversation ?: error("Model not loaded")
        val reply = conv.sendMessage(message)
        return reply.contents.contents
            .filterIsInstance<Content.Text>()
            .joinToString("") { it.text }
    }

    fun resetConversation() {
        val eng = engine ?: return
        conversation?.close()
        conversation = eng.createConversation()
    }

    fun close() {
        conversation?.close()
        conversation = null
        engine?.close()
        engine = null
    }
}
