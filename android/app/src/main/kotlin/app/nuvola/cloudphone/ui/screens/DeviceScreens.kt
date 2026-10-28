package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.LinkOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.AppError
import app.nuvola.cloudphone.data.Device
import app.nuvola.cloudphone.data.RenameRequest
import app.nuvola.cloudphone.data.RootRequest
import app.nuvola.cloudphone.data.StreamSession
import app.nuvola.cloudphone.data.call
import app.nuvola.cloudphone.ui.components.BackTopBar
import app.nuvola.cloudphone.ui.components.ErrorState
import app.nuvola.cloudphone.ui.components.InlineError
import app.nuvola.cloudphone.ui.components.LabelValue
import app.nuvola.cloudphone.ui.components.LoadingBox
import app.nuvola.cloudphone.ui.components.SectionCard
import app.nuvola.cloudphone.ui.components.SimulatedBanner
import app.nuvola.cloudphone.ui.components.StatusPill
import app.nuvola.cloudphone.ui.components.canDelete
import app.nuvola.cloudphone.ui.components.canOpen
import app.nuvola.cloudphone.ui.components.canRestart
import app.nuvola.cloudphone.ui.components.canStart
import app.nuvola.cloudphone.ui.components.canStop
import app.nuvola.cloudphone.ui.components.code
import app.nuvola.cloudphone.ui.components.deviceTypeLabel
import app.nuvola.cloudphone.ui.components.errorText
import app.nuvola.cloudphone.ui.components.formatDate
import app.nuvola.cloudphone.ui.components.formatDateTime
import app.nuvola.cloudphone.ui.components.formatRam
import app.nuvola.cloudphone.ui.components.jobLabel
import app.nuvola.cloudphone.ui.components.statusDetail
import app.nuvola.cloudphone.ui.theme.LocalStatusColors
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class DeviceVm(app: Application, handle: SavedStateHandle) : BaseVm(app) {
    val id: String = checkNotNull(handle["deviceId"])
    val state = MutableStateFlow<Load<Device>>(Load.Loading)
    val action = MutableStateFlow(ActionState())
    private var poller: Job? = null

    fun refresh(silent: Boolean = true) = load(state, silent) { api.device(id) }

    fun startPolling() {
        poller?.cancel()
        poller = viewModelScope.launch {
            while (isActive) {
                delay(3_000)
                if ((state.value as? Load.Ready)?.value?.pendingAction != null) refresh()
            }
        }
    }

    fun stopPolling() { poller?.cancel() }

    fun start() = act { api.startDevice(id) }
    fun stop() = act { api.stopDevice(id) }
    fun restart() = act { api.restartDevice(id) }
    fun rename(name: String) = act { api.renameDevice(id, RenameRequest(name.trim())) }
    fun setRoot(enabled: Boolean) = act { api.setRoot(id, RootRequest(enabled)) }
    fun delete(onDeleted: () -> Unit) = act { api.deleteDevice(id).also { onDeleted() } }

    private fun act(block: suspend () -> Device) {
        if (action.value.running) return
        action.value = ActionState(running = true)
        viewModelScope.launch {
            when (val r = call(block)) {
                is ApiResult.Ok -> { state.value = Load.Ready(r.value); action.value = ActionState() }
                is ApiResult.Failed -> { action.value = ActionState(error = r.error); refresh() }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DeviceDetailScreen(onBack: () -> Unit, onLive: (String) -> Unit, onExtend: () -> Unit, vm: DeviceVm = viewModel()) {
    val state by vm.state.collectAsState()
    val action by vm.action.collectAsState()
    var renaming by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    var confirmRoot by rememberSaveable { mutableStateOf(false) }

    LifecycleResumeEffect(Unit) {
        vm.refresh()
        vm.startPolling()
        onPauseOrDispose { vm.stopPolling() }
    }

    Scaffold(topBar = { BackTopBar(stringResource(R.string.device_details), onBack) }) { padding ->
        when (val s = state) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(s.error, { vm.refresh(false) }, Modifier.padding(padding))
            is Load.Ready -> {
                val d = s.value
                val colors = LocalStatusColors.current
                Column(
                    Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(d.displayName, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                        StatusPill(d.status)
                    }
                    if (d.simulated) SimulatedBanner()
                    d.pendingAction?.let {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.action_in_progress, jobLabel(it)), color = colors.warn)
                        }
                    }
                    statusDetail(d.statusDetail)?.let { Text(it, color = colors.bad) }
                    InlineError(action.error)

                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onLive(d.id) }, enabled = d.canOpen) { Text(stringResource(R.string.open_phone)) }
                        OutlinedButton(onClick = vm::start, enabled = d.canStart && !action.running) { Text(stringResource(R.string.start)) }
                        OutlinedButton(onClick = vm::stop, enabled = d.canStop && !action.running) { Text(stringResource(R.string.stop)) }
                        OutlinedButton(onClick = vm::restart, enabled = d.canRestart && !action.running) { Text(stringResource(R.string.restart)) }
                        OutlinedButton(onClick = { renaming = true }) { Text(stringResource(R.string.rename)) }
                        OutlinedButton(onClick = onExtend) { Text(stringResource(R.string.extend)) }
                    }

                    SectionCard {
                        Text(stringResource(R.string.section_system), style = MaterialTheme.typography.titleMedium)
                        LabelValue(stringResource(R.string.field_type), deviceTypeLabel(d.deviceType))
                        LabelValue(stringResource(R.string.field_android), stringResource(R.string.android_version, d.androidVersion))
                        LabelValue(stringResource(R.string.field_region), d.regionName)
                        LabelValue(stringResource(R.string.field_last_seen), formatDateTime(d.lastSeenAt) ?: "—")
                        if (d.preinstalledApps.isNotEmpty()) {
                            LabelValue(stringResource(R.string.field_preinstalled), d.preinstalledApps.joinToString("، "))
                        }
                        HorizontalDivider()
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.root_access), style = MaterialTheme.typography.titleMedium)
                                Text(stringResource(R.string.root_desc), style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Switch(
                                checked = d.rootEnabled,
                                enabled = d.pendingAction == null && d.status in setOf("RUNNING", "STOPPED") && !action.running,
                                onCheckedChange = { on -> if (on) confirmRoot = true else vm.setRoot(false) },
                            )
                        }
                    }

                    SectionCard {
                        Text(stringResource(R.string.section_specs), style = MaterialTheme.typography.titleMedium)
                        LabelValue(stringResource(R.string.field_cpu), stringResource(R.string.field_cpu_value, d.cpuCores))
                        LabelValue(stringResource(R.string.field_ram), formatRam(d.ramMb))
                        LabelValue(stringResource(R.string.field_storage), stringResource(R.string.gb, d.storageGb.toString()))
                        LabelValue(stringResource(R.string.field_screen), stringResource(R.string.field_screen_value, d.screenWidth, d.screenHeight, d.screenDpi))
                    }

                    SectionCard {
                        Text(stringResource(R.string.section_subscription), style = MaterialTheme.typography.titleMedium)
                        LabelValue(stringResource(R.string.field_plan), d.planName)
                        LabelValue(stringResource(R.string.field_expires),
                            if (d.subscriptionActive) formatDate(d.subscriptionExpiresAt) ?: "—" else stringResource(R.string.subscription_ended))
                        LabelValue(stringResource(R.string.field_always_on), stringResource(if (d.alwaysOn) R.string.yes else R.string.no))
                    }

                    Text(stringResource(R.string.storage_note), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)

                    TextButton(
                        onClick = { confirmDelete = true },
                        enabled = d.canDelete && !action.running,
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) { Text(stringResource(R.string.delete)) }
                }

                if (renaming) RenameDialog(d.displayName, onDismiss = { renaming = false }) { vm.rename(it); renaming = false }
                if (confirmDelete) AlertDialog(
                    onDismissRequest = { confirmDelete = false },
                    title = { Text(stringResource(R.string.delete_title)) },
                    text = { Text(stringResource(R.string.delete_body)) },
                    confirmButton = {
                        TextButton(onClick = { confirmDelete = false; vm.delete(onBack) },
                            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
                            Text(stringResource(R.string.delete))
                        }
                    },
                    dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } },
                )
                if (confirmRoot) RootWarningDialog(onDismiss = { confirmRoot = false }) { confirmRoot = false; vm.setRoot(true) }
            }
        }
    }
}

@Composable
fun RootWarningDialog(onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.root_warning_title)) },
        text = { Text(stringResource(R.string.root_warning_body)) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(stringResource(R.string.turn_on)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun RenameDialog(current: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var name by rememberSaveable { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.rename_title)) },
        text = {
            OutlinedTextField(name, { name = it.take(60) }, singleLine = true, label = { Text(stringResource(R.string.phone_name)) })
        },
        confirmButton = { TextButton(onClick = { onSave(name) }, enabled = name.isNotBlank()) { Text(stringResource(R.string.save)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

// ---------------- Live screen ----------------

sealed interface LiveState {
    data object Connecting : LiveState
    data class Ready(val session: StreamSession) : LiveState
    data class Failed(val error: AppError) : LiveState
}

/**
 * Asks the server for a short-lived stream session. The video and touch client is built in phase 4;
 * until then this screen reports exactly what the server answered and shows no fake screen.
 */
class LiveVm(app: Application, handle: SavedStateHandle) : BaseVm(app) {
    private val deviceId: String = checkNotNull(handle["deviceId"])
    val state = MutableStateFlow<LiveState>(LiveState.Connecting)

    init { connect() }

    fun connect() {
        state.value = LiveState.Connecting
        viewModelScope.launch {
            state.value = when (val r = call { api.openSession(deviceId) }) {
                is ApiResult.Ok -> LiveState.Ready(r.value)
                is ApiResult.Failed -> LiveState.Failed(r.error)
            }
        }
    }

    fun close() {
        val s = (state.value as? LiveState.Ready)?.session ?: return
        // Fire and forget on the app scope so the server ends the session even as this screen closes.
        nuvola.appScope.launch { call { api.closeSession(s.sessionId) } }
    }

    override fun onCleared() { close() }
}

@Composable
fun LiveScreen(onBack: () -> Unit, vm: LiveVm = viewModel()) {
    val state by vm.state.collectAsState()
    Scaffold(topBar = { BackTopBar(stringResource(R.string.open_phone), onBack) }) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when (val s = state) {
                LiveState.Connecting -> {
                    CircularProgressIndicator()
                    Spacer(Modifier.size(12.dp))
                    Text(stringResource(R.string.live_connecting), textAlign = TextAlign.Center)
                }
                is LiveState.Ready -> {
                    Text(stringResource(R.string.live_session_ready), textAlign = TextAlign.Center)
                    Spacer(Modifier.size(12.dp))
                    FilledTonalButton(onClick = onBack) { Text(stringResource(R.string.close)) }
                }
                is LiveState.Failed -> {
                    Icon(Icons.Outlined.LinkOff, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.size(12.dp))
                    if (s.error.code == "STREAMING_NOT_AVAILABLE") {
                        Text(stringResource(R.string.live_unavailable_title), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.live_unavailable_body), textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        Text(errorText(s.error), textAlign = TextAlign.Center)
                    }
                    Spacer(Modifier.size(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = onBack) { Text(stringResource(R.string.back)) }
                        Button(onClick = vm::connect) { Text(stringResource(R.string.retry)) }
                    }
                }
            }
        }
    }
}
