package com.example.alertpaati

import android.util.Log
import com.google.ai.edge.litertlm.Content
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CH_MODEL = "kavach/model"
        private const val CH_CHAT = "kavach/chat"
        private const val EV_DOWNLOAD = "kavach/downloadProgress"
        private const val EV_CHAT = "kavach/chatStream"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var gemmaEngine: GemmaEngine
    private lateinit var modelDownloader: ModelDownloadManager
    private var chatTokenSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        gemmaEngine = GemmaEngine(this)
        modelDownloader = ModelDownloadManager(this)

        setupModelChannel(flutterEngine)
        setupChatChannel(flutterEngine)
        setupDownloadProgressChannel(flutterEngine)
        setupChatStreamChannel(flutterEngine)

        modelDownloader.resumeIfActive()
    }

    private fun setupModelChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_MODEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkModel" -> {
                        result.success(mapOf(
                            "downloaded" to (modelDownloader.savedModelPath() != null),
                            "loaded"     to gemmaEngine.isLoaded,
                            "path"       to (modelDownloader.savedModelPath() ?: ""),
                            "sizeBytes"  to modelDownloader.modelFileSize(),
                        ))
                    }
                    "startDownload" -> {
                        val url = call.argument<String>("url") ?: run {
                            result.error("INVALID_ARG", "url required", null)
                            return@setMethodCallHandler
                        }
                        val name = call.argument<String>("fileName") ?: "gemma-4-E2B-it.litertlm"
                        val id = modelDownloader.startDownload(url, name)
                        result.success(id)
                    }
                    "cancelDownload" -> {
                        modelDownloader.cancelDownload()
                        result.success(null)
                    }
                    "deleteModel" -> {
                        val path = modelDownloader.savedModelPath()
                        if (path != null) java.io.File(path).delete()
                        gemmaEngine.close()
                        result.success(null)
                    }
                    "loadModel" -> {
                        val path = modelDownloader.savedModelPath() ?: run {
                            result.error("NO_MODEL", "No model file found", null)
                            return@setMethodCallHandler
                        }
                        val useGpu = call.argument<Boolean>("useGpu") ?: false
                        scope.launch(Dispatchers.IO) {
                            try {
                                gemmaEngine.loadModel(path, useGpu)
                                scope.launch(Dispatchers.Main) { result.success(null) }
                            } catch (e: Exception) {
                                Log.e(TAG, "loadModel failed", e)
                                scope.launch(Dispatchers.Main) {
                                    result.error("LOAD_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupChatChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_CHAT)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startChat" -> {
                        val message = call.argument<String>("message") ?: run {
                            result.error("INVALID_ARG", "message required", null)
                            return@setMethodCallHandler
                        }
                        // Return immediately so Flutter can start listening before tokens arrive
                        result.success(null)
                        scope.launch(Dispatchers.IO) {
                            gemmaEngine.chatStreamFlow(message)
                                .catch { e ->
                                    Log.e(TAG, "chatStream error", e)
                                    scope.launch(Dispatchers.Main) {
                                        chatTokenSink?.error("CHAT_ERROR", e.message, null)
                                    }
                                }
                                .collect { msg ->
                                    val text = msg.contents.contents
                                        .filterIsInstance<Content.Text>()
                                        .joinToString("") { it.text }
                                    scope.launch(Dispatchers.Main) {
                                        chatTokenSink?.success(mapOf("token" to text, "done" to false))
                                    }
                                }
                            scope.launch(Dispatchers.Main) {
                                chatTokenSink?.success(mapOf("token" to "", "done" to true))
                            }
                        }
                    }
                    "resetConversation" -> {
                        gemmaEngine.resetConversation()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupDownloadProgressChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, EV_DOWNLOAD)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    modelDownloader.progressSink = sink
                }
                override fun onCancel(args: Any?) {
                    modelDownloader.progressSink = null
                }
            })
    }

    private fun setupChatStreamChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, EV_CHAT)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    chatTokenSink = sink
                }
                override fun onCancel(args: Any?) {
                    chatTokenSink = null
                }
            })
    }

    override fun onDestroy() {
        super.onDestroy()
        gemmaEngine.close()
        modelDownloader.release()
    }
}
