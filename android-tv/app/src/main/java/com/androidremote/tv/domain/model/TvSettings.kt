package com.androidremote.tv.domain.model

data class TvSettings(
    val deviceName: String = DEFAULT_DEVICE_NAME,
    val videoQuality: VideoQuality = VideoQuality.HD_720P,
    val showDiagnostics: Boolean = false
) {
    val streamConfig: StreamConfig
        get() = when (videoQuality) {
            VideoQuality.HD_720P -> StreamConfig(width = 1280, height = 720)
            VideoQuality.FULL_HD_1080P -> StreamConfig(width = 1920, height = 1080)
        }

    companion object {
        const val DEFAULT_DEVICE_NAME = "Living Room TV"
    }
}

enum class VideoQuality(val label: String) {
    HD_720P("720p"),
    FULL_HD_1080P("1080p");

    fun next(): VideoQuality = when (this) {
        HD_720P -> FULL_HD_1080P
        FULL_HD_1080P -> HD_720P
    }

    companion object {
        fun fromLabel(label: String): VideoQuality =
            entries.firstOrNull { it.label == label } ?: HD_720P
    }
}
