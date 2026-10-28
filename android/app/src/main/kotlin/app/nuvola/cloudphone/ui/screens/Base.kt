package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.nuvola.cloudphone.NuvolaApp
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.AppError
import app.nuvola.cloudphone.data.call
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Data that is loading, loaded, or failed. */
sealed interface Load<out T> {
    data object Loading : Load<Nothing>
    data class Ready<T>(val value: T) : Load<T>
    data class Failed(val error: AppError) : Load<Nothing>
}

abstract class BaseVm(app: Application) : AndroidViewModel(app) {
    protected val nuvola = app as NuvolaApp
    protected val api get() = nuvola.client.api

    /** Loads into a state flow and keeps the previous value on screen while refreshing. */
    protected fun <T> load(target: MutableStateFlow<Load<T>>, silent: Boolean = false, block: suspend () -> T) {
        if (!silent || target.value !is Load.Ready) target.value = Load.Loading
        viewModelScope.launch {
            when (val r = call(block)) {
                is ApiResult.Ok -> target.value = Load.Ready(r.value)
                is ApiResult.Failed -> if (!silent || target.value !is Load.Ready) target.value = Load.Failed(r.error)
            }
        }
    }
}

/** State for a one-shot action button: idle, running, or failed with an error to show. */
data class ActionState(val running: Boolean = false, val error: AppError? = null, val done: Boolean = false)

fun MutableStateFlow<ActionState>.asState(): StateFlow<ActionState> = this
