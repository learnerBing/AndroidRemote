package com.androidremote.tv.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.androidremote.tv.di.AppContainer
import com.androidremote.tv.domain.model.ConnectionState
import com.androidremote.tv.domain.model.PairingSession
import com.androidremote.tv.domain.model.TvSettings
import com.androidremote.tv.domain.usecase.ObservePairingUseCase
import com.androidremote.tv.domain.usecase.ObserveReceiverStateUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class ReceiverRoute {
    Home,
    Settings
}

class ReceiverViewModel(
  private val container: AppContainer,
  observeState: ObserveReceiverStateUseCase,
  observePairing: ObservePairingUseCase
) : ViewModel() {

    val connectionState: StateFlow<ConnectionState> = observeState()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ConnectionState.Idle)

    val pairing: StateFlow<PairingSession?> = observePairing()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val settings: StateFlow<TvSettings> = container.settingsRepository.settings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), TvSettings())

    private val _route = MutableStateFlow(ReceiverRoute.Home)
    val route: StateFlow<ReceiverRoute> = _route.asStateFlow()

    fun openSettings() {
        if (connectionState.value != ConnectionState.Streaming) {
            _route.value = ReceiverRoute.Settings
        }
    }

    fun closeSettings() {
        _route.value = ReceiverRoute.Home
    }

    fun cycleDeviceName() {
        container.settingsRepository.cycleDeviceName()
        viewModelScope.launch {
            container.updateDeviceName(container.settingsRepository.current().deviceName)
        }
    }

    fun cycleVideoQuality() {
        container.settingsRepository.cycleVideoQuality()
    }

    fun toggleDiagnostics() {
        container.settingsRepository.toggleDiagnostics()
    }
}
