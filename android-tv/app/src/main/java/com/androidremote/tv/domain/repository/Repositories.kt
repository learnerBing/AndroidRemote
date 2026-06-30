package com.androidremote.tv.domain.repository

import com.androidremote.tv.domain.model.ConnectionState
import com.androidremote.tv.domain.model.PairingSession
import kotlinx.coroutines.flow.Flow

interface CastRepository {
    val connectionState: Flow<ConnectionState>
    val currentPairing: Flow<PairingSession?>

    suspend fun startAdvertising(deviceName: String)
    suspend fun stopAdvertising()
    suspend fun refreshPairingCode(): PairingSession
}

interface SignalingRepository {
    suspend fun startServer(port: Int)
    suspend fun stopServer()
}

interface WebRtcRepository {
    suspend fun prepareReceiver()
    suspend fun handleRemoteOffer(sessionId: String, sdp: String)
    suspend fun disconnect()
}
