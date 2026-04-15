package com.example.alertpaati

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "KavachMain"
        private const val CH_CALL = "kavach/call"
        private const val CH_FRAUD = "kavach/fraud"
        private const val CH_RECORDING = "kavach/recording"
        private const val CH_MODEL = "kavach/model"
        private const val EV_CALL = "kavach/callEvents"
        private const val EV_FRAUD = "kavach/fraudEvents"
        private const val EV_DOWNLOAD = "kavach/downloadProgress"

        private const val REQ_PERMISSIONS = 100

        // Emitted to Flutter via EventChannels
        var callEventSink: EventChannel.EventSink? = null
        var fraudEventSink: EventChannel.EventSink? = null
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private lateinit var audioManager: AudioRecordingManager
    private lateinit var fraudEngine: FraudEngineManager
    private lateinit var overlayService: FraudOverlayService
    private lateinit var modelDownloader: ModelDownloadManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestRequiredPermissions()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = AudioRecordingManager(this)
        fraudEngine = FraudEngineManager(this)
        overlayService = FraudOverlayService(this)
        modelDownloader = ModelDownloadManager(this)

        setupCallChannel(flutterEngine)
        setupFraudChannel(flutterEngine)
        setupRecordingChannel(flutterEngine)
        setupModelChannel(flutterEngine)
        setupCallEventChannel(flutterEngine)
        setupFraudEventChannel(flutterEngine)
        setupDownloadProgressChannel(flutterEngine)

        // Resume polling if app was killed during a download
        modelDownloader.resumeIfActive()
    }

    // ── Call Channel ─────────────────────────────────────────────────────────

    private fun setupCallChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_CALL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dialNumber" -> {
                        val number = call.argument<String>("number") ?: run {
                            result.error("INVALID_ARG", "number required", null)
                            return@setMethodCallHandler
                        }
                        dialNumber(number, result)
                    }
                    "endCall" -> endCall(result)
                    "setMute" -> {
                        val muted = call.argument<Boolean>("muted") ?: false
                        audioManager.setMuted(muted)
                        result.success(null)
                    }
                    "setSpeaker" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        audioManager.setSpeakerphone(enabled)
                        result.success(null)
                    }
                    "requestPhoneAccount" -> {
                        val granted = ensurePhoneAccount()
                        result.success(granted)
                    }
                    "showOverlay" -> {
                        @Suppress("UNCHECKED_CAST")
                        val map = call.arguments as? Map<String, Any> ?: emptyMap()
                        overlayService.show(map)
                        result.success(null)
                    }
                    "hideOverlay" -> {
                        overlayService.hide()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Fraud Channel ─────────────────────────────────────────────────────────

    private fun setupFraudChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_FRAUD)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "analyzeTranscript" -> {
                        val transcript = call.argument<String>("transcript") ?: ""
                        scope.launch(Dispatchers.IO) {
                            try {
                                val fraudResult = fraudEngine.analyzeTranscript(transcript)
                                scope.launch(Dispatchers.Main) {
                                    result.success(fraudResult)
                                    fraudEventSink?.success(fraudResult)
                                }
                            } catch (e: Exception) {
                                scope.launch(Dispatchers.Main) {
                                    result.error("FRAUD_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "analyzeAudioFile" -> {
                        val path = call.argument<String>("path") ?: run {
                            result.error("INVALID_ARG", "path required", null)
                            return@setMethodCallHandler
                        }
                        scope.launch(Dispatchers.IO) {
                            try {
                                val transcript = audioManager.transcribeFile(path)
                                val fraudResult = fraudEngine.analyzeTranscript(transcript)
                                scope.launch(Dispatchers.Main) {
                                    result.success(fraudResult)
                                    fraudEventSink?.success(fraudResult)
                                }
                            } catch (e: Exception) {
                                scope.launch(Dispatchers.Main) {
                                    result.error("FRAUD_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "isModelLoaded" -> result.success(fraudEngine.isLoaded)
                    "loadModel" -> {
                        val path = call.argument<String>("path") ?: run {
                            result.error("INVALID_ARG", "path required", null)
                            return@setMethodCallHandler
                        }
                        scope.launch(Dispatchers.IO) {
                            try {
                                fraudEngine.loadModel(path)
                                scope.launch(Dispatchers.Main) { result.success(null) }
                            } catch (e: Exception) {
                                scope.launch(Dispatchers.Main) {
                                    result.error("MODEL_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Recording Channel ─────────────────────────────────────────────────────

    private fun setupRecordingChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_RECORDING)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> {
                        if (!hasPermission(Manifest.permission.RECORD_AUDIO)) {
                            result.error("NO_PERMISSION", "RECORD_AUDIO denied", null)
                            return@setMethodCallHandler
                        }
                        val started = audioManager.startRecording()
                        result.success(started)
                    }
                    "stopRecording" -> {
                        val path = audioManager.stopRecording()
                        result.success(path)
                        // Kick off post-call fraud analysis automatically
                        if (path != null) analyzeCallRecording(path)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Model Channel ─────────────────────────────────────────────────────────

    private fun setupModelChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_MODEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkModel" -> {
                        result.success(mapOf(
                            "downloaded" to (modelDownloader.savedModelPath() != null),
                            "loaded"     to fraudEngine.isLoaded,
                            "path"       to (modelDownloader.savedModelPath() ?: ""),
                            "sizeBytes"  to modelDownloader.modelFileSize(),
                        ))
                    }
                    "startDownload" -> {
                        val url   = call.argument<String>("url") ?: run {
                            result.error("INVALID_ARG", "url required", null)
                            return@setMethodCallHandler
                        }
                        val name  = call.argument<String>("fileName") ?: "gemma-4-1b-it-cpu-int8.tflite"
                        val token = call.argument<String>("authToken")
                        val id    = modelDownloader.startDownload(url, name, token)
                        result.success(id)
                    }
                    "cancelDownload" -> {
                        modelDownloader.cancelDownload()
                        result.success(null)
                    }
                    "deleteModel" -> {
                        val path = modelDownloader.savedModelPath()
                        if (path != null) {
                            java.io.File(path).delete()
                            fraudEngine.close()
                        }
                        result.success(null)
                    }
                    "loadModel" -> {
                        val path = call.argument<String>("path")
                            ?: modelDownloader.savedModelPath()
                            ?: run {
                                result.error("NO_MODEL", "No model file found", null)
                                return@setMethodCallHandler
                            }
                        val useGpu = call.argument<Boolean>("useGpu") ?: false
                        scope.launch(Dispatchers.IO) {
                            try {
                                fraudEngine.loadModel(path, useGpu)
                                scope.launch(Dispatchers.Main) { result.success(null) }
                            } catch (e: Exception) {
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

    // ── Event Channels ────────────────────────────────────────────────────────

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

    private fun setupCallEventChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, EV_CALL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    callEventSink = sink
                }
                override fun onCancel(args: Any?) {
                    callEventSink = null
                }
            })
    }

    private fun setupFraudEventChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, EV_FRAUD)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    fraudEventSink = sink
                }
                override fun onCancel(args: Any?) {
                    fraudEventSink = null
                }
            })
    }

    // ── Telecom ───────────────────────────────────────────────────────────────

    private fun dialNumber(number: String, result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.CALL_PHONE)) {
            result.error("NO_PERMISSION", "CALL_PHONE denied", null)
            return
        }
        try {
            val telecom = getSystemService(TELECOM_SERVICE) as TelecomManager
            val handle = PhoneAccountHandle(
                ComponentName(this, KavachConnectionService::class.java),
                "kavach_account"
            )
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
            }
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
                == PackageManager.PERMISSION_GRANTED
            ) {
                telecom.placeCall(Uri.parse("tel:$number"), extras)
                result.success(null)
            } else {
                result.error("NO_PERMISSION", "CALL_PHONE denied", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "dialNumber failed", e)
            result.error("DIAL_ERROR", e.message, null)
        }
    }

    private fun endCall(result: MethodChannel.Result) {
        try {
            KavachConnectionService.activeConnection?.onDisconnect()
            result.success(null)
        } catch (e: Exception) {
            result.error("END_CALL_ERROR", e.message, null)
        }
    }

    private fun ensurePhoneAccount(): Boolean {
        val telecom = getSystemService(TELECOM_SERVICE) as TelecomManager
        val handle = PhoneAccountHandle(
            ComponentName(this, KavachConnectionService::class.java),
            "kavach_account"
        )
        return telecom.getPhoneAccount(handle) != null
    }

    // ── Post-call analysis ────────────────────────────────────────────────────

    private fun analyzeCallRecording(path: String) {
        scope.launch(Dispatchers.IO) {
            try {
                val transcript = audioManager.transcribeFile(path)
                if (transcript.isNotBlank()) {
                    val fraudResult = fraudEngine.analyzeTranscript(transcript)
                    scope.launch(Dispatchers.Main) {
                        fraudEventSink?.success(fraudResult)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Post-call analysis failed", e)
            }
        }
    }

    // ── Permissions ───────────────────────────────────────────────────────────

    private fun requestRequiredPermissions() {
        val needed = listOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
        ).filter { !hasPermission(it) }

        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), REQ_PERMISSIONS)
        }
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    override fun onDestroy() {
        super.onDestroy()
        audioManager.release()
        fraudEngine.close()
        overlayService.hide()
        modelDownloader.release()
    }
}
