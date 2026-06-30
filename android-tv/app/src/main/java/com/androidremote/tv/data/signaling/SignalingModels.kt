package com.androidremote.tv.data.signaling

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PairRequest(
    @Json(name = "code") val code: String
)

@JsonClass(generateAdapter = true)
data class PairResponse(
    @Json(name = "sessionId") val sessionId: String
)

@JsonClass(generateAdapter = true)
data class SdpMessage(
    @Json(name = "sessionId") val sessionId: String,
    @Json(name = "type") val type: String,
    @Json(name = "sdp") val sdp: String
)

@JsonClass(generateAdapter = true)
data class IceMessage(
    @Json(name = "sessionId") val sessionId: String,
    @Json(name = "candidate") val candidate: String,
    @Json(name = "sdpMid") val sdpMid: String?,
    @Json(name = "sdpMLineIndex") val sdpMLineIndex: Int
)

@JsonClass(generateAdapter = true)
data class IceCandidateDto(
    @Json(name = "candidate") val candidate: String,
    @Json(name = "sdpMid") val sdpMid: String?,
    @Json(name = "sdpMLineIndex") val sdpMLineIndex: Int
)

@JsonClass(generateAdapter = true)
data class IceListResponse(
    @Json(name = "candidates") val candidates: List<IceCandidateDto>
)

@JsonClass(generateAdapter = true)
data class StatusResponse(
    @Json(name = "state") val state: String
)

@JsonClass(generateAdapter = true)
data class OkResponse(
    @Json(name = "ok") val ok: Boolean = true
)

@JsonClass(generateAdapter = true)
data class HealthResponse(
    @Json(name = "ok") val ok: Boolean = true
)
