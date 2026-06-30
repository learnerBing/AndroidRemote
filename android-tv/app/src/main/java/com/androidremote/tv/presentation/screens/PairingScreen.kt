package com.androidremote.tv.presentation.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.androidremote.tv.domain.model.ConnectionState
import com.androidremote.tv.presentation.theme.TvColors

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PairingScreen(
    pairingCode: String,
    connectionState: ConnectionState,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 80.dp, vertical = 56.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "AndroidRemote",
            style = MaterialTheme.typography.displayMedium,
            color = TvColors.TextPrimary
        )

        Spacer(modifier = Modifier.weight(0.35f))

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "Enter this code on your iPhone",
                style = MaterialTheme.typography.titleMedium,
                color = TvColors.TextSecondary,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(32.dp))

            Text(
                text = formatPairingCode(pairingCode),
                style = MaterialTheme.typography.displayLarge,
                color = TvColors.Primary,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(40.dp))

            Text(
                text = pairingStatusMessage(connectionState),
                style = MaterialTheme.typography.bodyLarge,
                color = TvColors.TextSecondary,
                textAlign = TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.weight(0.45f))

        SettingsEntryButton(onClick = onOpenSettings)
    }
}

private fun formatPairingCode(code: String): String {
    val digits = code.filter { it.isDigit() }.take(6)
    if (digits.isEmpty()) return "—— —— ——"
    return digits.padEnd(6, '·')
        .chunked(3)
        .joinToString(" ")
}

private fun pairingStatusMessage(state: ConnectionState): String = when (state) {
    ConnectionState.Idle -> "Starting receiver…"
    ConnectionState.Advertising -> "Discoverable on your network"
    ConnectionState.WaitingForPair -> "Waiting for iPhone to connect"
    ConnectionState.Pairing -> "Pairing…"
    ConnectionState.Connecting -> "Establishing secure connection…"
    ConnectionState.Streaming -> "Mirroring active"
    ConnectionState.Disconnected -> "Disconnected — ready for new session"
    ConnectionState.Error -> "Connection error — check network"
}
