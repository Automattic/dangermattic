package com.dayoneapp.dayone.domain.drive

sealed class LoadKeyUiState(
    val buttonEnabled: Boolean,
) {
    object Init : LoadKeyUiState(buttonEnabled = true)

    object Loading : LoadKeyUiState(buttonEnabled = false)

    object KeyLoaded : LoadKeyUiState(buttonEnabled = false)

    object KeyNotFound : LoadKeyUiState(buttonEnabled = true)
}
