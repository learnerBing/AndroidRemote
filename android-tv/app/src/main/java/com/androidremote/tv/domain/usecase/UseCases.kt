package com.androidremote.tv.domain.usecase

import com.androidremote.tv.domain.model.ConnectionState
import com.androidremote.tv.domain.model.PairingSession
import com.androidremote.tv.domain.repository.CastRepository
import com.androidremote.tv.domain.repository.SignalingRepository
import com.androidremote.tv.domain.repository.WebRtcRepository
import kotlinx.coroutines.flow.Flow

class StartReceiverUseCase(
    private val castRepository: CastRepository,
    private val signalingRepository: SignalingRepository,
    private val webRtcRepository: WebRtcRepository,
    private val signalingPort: Int = 8765
) {
    suspend operator fun invoke(deviceName: String): PairingSession {
        webRtcRepository.prepareReceiver()
        signalingRepository.startServer(signalingPort)
        castRepository.startAdvertising(deviceName)
        return castRepository.refreshPairingCode()
    }
}

class ObserveReceiverStateUseCase(
    private val castRepository: CastRepository
) {
    operator fun invoke(): Flow<ConnectionState> = castRepository.connectionState
}

class ObservePairingUseCase(
    private val castRepository: CastRepository
) {
    operator fun invoke(): Flow<PairingSession?> = castRepository.currentPairing
}

class StopReceiverUseCase(
    private val castRepository: CastRepository,
    private val signalingRepository: SignalingRepository,
    private val webRtcRepository: WebRtcRepository
) {
    suspend operator fun invoke() {
        webRtcRepository.disconnect()
        signalingRepository.stopServer()
        castRepository.stopAdvertising()
    }
}
