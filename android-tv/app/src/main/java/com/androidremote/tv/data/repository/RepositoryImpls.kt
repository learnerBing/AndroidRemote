package com.androidremote.tv.data.repository

import com.androidremote.tv.data.discovery.MdnsAdvertiser
import com.androidremote.tv.data.signaling.SignalingServer
import com.androidremote.tv.data.webrtc.WebRtcSessionManager
import com.androidremote.tv.domain.model.ConnectionState
import com.androidremote.tv.domain.model.PairingSession
import com.androidremote.tv.domain.repository.CastRepository
import com.androidremote.tv.domain.repository.SignalingRepository
import com.androidremote.tv.domain.repository.WebRtcRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class CastRepositoryImpl(
    private val mdnsAdvertiser: MdnsAdvertiser,
    private val signalingServer: SignalingServer
) : CastRepository {

    private val _connectionState = MutableStateFlow(ConnectionState.Idle)
    private val _currentPairing = MutableStateFlow<PairingSession?>(null)

    override val connectionState: Flow<ConnectionState> = _connectionState.asStateFlow()
    override val currentPairing: Flow<PairingSession?> = _currentPairing.asStateFlow()

    override suspend fun startAdvertising(deviceName: String) {
        mdnsAdvertiser.start(deviceName)
        updatePairingCode(signalingServer.currentCode())
        _connectionState.value = ConnectionState.WaitingForPair
    }

    override suspend fun stopAdvertising() {
        mdnsAdvertiser.stop()
        _connectionState.value = ConnectionState.Idle
        _currentPairing.value = null
    }

    override suspend fun refreshPairingCode(): PairingSession {
        val code = signalingServer.rotatePairingCode()
        return updatePairingCode(code)
    }

    suspend fun updatePairingCode(code: String): PairingSession {
        val session = PairingSession(
            sessionId = _currentPairing.value?.sessionId.orEmpty(),
            pairingCode = code,
            expiresAtEpochMs = System.currentTimeMillis() + 5 * 60 * 1000
        )
        _currentPairing.value = session
        return session
    }

    fun onSessionPaired(sessionId: String) {
        _connectionState.value = ConnectionState.Connecting
        _currentPairing.value = _currentPairing.value?.copy(sessionId = sessionId)
    }

    fun onConnecting() {
        _connectionState.value = ConnectionState.Connecting
    }

    fun onStreaming() {
        _connectionState.value = ConnectionState.Streaming
    }

    fun onDisconnected() {
        _connectionState.value = ConnectionState.Disconnected
    }

    fun returnToWaiting() {
        _connectionState.value = ConnectionState.WaitingForPair
    }

    suspend fun updateDeviceName(name: String) {
        mdnsAdvertiser.start(name)
    }
}

class SignalingRepositoryImpl(
    private val signalingServer: SignalingServer
) : SignalingRepository {

    override suspend fun startServer(port: Int) {
        if (!signalingServer.isAlive) {
            signalingServer.start(SOCKET_READ_TIMEOUT, false)
        }
    }

    override suspend fun stopServer() {
        signalingServer.stop()
    }
}

class WebRtcRepositoryImpl(
    private val webRtcSessionManager: WebRtcSessionManager
) : WebRtcRepository {

    override suspend fun prepareReceiver() {
        webRtcSessionManager.prepare()
    }

    override suspend fun handleRemoteOffer(sessionId: String, sdp: String) {
        webRtcSessionManager.handleRemoteOffer(sessionId, sdp)
    }

    override suspend fun disconnect() {
        webRtcSessionManager.disconnect()
    }

    fun attachRenderer(renderer: org.webrtc.SurfaceViewRenderer) {
        webRtcSessionManager.attachRenderer(renderer)
    }
}
