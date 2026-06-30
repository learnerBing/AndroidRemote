package com.androidremote.tv.domain.model

/**
 * What the user is casting. V1 implements [SCREEN] only.
 */
enum class CastMode(val wireValue: String) {
    SCREEN("screen"),
    PHOTO("photo"),
    VIDEO("video"),
    IPTV("iptv"),
    YOUTUBE("youtube"),
    REMOTE("remote");

    val isV1: Boolean get() = this == SCREEN
}

data class MediaItem(
    val id: String,
    val title: String,
    val sourceUrl: String,
    val mimeType: String,
    val thumbnailUrl: String? = null
)

data class IptvChannel(
    val id: String,
    val name: String,
    val group: String,
    val streamUrl: String,
    val logoUrl: String? = null
)

data class IptvPlaylist(
    val name: String,
    val channels: List<IptvChannel>,
    val epgUrl: String? = null
)

data class YoutubeCastRequest(
    val videoId: String,
    val url: String
)

enum class RemoteKey(val wireValue: String) {
    DPAD_UP("DPAD_UP"),
    DPAD_DOWN("DPAD_DOWN"),
    DPAD_LEFT("DPAD_LEFT"),
    DPAD_RIGHT("DPAD_RIGHT"),
    ENTER("ENTER"),
    BACK("BACK"),
    HOME("HOME"),
    PLAY("PLAY"),
    PAUSE("PAUSE"),
    PLAY_PAUSE("PLAY_PAUSE"),
    VOLUME_UP("VOLUME_UP"),
    VOLUME_DOWN("VOLUME_DOWN")
}

data class RemoteCommand(
    val sessionId: String,
    val key: RemoteKey,
    val timestampEpochMs: Long = System.currentTimeMillis()
)
