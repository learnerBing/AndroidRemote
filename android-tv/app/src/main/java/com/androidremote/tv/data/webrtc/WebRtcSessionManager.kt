package com.androidremote.tv.data.webrtc

import android.content.Context
import com.androidremote.tv.data.signaling.IceCandidateDto
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.EglBase
import org.webrtc.MediaConstraints
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.SessionDescription
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack
import java.util.concurrent.ConcurrentHashMap

typealias ConnectionStateCallback = (sessionId: String, state: String) -> Unit

/**
 * Manages WebRTC peer connections on the TV receiver (answerer role).
 */
class WebRtcSessionManager(
    private val context: Context,
    private val onConnectionStateChanged: ConnectionStateCallback = { _, _ -> }
) {
    private val eglBase: EglBase = EglBase.create()
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private val peerConnections = ConcurrentHashMap<String, PeerConnection>()
    private val localAnswers = ConcurrentHashMap<String, String>()
    private val pendingLocalIce = ConcurrentHashMap<String, MutableList<IceCandidateDto>>()
    private val pendingRemoteIce = ConcurrentHashMap<String, MutableList<Triple<String, String?, Int>>>()
    private val connectionStates = ConcurrentHashMap<String, String>()
    private var videoRenderer: SurfaceViewRenderer? = null
    private var remoteVideoTrack: VideoTrack? = null

    fun prepare() {
        if (peerConnectionFactory != null) return

        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .createInitializationOptions()
        )

        peerConnectionFactory = PeerConnectionFactory.builder()
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(eglBase.eglBaseContext))
            .createPeerConnectionFactory()
    }

    fun attachRenderer(renderer: SurfaceViewRenderer) {
        videoRenderer = renderer
        renderer.init(eglBase.eglBaseContext, null)
        renderer.setMirror(false)
        renderer.setEnableHardwareScaler(true)
        remoteVideoTrack?.addSink(renderer)
    }

    fun handleRemoteOffer(sessionId: String, sdp: String) {
        val factory = peerConnectionFactory ?: return
        peerConnections[sessionId]?.close()
        peerConnections.remove(sessionId)
        localAnswers.remove(sessionId)
        pendingLocalIce.remove(sessionId)

        val constraints = MediaConstraints()
        val observer = createPeerObserver(sessionId)

        val rtcConfig = PeerConnection.RTCConfiguration(
            listOf(PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer())
        ).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }

        val pc = factory.createPeerConnection(rtcConfig, observer) ?: return
        peerConnections[sessionId] = pc

        val offer = SessionDescription(SessionDescription.Type.OFFER, sdp)
        pc.setRemoteDescription(object : org.webrtc.SdpObserver {
            override fun onCreateSuccess(desc: SessionDescription?) = Unit
            override fun onSetSuccess() {
                flushPendingRemoteIce(sessionId, pc)
                pc.createAnswer(object : org.webrtc.SdpObserver {
                    override fun onCreateSuccess(answer: SessionDescription?) {
                        answer ?: return
                        pc.setLocalDescription(object : org.webrtc.SdpObserver {
                            override fun onCreateSuccess(desc: SessionDescription?) = Unit
                            override fun onSetSuccess() {
                                localAnswers[sessionId] = answer.description
                            }
                            override fun onCreateFailure(error: String?) = Unit
                            override fun onSetFailure(error: String?) = Unit
                        }, answer)
                    }
                    override fun onSetSuccess() = Unit
                    override fun onCreateFailure(error: String?) = Unit
                    override fun onSetFailure(error: String?) = Unit
                }, constraints)
            }
            override fun onCreateFailure(error: String?) = Unit
            override fun onSetFailure(error: String?) = Unit
        }, offer)
    }

    private fun createPeerObserver(sessionId: String) = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState?) = Unit

        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
            val mapped = when (state) {
                PeerConnection.IceConnectionState.CONNECTED,
                PeerConnection.IceConnectionState.COMPLETED -> "connected"
                PeerConnection.IceConnectionState.DISCONNECTED -> "disconnected"
                PeerConnection.IceConnectionState.FAILED -> "error"
                else -> "connecting"
            }
            connectionStates[sessionId] = mapped
            onConnectionStateChanged(sessionId, mapped)
        }

        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) = Unit

        override fun onIceCandidate(candidate: org.webrtc.IceCandidate?) {
            candidate ?: return
            val list = pendingLocalIce.getOrPut(sessionId) { mutableListOf() }
            list.add(
                IceCandidateDto(
                    candidate = candidate.sdp,
                    sdpMid = candidate.sdpMid,
                    sdpMLineIndex = candidate.sdpMLineIndex
                )
            )
        }

        override fun onIceCandidatesRemoved(candidates: Array<out org.webrtc.IceCandidate>?) = Unit
        override fun onAddStream(stream: org.webrtc.MediaStream?) = Unit
        override fun onRemoveStream(stream: org.webrtc.MediaStream?) = Unit
        override fun onDataChannel(channel: org.webrtc.DataChannel?) = Unit
        override fun onRenegotiationNeeded() = Unit

        override fun onAddTrack(
            receiver: org.webrtc.RtpReceiver?,
            streams: Array<out org.webrtc.MediaStream>?
        ) {
            val track = receiver?.track()
            if (track is VideoTrack) {
                remoteVideoTrack = track
                videoRenderer?.let { track.addSink(it) }
            }
        }
    }

    fun getLocalAnswer(sessionId: String): String? = localAnswers[sessionId]

    fun addRemoteIceCandidate(sessionId: String, candidate: String, sdpMid: String?, sdpMLineIndex: Int) {
        val pc = peerConnections[sessionId]
        if (pc == null || pc.remoteDescription == null) {
            val queue = pendingRemoteIce.getOrPut(sessionId) { mutableListOf() }
            queue.add(Triple(candidate, sdpMid, sdpMLineIndex))
            return
        }
        pc.addIceCandidate(org.webrtc.IceCandidate(sdpMid, sdpMLineIndex, candidate))
    }

    private fun flushPendingRemoteIce(sessionId: String, pc: PeerConnection) {
        val queued = pendingRemoteIce.remove(sessionId) ?: return
        queued.forEach { (candidate, sdpMid, index) ->
            pc.addIceCandidate(org.webrtc.IceCandidate(sdpMid, index, candidate))
        }
    }

    fun drainLocalIceCandidates(sessionId: String): List<IceCandidateDto> {
        val list = pendingLocalIce[sessionId] ?: return emptyList()
        if (list.isEmpty()) return emptyList()
        val copy = list.toList()
        list.clear()
        return copy
    }

    fun connectionState(sessionId: String): String? = connectionStates[sessionId]

    fun disconnect() {
        peerConnections.values.forEach { it.close() }
        peerConnections.clear()
        localAnswers.clear()
        pendingLocalIce.clear()
        pendingRemoteIce.clear()
        connectionStates.clear()
        remoteVideoTrack?.removeSink(videoRenderer)
        remoteVideoTrack = null
    }

    fun release() {
        disconnect()
        videoRenderer?.release()
        videoRenderer = null
        peerConnectionFactory?.dispose()
        peerConnectionFactory = null
        eglBase.release()
    }
}
