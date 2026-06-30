package com.androidremote.tv.di

import android.content.Context
import com.androidremote.tv.data.discovery.MdnsAdvertiser
import com.androidremote.tv.data.repository.CastRepositoryImpl
import com.androidremote.tv.data.repository.SignalingRepositoryImpl
import com.androidremote.tv.data.repository.WebRtcRepositoryImpl
import com.androidremote.tv.data.service.CastReceiverService
import com.androidremote.tv.data.signaling.SignalingServer
import com.androidremote.tv.data.webrtc.WebRtcSessionManager
import com.androidremote.tv.domain.usecase.ObservePairingUseCase
import com.androidremote.tv.domain.usecase.ObserveReceiverStateUseCase
import com.androidremote.tv.domain.usecase.StartReceiverUseCase
import com.androidremote.tv.domain.usecase.StopReceiverUseCase
import com.androidremote.tv.data.settings.TvSettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class AppContainer(context: Context) {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val settingsRepository = TvSettingsRepository(appContext)

    val webRtcSessionManager = WebRtcSessionManager(appContext) { sessionId, state ->
        when (state) {
            "connected" -> castRepository.onStreaming()
            "disconnected", "error" -> scope.launch {
                castRepository.onDisconnected()
                castRepository.refreshPairingCode()
                castRepository.returnToWaiting()
            }
            "connecting" -> castRepository.onConnecting()
        }
    }

    private val signalingServer = SignalingServer(
        port = CastReceiverService.SIGNALING_PORT,
        onSessionPaired = { sessionId ->
            scope.launch { castRepository.onSessionPaired(sessionId) }
        },
        webRtcSessionManager = webRtcSessionManager,
        onPairingCodeRotated = { code ->
            scope.launch { castRepository.updatePairingCode(code) }
        }
    )

    val castRepository = CastRepositoryImpl(
        mdnsAdvertiser = MdnsAdvertiser(appContext, CastReceiverService.SIGNALING_PORT),
        signalingServer = signalingServer
    )

    val webRtcRepository = WebRtcRepositoryImpl(webRtcSessionManager)
    private val signalingRepository = SignalingRepositoryImpl(signalingServer)

    val startReceiverUseCase = StartReceiverUseCase(
        castRepository = castRepository,
        signalingRepository = signalingRepository,
        webRtcRepository = webRtcRepository,
        signalingPort = CastReceiverService.SIGNALING_PORT
    )

    val stopReceiverUseCase = StopReceiverUseCase(
        castRepository = castRepository,
        signalingRepository = signalingRepository,
        webRtcRepository = webRtcRepository
    )

    val observeReceiverStateUseCase = ObserveReceiverStateUseCase(castRepository)
    val observePairingUseCase = ObservePairingUseCase(castRepository)

    @Volatile
    private var receiverStarted = false

    fun ensureReceiverStarted(deviceName: String) {
        if (receiverStarted) return
        receiverStarted = true
        scope.launch {
            val name = settingsRepository.current().deviceName.ifBlank { deviceName }
            startReceiverUseCase(name)
            castRepository.updatePairingCode(signalingServer.currentCode())
        }
    }

    suspend fun updateDeviceName(name: String) {
        castRepository.updateDeviceName(name)
    }
}
