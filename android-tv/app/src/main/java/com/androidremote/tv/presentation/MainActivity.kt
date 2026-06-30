package com.androidremote.tv.presentation

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.androidremote.tv.AndroidRemoteApp
import com.androidremote.tv.BuildConfig
import com.androidremote.tv.data.service.CastReceiverService
import com.androidremote.tv.presentation.screens.ReceiverScreen
import com.androidremote.tv.presentation.theme.AndroidRemoteTheme

class MainActivity : ComponentActivity() {

    private lateinit var viewModel: ReceiverViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val container = AndroidRemoteApp.container(application)
        val deviceName = container.settingsRepository.current().deviceName

        val serviceIntent = Intent(this, CastReceiverService::class.java).apply {
            putExtra(CastReceiverService.EXTRA_DEVICE_NAME, deviceName)
        }
        startForegroundService(serviceIntent)

        viewModel = ReceiverViewModel(
            container = container,
            observeState = container.observeReceiverStateUseCase,
            observePairing = container.observePairingUseCase
        )

        setContent {
            AndroidRemoteTheme {
                ReceiverScreen(
                    viewModel = viewModel,
                    appVersion = BuildConfig.VERSION_NAME,
                    onRendererReady = { renderer ->
                        container.webRtcRepository.attachRenderer(renderer)
                    }
                )
            }
        }
    }
}
