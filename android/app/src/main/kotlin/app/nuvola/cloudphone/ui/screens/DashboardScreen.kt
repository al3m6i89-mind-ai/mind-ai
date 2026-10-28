package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.SupportAgent
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.AppError
import app.nuvola.cloudphone.data.Dashboard
import app.nuvola.cloudphone.data.Device
import app.nuvola.cloudphone.data.call
import app.nuvola.cloudphone.ui.components.ErrorState
import app.nuvola.cloudphone.ui.components.InlineError
import app.nuvola.cloudphone.ui.components.LoadingBox
import app.nuvola.cloudphone.ui.components.Pill
import app.nuvola.cloudphone.ui.components.SectionCard
import app.nuvola.cloudphone.ui.components.SimulatedBanner
import app.nuvola.cloudphone.ui.components.StatusPill
import app.nuvola.cloudphone.ui.components.canOpen
import app.nuvola.cloudphone.ui.components.canRestart
import app.nuvola.cloudphone.ui.components.canStart
import app.nuvola.cloudphone.ui.components.canStop
import app.nuvola.cloudphone.ui.components.formatDate
import app.nuvola.cloudphone.ui.components.formatRam
import app.nuvola.cloudphone.ui.components.jobLabel
import app.nuvola.cloudphone.ui.components.statusDetail
import app.nuvola.cloudphone.ui.theme.LocalStatusColors
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class DashboardVm(app: Application) : BaseVm(app) {
    val state = MutableStateFlow<Load<Dashboard>>(Load.Loading)
    val actionError = MutableStateFlow<AppError?>(null)
    val refreshing = MutableStateFlow(false)
    private var poller: Job? = null

    fun refresh(silent: Boolean = true) = load(state, silent) { api.dashboard() }

    fun pullRefresh() {
        refreshing.value = true
        viewModelScope.launch {
            (call { api.dashboard() } as? ApiResult.Ok)?.let { state.value = Load.Ready(it.value) }
            refreshing.value = false
        }
    }

    /** While any phone has an action in progress, re-read the server every few seconds. */
    fun startPolling() {
        poller?.cancel()
        poller = viewModelScope.launch {
            while (isActive) {
                delay(3_000)
                val d = (state.value as? Load.Ready)?.value ?: continue
                if (d.devices.any { it.pendingAction != null }) refresh()
            }
        }
    }

    fun stopPolling() { poller?.cancel() }

    fun act(device: Device, action: String) {
        actionError.value = null
        viewModelScope.launch {
            val r = call {
                when (action) {
                    "start" -> api.startDevice(device.id)
                    "stop" -> api.stopDevice(device.id)
                    else -> api.restartDevice(device.id)
                }
            }
            if (r is ApiResult.Failed) actionError.value = r.error
            refresh()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    onOpenDevice: (String) -> Unit,
    onLive: (String) -> Unit,
    onCreate: () -> Unit,
    onPlans: () -> Unit,
    onSubscriptions: () -> Unit,
    onInvoices: () -> Unit,
    onSupport: () -> Unit,
    onSettings: () -> Unit,
    onVerifyEmail: (String) -> Unit,
    vm: DashboardVm = viewModel(),
) {
    val state by vm.state.collectAsState()
    val actionError by vm.actionError.collectAsState()
    val refreshing by vm.refreshing.collectAsState()

    LifecycleResumeEffect(Unit) {
        vm.refresh(silent = true)
        vm.startPolling()
        onPauseOrDispose { vm.stopPolling() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Cloud, null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.app_name))
                    }
                },
                actions = {
                    IconButton(onClick = onSupport) { Icon(Icons.Outlined.SupportAgent, stringResource(R.string.support)) }
                    val name = (state as? Load.Ready)?.value?.displayName.orEmpty()
                    Box(
                        Modifier.padding(end = 12.dp, start = 4.dp).size(34.dp)
                            .background(MaterialTheme.colorScheme.primaryContainer, CircleShape)
                            .clickable(onClick = onSettings),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (name.isNotBlank()) Text(name.trim().take(1).uppercase(), color = MaterialTheme.colorScheme.onPrimaryContainer)
                        else Icon(Icons.Outlined.Settings, stringResource(R.string.settings), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                    }
                },
            )
        },
    ) { padding ->
        when (val s = state) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(s.error, { vm.refresh(silent = false) }, Modifier.padding(padding))
            is Load.Ready -> PullToRefreshBox(isRefreshing = refreshing, onRefresh = vm::pullRefresh, modifier = Modifier.padding(padding)) {
                DashboardContent(s.value, actionError, onOpenDevice, onLive, onCreate, onPlans, onSubscriptions, onInvoices, onVerifyEmail, vm::act)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DashboardContent(
    d: Dashboard,
    actionError: AppError?,
    onOpenDevice: (String) -> Unit,
    onLive: (String) -> Unit,
    onCreate: () -> Unit,
    onPlans: () -> Unit,
    onSubscriptions: () -> Unit,
    onInvoices: () -> Unit,
    onVerifyEmail: (String) -> Unit,
    onAct: (Device, String) -> Unit,
) {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column {
                Text(d.displayName, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(d.email, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (!d.emailVerified) item {
            SectionCard {
                Text(stringResource(R.string.verify_banner))
                TextButton(onClick = { onVerifyEmail(d.email) }) { Text(stringResource(R.string.verify)) }
            }
        }
        if (d.devicesSimulated) item { SimulatedBanner() }
        item { Summary(d) }
        item {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onCreate) {
                    Icon(Icons.Outlined.Add, null); Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.action_create_phone))
                }
                AssistChip(onClick = onPlans, label = { Text(stringResource(R.string.action_plans)) },
                    leadingIcon = { Icon(Icons.Outlined.Inventory2, null) })
                AssistChip(onClick = onSubscriptions, label = { Text(stringResource(R.string.action_subscriptions)) },
                    leadingIcon = { Icon(Icons.Outlined.CreditCard, null) })
                AssistChip(onClick = onInvoices, label = { Text(stringResource(R.string.action_invoices)) },
                    leadingIcon = { Icon(Icons.Outlined.ReceiptLong, null) })
            }
        }
        if (actionError != null) item { InlineError(actionError) }
        if (d.devices.isEmpty()) {
            item { EmptyPhones(onCreate) }
        } else {
            item { Text(stringResource(R.string.dashboard_title), style = MaterialTheme.typography.titleMedium) }
            items(d.devices, key = { it.id }) { device ->
                DeviceCard(device, onClick = { onOpenDevice(device.id) }, onLive = { onLive(device.id) }, onAct = { onAct(device, it) })
            }
        }
    }
}

@Composable
private fun Summary(d: Dashboard) {
    SectionCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Stat(stringResource(R.string.summary_running), d.runningDevices.toString())
            Stat(stringResource(R.string.summary_stopped), d.stoppedDevices.toString())
            Stat(stringResource(R.string.summary_allowed), d.deviceAllowance.toString())
            Stat(stringResource(R.string.summary_next_expiry), formatDate(d.nearestExpiry) ?: stringResource(R.string.summary_none))
        }
    }
}

@Composable
private fun Stat(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleMedium)
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

@Composable
private fun EmptyPhones(onCreate: () -> Unit) {
    SectionCard {
        Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Outlined.PhoneAndroid, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.empty_title), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.empty_body), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onCreate) { Text(stringResource(R.string.empty_cta)) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DeviceCard(device: Device, onClick: () -> Unit, onLive: () -> Unit, onAct: (String) -> Unit) {
    val s = LocalStatusColors.current
    SectionCard(Modifier.clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.PhoneAndroid, null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(device.displayName, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    stringResource(R.string.android_version, device.androidVersion) + " · " + device.regionName,
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            StatusPill(device.status)
        }
        Text(
            stringResource(R.string.spec_line, device.cpuCores, formatRam(device.ramMb), device.storageGb),
            style = MaterialTheme.typography.bodyMedium,
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (device.simulated) Pill(stringResource(R.string.simulated_badge), s.warn, s.warnBg)
            if (device.rootEnabled) Pill(stringResource(R.string.root_on), s.idle, s.idleBg)
            Text(
                if (device.subscriptionActive) stringResource(R.string.expires_on, formatDate(device.subscriptionExpiresAt) ?: "—")
                else stringResource(R.string.subscription_ended),
                style = MaterialTheme.typography.labelMedium,
                color = if (device.subscriptionActive) MaterialTheme.colorScheme.onSurfaceVariant else s.bad,
            )
        }
        device.pendingAction?.let {
            Text(stringResource(R.string.action_in_progress, jobLabel(it)), color = s.warn, style = MaterialTheme.typography.bodyMedium)
        }
        statusDetail(device.statusDetail)?.let { Text(it, color = s.bad, style = MaterialTheme.typography.bodyMedium) }
        Spacer(Modifier.height(2.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FilledTonalButton(onClick = onLive, enabled = device.canOpen) { Text(stringResource(R.string.open_phone)) }
            if (device.status == "RUNNING" || device.status == "STOPPING") {
                OutlinedButton(onClick = { onAct("stop") }, enabled = device.canStop) {
                    Icon(Icons.Outlined.Stop, null); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.stop))
                }
            } else {
                OutlinedButton(onClick = { onAct("start") }, enabled = device.canStart) {
                    Icon(Icons.Outlined.PlayArrow, null); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.start))
                }
            }
            OutlinedButton(onClick = { onAct("restart") }, enabled = device.canRestart) {
                Icon(Icons.Outlined.RestartAlt, null); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.restart))
            }
            TextButton(onClick = onClick) { Text(stringResource(R.string.settings)) }
        }
    }
}
