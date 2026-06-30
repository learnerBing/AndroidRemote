package com.androidremote.tv.data.signaling

import com.androidremote.tv.data.webrtc.WebRtcSessionManager
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import fi.iki.elonen.NanoHTTPD
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class SignalingServer(
    port: Int,
    private val onSessionPaired: (String) -> Unit,
    private val webRtcSessionManager: WebRtcSessionManager,
    private val onPairingCodeRotated: (String) -> Unit = {}
) : NanoHTTPD(port) {

    private val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    private data class Session(
        val id: String,
        val code: String,
        val expiresAtMs: Long,
        var state: String = "waiting",
        var remoteOffer: SdpMessage? = null,
        val iceCandidates: MutableList<IceCandidateDto> = mutableListOf()
    )

    private val sessions = ConcurrentHashMap<String, Session>()
    @Volatile
    private var activePairingCode: String = generateCode()

    fun currentCode(): String = activePairingCode

    fun rotatePairingCode(): String {
        activePairingCode = generateCode()
        onPairingCodeRotated(activePairingCode)
        return activePairingCode
    }

    override fun serve(session: IHTTPSession): Response {
        val uri = session.uri
        val method = session.method

        return when {
            uri == "/health" && method == Method.GET -> jsonResponse(HealthResponse())
            uri == "/pair" && method == Method.POST -> handlePair(session)
            uri == "/sdp" && method == Method.POST -> handleSdpPost(session)
            uri.startsWith("/sdp") && method == Method.GET -> handleSdpGet(uri)
            uri == "/ice" && method == Method.POST -> handleIcePost(session)
            uri.startsWith("/ice") && method == Method.GET -> handleIceGet(uri)
            uri.startsWith("/status") && method == Method.GET -> handleStatus(uri)
            else -> newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Not found")
        }
    }

    private fun handlePair(session: IHTTPSession): Response {
        val body = readBody(session)
        val request = moshi.adapter(PairRequest::class.java).fromJson(body)
            ?: return errorResponse("Invalid JSON")

        if (request.code != activePairingCode) {
            return newFixedLengthResponse(Response.Status.UNAUTHORIZED, MIME_PLAINTEXT, "Invalid code")
        }

        val sessionId = UUID.randomUUID().toString()
        val pairingSession = Session(
            id = sessionId,
            code = request.code,
            expiresAtMs = System.currentTimeMillis() + PAIRING_TTL_MS
        )
        sessions[sessionId] = pairingSession
        onSessionPaired(sessionId)
        rotatePairingCode()

        return jsonResponse(PairResponse(sessionId = sessionId))
    }

    private fun handleSdpPost(session: IHTTPSession): Response {
        val body = readBody(session)
        val message = moshi.adapter(SdpMessage::class.java).fromJson(body)
            ?: return errorResponse("Invalid JSON")

        val castSession = sessions[message.sessionId]
            ?: return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Unknown session")

        if (message.type == "offer") {
            castSession.remoteOffer = message
            castSession.state = "connecting"
            webRtcSessionManager.handleRemoteOffer(message.sessionId, message.sdp)
        }

        return jsonResponse(OkResponse())
    }

    private fun handleSdpGet(uri: String): Response {
        val sessionId = queryParam(uri, "sessionId")
            ?: return errorResponse("Missing sessionId")

        if (!sessions.containsKey(sessionId)) {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Unknown session")
        }

        val answer = webRtcSessionManager.getLocalAnswer(sessionId)
            ?: return newFixedLengthResponse(Response.Status.NO_CONTENT, MIME_PLAINTEXT, "")

        return jsonResponse(SdpMessage(sessionId = sessionId, type = "answer", sdp = answer))
    }

    private fun handleIcePost(session: IHTTPSession): Response {
        val body = readBody(session)
        val message = moshi.adapter(IceMessage::class.java).fromJson(body)
            ?: return errorResponse("Invalid JSON")

        webRtcSessionManager.addRemoteIceCandidate(
            message.sessionId,
            message.candidate,
            message.sdpMid,
            message.sdpMLineIndex
        )
        return jsonResponse(OkResponse())
    }

    private fun handleIceGet(uri: String): Response {
        val sessionId = queryParam(uri, "sessionId").orEmpty()
        val candidates = webRtcSessionManager.drainLocalIceCandidates(sessionId)
        return jsonResponse(IceListResponse(candidates = candidates))
    }

    private fun handleStatus(uri: String): Response {
        val sessionId = queryParam(uri, "sessionId") ?: ""
        val rtcState = if (sessionId.isNotEmpty()) webRtcSessionManager.connectionState(sessionId) else null
        val state = rtcState ?: sessions[sessionId]?.state ?: "waiting"
        if (rtcState == "connected") {
            sessions[sessionId]?.state = "connected"
        }
        return jsonResponse(StatusResponse(state = state))
    }

    private fun queryParam(uri: String, key: String): String? {
        val query = uri.substringAfter('?', "")
        if (query.isEmpty() || query == uri) return null
        return query.split('&')
            .mapNotNull {
                val parts = it.split('=', limit = 2)
                if (parts.size == 2 && parts[0] == key) parts[1] else null
            }
            .firstOrNull()
    }

    private fun readBody(session: IHTTPSession): String {
        val files = HashMap<String, String>()
        session.parseBody(files)
        return files["postData"] ?: ""
    }

    private inline fun <reified T> jsonResponse(value: T): Response {
        val json = moshi.adapter(T::class.java).toJson(value)
        return newFixedLengthResponse(Response.Status.OK, "application/json", json)
    }

    private fun errorResponse(message: String): Response =
        newFixedLengthResponse(Response.Status.BAD_REQUEST, MIME_PLAINTEXT, message)

    companion object {
        private const val PAIRING_TTL_MS = 5 * 60 * 1000L

        fun generateCode(): String = (100_000..999_999).random().toString()
    }
}
