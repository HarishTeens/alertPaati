package com.example.alertpaati

import android.net.Uri
import android.os.Bundle
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Android [ConnectionService] that owns the call lifecycle.
 *
 * Bridges Telecom Manager events → Flutter via [MainActivity.callEventSink].
 * Also kicks off [AudioRecordingManager] once the call becomes active.
 */
class KavachConnectionService : ConnectionService() {

    companion object {
        private const val TAG = "KavachConnSvc"

        /** Held so [MainActivity] can call disconnect() on End-Call press. */
        var activeConnection: KavachConnection? = null
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest,
    ): Connection {
        val number = request.address?.schemeSpecificPart ?: "unknown"
        Log.d(TAG, "Creating outgoing connection to $number")

        val conn = KavachConnection(applicationContext as android.app.Application, number)
        activeConnection = conn

        emit("dialing", mapOf("number" to number))
        return conn
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest,
    ) {
        Log.e(TAG, "Outgoing connection failed")
        emit("ended", emptyMap())
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest,
    ): Connection {
        val number = request.address?.schemeSpecificPart ?: "unknown"
        Log.d(TAG, "Incoming connection from $number")

        val conn = KavachConnection(applicationContext as android.app.Application, number)
        activeConnection = conn
        emit("ringing", mapOf("number" to number))
        return conn
    }

    private fun emit(type: String, extra: Map<String, Any>) {
        val payload = extra.toMutableMap()
        payload["type"] = type
        MainActivity.callEventSink?.success(payload)
    }
}

/**
 * A single call connection. Manages state transitions and notifies Flutter
 * via [MainActivity.callEventSink].
 */
class KavachConnection(
    private val app: android.app.Application,
    private val number: String,
) : Connection() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var durationMs = 0L
    private var recording = false

    init {
        connectionCapabilities = (
            CAPABILITY_HOLD or
            CAPABILITY_SUPPORT_HOLD or
            CAPABILITY_MUTE or
            CAPABILITY_MANAGE_CONFERENCE
        )
        audioModeIsVoip = true
        setDialing()
    }

    override fun onStateChanged(state: Int) {
        super.onStateChanged(state)
        Log.d("KavachConn", "State changed: $state")
        when (state) {
            STATE_ACTIVE -> onActive()
            STATE_DISCONNECTED -> onDisconnected()
        }
    }

    override fun onAnswer() {
        setActive()
        onActive()
    }

    override fun onDisconnect() {
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        onDisconnected()
    }

    override fun onHold() = setOnHold()
    override fun onUnhold() = setActive()

    override fun onCallAudioStateChanged(state: CallAudioState) {
        // Audio routing changes (earpiece ↔ speaker) are handled here
        Log.d("KavachConn", "Audio state: ${state.route}")
    }

    private fun onActive() {
        emit("active", mapOf("number" to number))

        // Start PCM recording via the app-level manager
        val audioMgr = AudioRecordingManager(app)
        if (audioMgr.startRecording()) {
            recording = true
            emit("recordingStarted", emptyMap())
        }

        // Tick call duration every second
        scope.launch {
            while (state == STATE_ACTIVE) {
                delay(1_000)
                durationMs += 1_000
                emit("duration", mapOf("ms" to durationMs))
            }
        }
    }

    private fun onDisconnected() {
        if (recording) {
            val path = AudioRecordingManager(app).stopRecording()
            recording = false
            emit("ended", mapOf("recordingPath" to (path ?: "")))
        } else {
            emit("ended", emptyMap())
        }
        KavachConnectionService.activeConnection = null
    }

    private fun emit(type: String, extra: Map<String, Any>) {
        val payload = extra.toMutableMap()
        payload["type"] = type
        MainActivity.callEventSink?.success(payload)
    }
}
