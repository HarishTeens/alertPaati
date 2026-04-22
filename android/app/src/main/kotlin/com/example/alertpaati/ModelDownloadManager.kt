package com.example.alertpaati

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.io.File

/**
 * Manages downloading a Gemma 4 LiteRT model file using Android's
 * [DownloadManager].
 *
 * Why DownloadManager?
 *  - Survives app backgrounding / process death
 *  - Supports HTTP range-resume after interruptions
 *  - Shows a system progress notification automatically
 *  - Handles large files (2–3 GB) without OOM
 *
 * Progress is streamed to Flutter via [progressSink] (EventChannel).
 * Each event is a Map:
 *   { "status": "downloading"|"completed"|"failed"|"paused"|"idle",
 *     "progress": 0–100,
 *     "downloadedBytes": Long,
 *     "totalBytes": Long,
 *     "modelPath": String   // only when status == "completed"
 *   }
 */
class ModelDownloadManager(private val context: Context) {

    companion object {
        private const val TAG = "ModelDownloadMgr"
        private const val POLL_INTERVAL_MS = 500L
        private const val PREF_DOWNLOAD_ID = "kavach_model_download_id"
        private const val PREF_MODEL_PATH = "kavach_model_path"
    }

    var progressSink: EventChannel.EventSink? = null

    private val downloadManager by lazy {
        context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    }

    private val prefs by lazy {
        context.getSharedPreferences("kavach_prefs", Context.MODE_PRIVATE)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var activeDownloadId = -1L
    private var pollRunnable: Runnable? = null

    // BroadcastReceiver fires when DownloadManager finishes a download
    private val completionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) ?: return
            if (id == activeDownloadId) onDownloadComplete(id)
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Start downloading the model from [url] to [destFileName] inside
     * the app's files/models directory.
     *
     * @param url          Direct HTTPS link to the .tflite file.
     * @param destFileName Filename on disk, e.g. "gemma-4-1b-it-cpu-int8.tflite".
     * @param authToken    Optional Bearer token (e.g. HuggingFace API key).
     * @return The DownloadManager download ID, or -1 on error.
     */
    fun startDownload(
        url: String,
        destFileName: String,
        authToken: String? = null,
    ): Long {
        if (activeDownloadId != -1L) {
            Log.w(TAG, "Download already in progress (id=$activeDownloadId)")
            return activeDownloadId
        }

        // DownloadManager cannot write to internal storage (filesDir) on API 29+.
        // Use app-private external files dir — no extra permissions needed.
        val destDir = context.getExternalFilesDir("models")?.also { it.mkdirs() }
            ?: File(context.filesDir, "models").also { it.mkdirs() }
        val destFile = File(destDir, destFileName)

        // Delete stale partial file
        if (destFile.exists()) destFile.delete()

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle("Downloading Gemma 4 model")
            setDescription(destFileName)
            setDestinationInExternalFilesDir(context, "models", destFileName)
            setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
            if (authToken != null) {
                addRequestHeader("Authorization", "Bearer $authToken")
            }
            setAllowedOverMetered(true)
            setAllowedOverRoaming(false)
        }

        val id = downloadManager.enqueue(request)
        activeDownloadId = id
        prefs.edit().putLong(PREF_DOWNLOAD_ID, id).apply()

        Log.d(TAG, "Download enqueued id=$id → ${destFile.absolutePath}")

        registerReceiver()
        startPolling()
        return id
    }

    fun cancelDownload() {
        if (activeDownloadId == -1L) return
        downloadManager.remove(activeDownloadId)
        activeDownloadId = -1L
        prefs.edit().remove(PREF_DOWNLOAD_ID).apply()
        stopPolling()
        unregisterReceiver()
        emit(mapOf("status" to "idle", "progress" to 0))
        Log.d(TAG, "Download cancelled")
    }

    /**
     * Returns the absolute path of the already-downloaded model, or null.
     */
    fun savedModelPath(): String? {
        val path = prefs.getString(PREF_MODEL_PATH, null)
        if (path != null && File(path).exists()) return path
        // Fallback: check external files dir directly (handles reinstalls / path migration)
        val externalDir = context.getExternalFilesDir("models") ?: return null
        return externalDir.listFiles()
            ?.firstOrNull { it.name.endsWith(".litertlm") || it.name.endsWith(".bin") }
            ?.absolutePath
    }

    /**
     * Returns the file size in bytes if the model file exists, else -1.
     */
    fun modelFileSize(): Long {
        val path = savedModelPath() ?: return -1L
        return File(path).length()
    }

    /**
     * True if a previously started download is still in progress.
     * Call this on startup to resume polling if the app was killed mid-download.
     */
    fun resumeIfActive() {
        val savedId = prefs.getLong(PREF_DOWNLOAD_ID, -1L)
        if (savedId == -1L) return
        activeDownloadId = savedId
        val status = queryStatus(savedId)
        if (status == DownloadManager.STATUS_RUNNING ||
            status == DownloadManager.STATUS_PENDING ||
            status == DownloadManager.STATUS_PAUSED
        ) {
            Log.d(TAG, "Resuming progress polling for download $savedId")
            registerReceiver()
            startPolling()
        } else {
            // Already completed or failed before the receiver could fire
            activeDownloadId = -1L
            prefs.edit().remove(PREF_DOWNLOAD_ID).apply()
        }
    }

    fun release() {
        stopPolling()
        try { unregisterReceiver() } catch (_: Exception) {}
    }

    // ── Polling ───────────────────────────────────────────────────────────────

    private fun startPolling() {
        pollRunnable = object : Runnable {
            override fun run() {
                if (activeDownloadId == -1L) return
                val event = queryProgress(activeDownloadId)
                emit(event)
                handler.postDelayed(this, POLL_INTERVAL_MS)
            }
        }
        handler.post(pollRunnable!!)
    }

    private fun stopPolling() {
        pollRunnable?.let { handler.removeCallbacks(it) }
        pollRunnable = null
    }

    // ── DownloadManager queries ───────────────────────────────────────────────

    private fun queryStatus(downloadId: Long): Int {
        val cursor = downloadManager.query(
            DownloadManager.Query().setFilterById(downloadId)
        )
        if (!cursor.moveToFirst()) { cursor.close(); return -1 }
        val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
        cursor.close()
        return status
    }

    private fun queryProgress(downloadId: Long): Map<String, Any> {
        val cursor: Cursor = downloadManager.query(
            DownloadManager.Query().setFilterById(downloadId)
        )
        if (!cursor.moveToFirst()) {
            cursor.close()
            return mapOf("status" to "idle", "progress" to 0)
        }

        val status = cursor.getInt(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
        )
        val downloaded = cursor.getLong(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
        )
        val total = cursor.getLong(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
        )
        val reason = cursor.getInt(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
        )
        cursor.close()

        val progress = if (total > 0) ((downloaded * 100) / total).toInt() else 0

        return when (status) {
            DownloadManager.STATUS_RUNNING, DownloadManager.STATUS_PENDING ->
                mapOf(
                    "status" to "downloading",
                    "progress" to progress,
                    "downloadedBytes" to downloaded,
                    "totalBytes" to total,
                )
            DownloadManager.STATUS_PAUSED ->
                mapOf(
                    "status" to "paused",
                    "progress" to progress,
                    "downloadedBytes" to downloaded,
                    "totalBytes" to total,
                    "reason" to reason,
                )
            DownloadManager.STATUS_SUCCESSFUL ->
                mapOf("status" to "completed", "progress" to 100)
            DownloadManager.STATUS_FAILED ->
                mapOf("status" to "failed", "progress" to 0, "reason" to reason)
            else ->
                mapOf("status" to "idle", "progress" to 0)
        }
    }

    private fun onDownloadComplete(downloadId: Long) {
        stopPolling()
        unregisterReceiver()

        val cursor = downloadManager.query(
            DownloadManager.Query().setFilterById(downloadId)
        )
        if (!cursor.moveToFirst()) { cursor.close(); return }

        val status = cursor.getInt(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
        )
        val localUri = cursor.getString(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
        )
        cursor.close()

        activeDownloadId = -1L
        prefs.edit().remove(PREF_DOWNLOAD_ID).apply()

        if (status == DownloadManager.STATUS_SUCCESSFUL && localUri != null) {
            val path = Uri.parse(localUri).path ?: return
            prefs.edit().putString(PREF_MODEL_PATH, path).apply()
            Log.d(TAG, "Download complete → $path")
            emit(mapOf("status" to "completed", "progress" to 100, "modelPath" to path))
        } else {
            Log.e(TAG, "Download failed (status=$status)")
            emit(mapOf("status" to "failed", "progress" to 0))
        }
    }

    // ── BroadcastReceiver ─────────────────────────────────────────────────────

    private var receiverRegistered = false

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        ContextCompat.registerReceiver(
            context, completionReceiver, filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    private fun unregisterReceiver() {
        if (!receiverRegistered) return
        try { context.unregisterReceiver(completionReceiver) } catch (_: Exception) {}
        receiverRegistered = false
    }

    // ── EventChannel emit ─────────────────────────────────────────────────────

    private fun emit(event: Map<String, Any>) {
        handler.post { progressSink?.success(event) }
    }
}
