package com.androidremote.tv.data.settings

import android.content.Context
import com.androidremote.tv.domain.model.TvSettings
import com.androidremote.tv.domain.model.VideoQuality
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class TvSettingsRepository(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val _settings = MutableStateFlow(load())
    val settings: StateFlow<TvSettings> = _settings.asStateFlow()

    fun current(): TvSettings = _settings.value

    fun setDeviceName(name: String) {
        val trimmed = name.trim().ifEmpty { TvSettings.DEFAULT_DEVICE_NAME }
        prefs.edit().putString(KEY_DEVICE_NAME, trimmed).apply()
        _settings.value = _settings.value.copy(deviceName = trimmed)
    }

    fun cycleDeviceName() {
        val index = DEVICE_NAME_PRESETS.indexOf(_settings.value.deviceName)
        val next = DEVICE_NAME_PRESETS[(index + 1) % DEVICE_NAME_PRESETS.size]
        setDeviceName(next)
    }

    fun setVideoQuality(quality: VideoQuality) {
        prefs.edit().putString(KEY_VIDEO_QUALITY, quality.label).apply()
        _settings.value = _settings.value.copy(videoQuality = quality)
    }

    fun cycleVideoQuality() {
        setVideoQuality(_settings.value.videoQuality.next())
    }

    fun setShowDiagnostics(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_SHOW_DIAGNOSTICS, enabled).apply()
        _settings.value = _settings.value.copy(showDiagnostics = enabled)
    }

    fun toggleDiagnostics() {
        setShowDiagnostics(!_settings.value.showDiagnostics)
    }

    private fun load(): TvSettings = TvSettings(
        deviceName = prefs.getString(KEY_DEVICE_NAME, TvSettings.DEFAULT_DEVICE_NAME)
            ?: TvSettings.DEFAULT_DEVICE_NAME,
        videoQuality = VideoQuality.fromLabel(
            prefs.getString(KEY_VIDEO_QUALITY, VideoQuality.HD_720P.label) ?: VideoQuality.HD_720P.label
        ),
        showDiagnostics = prefs.getBoolean(KEY_SHOW_DIAGNOSTICS, false)
    )

    companion object {
        private const val PREFS_NAME = "androidremote_tv_settings"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_VIDEO_QUALITY = "video_quality"
        private const val KEY_SHOW_DIAGNOSTICS = "show_diagnostics"

        val DEVICE_NAME_PRESETS = listOf(
            "Living Room TV",
            "Bedroom TV",
            "Office TV",
            "AndroidRemote TV"
        )
    }
}
