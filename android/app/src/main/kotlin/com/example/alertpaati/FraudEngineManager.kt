package com.example.alertpaati

import android.content.Context
import android.util.Log
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

        val config = EngineConfig(modelPath = modelPath)
        engine = Engine(config).also { it.initialize() }
        conversation = engine!!.createConversation()
        Log.d(TAG, "Model loaded ✓")
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
