package com.androidremote.tv.domain.model

data class CastDevice(
    val id: String,
    val name: String,
    val host: String,
    val port: Int
)

data class PairingSession(
    val sessionId: String,
    val pairingCode: String,
    val expiresAtEpochMs: Long
)

enum class StreamCodec {
    H264
}

data class StreamConfig(
    val width: Int = 1280,
    val height: Int = 720,
    val fps: Int = 30,
    val maxBitrateKbps: Int = 2500,
    val codec: StreamCodec = StreamCodec.H264
)

enum class ConnectionState {
    Idle,
    Advertising,
    WaitingForPair,
    Pairing,
    Connecting,
    Streaming,
    Disconnected,
    Error
}
