package com.androidremote.tv.presentation.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.androidremote.tv.domain.model.ConnectionState
import com.androidremote.tv.presentation.ReceiverRoute
import com.androidremote.tv.presentation.ReceiverViewModel
import com.androidremote.tv.presentation.theme.TvColors
import org.webrtc.SurfaceViewRenderer

@Composable
fun ReceiverScreen(
    viewModel: ReceiverViewModel,
    appVersion: String,
    onRendererReady: (SurfaceViewRenderer) -> Unit,
    modifier: Modifier = Modifier
) {
    val connectionState by viewModel.connectionState.collectAsState()
    val pairing by viewModel.pairing.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val route by viewModel.route.collectAsState()

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TvColors.Background)
    ) {
        when (route) {
            ReceiverRoute.Settings -> SettingsScreen(
                settings = settings,
                appVersion = appVersion,
                onBack = viewModel::closeSettings,
                onCycleDeviceName = viewModel::cycleDeviceName,
                onCycleVideoQuality = viewModel::cycleVideoQuality,
                onToggleDiagnostics = viewModel::toggleDiagnostics
            )

            ReceiverRoute.Home -> when (connectionState) {
                ConnectionState.Streaming -> StreamingScreen(
                    settings = settings,
                    connectionLabel = connectionDiagnosticsLabel(connectionState),
                    onRendererReady = onRendererReady
                )

                else -> PairingScreen(
                    pairingCode = pairing?.pairingCode.orEmpty(),
                    connectionState = connectionState,
                    onOpenSettings = viewModel::openSettings
                )
            }
        }
    }
}

private fun connectionDiagnosticsLabel(state: ConnectionState): String =
    "State: ${state.name}"
