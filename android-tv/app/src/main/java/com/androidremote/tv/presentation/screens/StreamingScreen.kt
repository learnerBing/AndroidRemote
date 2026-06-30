package com.androidremote.tv.presentation.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import android.view.ViewGroup
import android.widget.FrameLayout
import com.androidremote.tv.domain.model.TvSettings
import com.androidremote.tv.presentation.theme.TvColors
import org.webrtc.SurfaceViewRenderer

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun StreamingScreen(
    settings: TvSettings,
  connectionLabel: String,
    onRendererReady: (SurfaceViewRenderer) -> Unit,
    modifier: Modifier = Modifier
) {
    val rendererHolder = remember { mutableListOf<SurfaceViewRenderer>() }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TvColors.Black)
    ) {
        AndroidView(
            factory = { context ->
                SurfaceViewRenderer(context).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    rendererHolder.add(this)
                }
            },
            update = onRendererReady,
            modifier = Modifier.fillMaxSize()
        )

        DisposableEffect(Unit) {
            onDispose {
                rendererHolder.firstOrNull()?.release()
            }
        }

        LiveStatusOverlay(
            qualityLabel = settings.videoQuality.label,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(32.dp)
        )

        if (settings.showDiagnostics) {
            DiagnosticsOverlay(
                connectionLabel = connectionLabel,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(32.dp)
            )
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun LiveStatusOverlay(
    qualityLabel: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(TvColors.CornerRadiusTv))
            .background(TvColors.Surface.copy(alpha = 0.85f))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .clip(CircleShape)
                .background(TvColors.Success)
        )
        Text(
            text = "Live",
            style = MaterialTheme.typography.labelLarge,
            color = TvColors.Success
        )
        Text(
            text = qualityLabel.uppercase(),
            style = MaterialTheme.typography.labelLarge,
            color = TvColors.TextSecondary
        )
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun DiagnosticsOverlay(
    connectionLabel: String,
    modifier: Modifier = Modifier
) {
    ColumnOverlay(
        modifier = modifier
            .clip(RoundedCornerShape(TvColors.CornerRadiusTv))
            .background(TvColors.Surface.copy(alpha = 0.9f))
            .padding(16.dp),
        lines = listOf(
            "Diagnostics",
            connectionLabel,
            "Codec: H.264",
            "Transport: WebRTC LAN"
        )
    )
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun ColumnOverlay(
    modifier: Modifier,
    lines: List<String>
) {
    androidx.compose.foundation.layout.Column(modifier = modifier) {
        lines.forEachIndexed { index, line ->
            Text(
                text = line,
                style = if (index == 0) {
                    MaterialTheme.typography.labelLarge
                } else {
                    MaterialTheme.typography.bodyMedium
                },
                color = if (index == 0) TvColors.Primary else TvColors.TextSecondary
            )
        }
    }
}
