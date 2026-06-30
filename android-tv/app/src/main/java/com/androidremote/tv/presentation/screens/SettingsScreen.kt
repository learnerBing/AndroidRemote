package com.androidremote.tv.presentation.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.androidremote.tv.domain.model.TvSettings
import com.androidremote.tv.presentation.theme.TvColors

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SettingsScreen(
    settings: TvSettings,
    appVersion: String,
    onBack: () -> Unit,
    onCycleDeviceName: () -> Unit,
    onCycleVideoQuality: () -> Unit,
    onToggleDiagnostics: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 72.dp, vertical = 48.dp)
    ) {
        Text(
            text = "Settings",
            style = MaterialTheme.typography.displayMedium,
            color = TvColors.TextPrimary
        )

        Spacer(modifier = Modifier.height(40.dp))

        SettingsRow(
            title = "Device name",
            value = settings.deviceName,
            onClick = onCycleDeviceName
        )

        Spacer(modifier = Modifier.height(16.dp))

        SettingsRow(
            title = "Video quality",
            value = settings.videoQuality.label,
            onClick = onCycleVideoQuality
        )

        Spacer(modifier = Modifier.height(16.dp))

        SettingsRow(
            title = "Show diagnostics overlay",
            value = if (settings.showDiagnostics) "On" else "Off",
            onClick = onToggleDiagnostics
        )

        Spacer(modifier = Modifier.height(16.dp))

        SettingsRow(
            title = "About",
            value = "v$appVersion",
            onClick = {},
            enabled = false
        )

        Spacer(modifier = Modifier.weight(1f))

        SettingsRow(
            title = "Back",
            value = "",
            onClick = onBack
        )
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SettingsEntryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    SettingsRow(
        title = "Settings",
        value = "",
        onClick = onClick,
        modifier = modifier.fillMaxWidth(0.35f)
    )
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun SettingsRow(
    title: String,
    value: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    var focused by remember { mutableStateOf(false) }

    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused },
        shape = RoundedCornerShape(TvColors.CornerRadiusTv),
        colors = androidx.tv.material3.SurfaceDefaults.colors(
            containerColor = TvColors.Surface,
            contentColor = TvColors.TextPrimary
        ),
        border = if (focused) {
            BorderStroke(2.dp, TvColors.Primary)
        } else {
            null
        }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 20.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = TvColors.TextPrimary
            )
            if (value.isNotEmpty()) {
                Text(
                    text = value,
                    style = MaterialTheme.typography.bodyLarge,
                    color = TvColors.Primary
                )
            }
        }
    }
}
