package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.AndroidImage
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.AppError
import app.nuvola.cloudphone.data.Catalog
import app.nuvola.cloudphone.data.CreateDeviceRequest
import app.nuvola.cloudphone.data.Device
import app.nuvola.cloudphone.data.Plan
import app.nuvola.cloudphone.data.Subscription
import app.nuvola.cloudphone.data.call
import app.nuvola.cloudphone.ui.components.BackTopBar
import app.nuvola.cloudphone.ui.components.ErrorState
import app.nuvola.cloudphone.ui.components.InlineError
import app.nuvola.cloudphone.ui.components.LabelValue
import app.nuvola.cloudphone.ui.components.LoadingBox
import app.nuvola.cloudphone.ui.components.SectionCard
import app.nuvola.cloudphone.ui.components.SimulatedBanner
import app.nuvola.cloudphone.ui.components.deviceTypeLabel
import app.nuvola.cloudphone.ui.components.formatDate
import app.nuvola.cloudphone.ui.components.formatRam
import app.nuvola.cloudphone.ui.components.statusDetail
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

data class WizardData(val subscriptions: List<Subscription>, val plans: List<Plan>, val catalog: Catalog)

sealed interface CreateProgress {
    data object None : CreateProgress
    data object Sending : CreateProgress
    data class Waiting(val device: Device) : CreateProgress
    data class Ready(val device: Device) : CreateProgress
    data class Failed(val device: Device) : CreateProgress
    data class TimedOut(val device: Device) : CreateProgress
}

class CreateDeviceVm(app: Application, private val handle: SavedStateHandle) : BaseVm(app) {
    val data = MutableStateFlow<Load<WizardData>>(Load.Loading)
    val progress = MutableStateFlow<CreateProgress>(CreateProgress.None)
    val error = MutableStateFlow<AppError?>(null)

    /** One key for the whole wizard, kept across rotation, so repeated taps or retries create one phone. */
    private val idempotencyKey: String = handle["idem"] ?: UUID.randomUUID().toString().also { handle["idem"] = it }

    init { reload() }

    fun reload() = load(data) {
        kotlinx.coroutines.coroutineScope {
            val subs = async { api.subscriptions() }
            val plans = async { api.plans() }
            val catalog = async { api.catalog() }
            WizardData(subs.await(), plans.await(), catalog.await())
        }
    }

    fun create(req: CreateDeviceRequest) {
        if (progress.value !is CreateProgress.None) return
        error.value = null
        progress.value = CreateProgress.Sending
        viewModelScope.launch {
            when (val r = call { api.createDevice(idempotencyKey, req) }) {
                is ApiResult.Failed -> { error.value = r.error; progress.value = CreateProgress.None }
                is ApiResult.Ok -> watch(r.value)
            }
        }
    }

    /** The phone shows as ready only after the server reports it running. */
    private suspend fun watch(initial: Device) {
        var device = initial
        progress.value = CreateProgress.Waiting(device)
        val deadline = System.currentTimeMillis() + 5 * 60_000
        while (System.currentTimeMillis() < deadline) {
            when {
                device.status == "RUNNING" && device.pendingAction == null -> { progress.value = CreateProgress.Ready(device); return }
                device.status == "ERROR" -> { progress.value = CreateProgress.Failed(device); return }
            }
            delay(2_000)
            (call { api.device(device.id) } as? ApiResult.Ok)?.let { device = it.value; progress.value = CreateProgress.Waiting(device) }
        }
        progress.value = CreateProgress.TimedOut(device)
    }
}

private const val STEPS = 4

@Composable
fun CreateDeviceScreen(onBack: () -> Unit, onPlans: () -> Unit, onDone: () -> Unit, onViewDevice: (String) -> Unit, vm: CreateDeviceVm = viewModel()) {
    val data by vm.data.collectAsState()
    val progress by vm.progress.collectAsState()
    val error by vm.error.collectAsState()

    Scaffold(topBar = { BackTopBar(stringResource(R.string.create_title), onBack) }) { padding ->
        when (val d = data) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(d.error, vm::reload, Modifier.padding(padding))
            is Load.Ready -> if (progress is CreateProgress.None || progress is CreateProgress.Sending) {
                Wizard(d.value, progress is CreateProgress.Sending, error, onPlans, vm::create, Modifier.padding(padding))
            } else {
                Progress(progress, onDone, onViewDevice, Modifier.padding(padding))
            }
        }
    }
}

@Composable
private fun Wizard(
    data: WizardData,
    sending: Boolean,
    error: AppError?,
    onPlans: () -> Unit,
    onCreate: (CreateDeviceRequest) -> Unit,
    modifier: Modifier,
) {
    val plansById = data.plans.associateBy { it.id }
    val usable = data.subscriptions.filter { it.status == "ACTIVE" && it.devicesUsed < it.deviceLimit }
    val defaultName = stringResource(R.string.default_phone_name)
    var step by rememberSaveable { mutableStateOf(1) }
    var subId by rememberSaveable { mutableStateOf(usable.firstOrNull()?.id) }
    var imageId by rememberSaveable { mutableStateOf<String?>(null) }
    var regionId by rememberSaveable { mutableStateOf(data.catalog.regions.firstOrNull()?.id) }
    var name by rememberSaveable { mutableStateOf(defaultName) }
    var root by rememberSaveable { mutableStateOf(false) }
    var confirmRoot by rememberSaveable { mutableStateOf(false) }

    val sub = usable.firstOrNull { it.id == subId }
    val plan = sub?.let { plansById[it.planId] }
    val images = data.catalog.androidImages.filter { plan == null || it.deviceType == plan.deviceType }
    val image = images.firstOrNull { it.id == imageId }
    val rootPossible = plan?.rootAllowed == true && image?.rootSupported == true

    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.step_of, step, STEPS), color = MaterialTheme.colorScheme.onSurfaceVariant)
        LinearProgressIndicator(progress = { step / STEPS.toFloat() }, modifier = Modifier.fillMaxWidth())
        if (data.catalog.androidImages.any { it.simulated }) SimulatedBanner()

        when (step) {
            1 -> {
                Text(stringResource(R.string.step_subscription), style = MaterialTheme.typography.titleLarge)
                Text(stringResource(R.string.step_subscription_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (usable.isEmpty()) {
                    SectionCard {
                        Text(stringResource(R.string.no_active_subscription))
                        Button(onClick = onPlans) { Text(stringResource(R.string.see_plans)) }
                    }
                }
                usable.forEach { s ->
                    val p = plansById[s.planId]
                    Choice(selected = s.id == subId, onSelect = { subId = s.id; imageId = null; root = false }) {
                        Text(s.planName, style = MaterialTheme.typography.titleMedium)
                        p?.let {
                            Text(deviceTypeLabel(it.deviceType))
                            Text(stringResource(R.string.plan_specs, it.cpuCores, formatRam(it.ramMb), it.storageGb),
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(stringResource(R.string.slots_used, s.devicesUsed, s.deviceLimit), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.expires_on, formatDate(s.expiresAt) ?: "—"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            2 -> {
                Text(stringResource(R.string.step_os), style = MaterialTheme.typography.titleLarge)
                Text(stringResource(R.string.step_os_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
                images.forEach { img -> ImageChoice(img, img.id == imageId) { imageId = img.id; if (!img.rootSupported) root = false } }
            }
            3 -> {
                Text(stringResource(R.string.step_setup), style = MaterialTheme.typography.titleLarge)
                OutlinedTextField(name, { name = it.take(60) }, label = { Text(stringResource(R.string.phone_name)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                Text(stringResource(R.string.location), style = MaterialTheme.typography.titleMedium)
                data.catalog.regions.forEach { r ->
                    Choice(selected = r.id == regionId, onSelect = { regionId = r.id }) { Text(r.displayName) }
                }
                SectionCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.root_access), style = MaterialTheme.typography.titleMedium)
                            Text(
                                if (rootPossible) stringResource(R.string.root_desc) else stringResource(R.string.root_not_in_plan),
                                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(checked = root, enabled = rootPossible, onCheckedChange = { if (it) confirmRoot = true else root = false })
                    }
                }
            }
            4 -> if (plan != null && image != null && sub != null) {
                Text(stringResource(R.string.step_review), style = MaterialTheme.typography.titleLarge)
                SectionCard {
                    LabelValue(stringResource(R.string.phone_name), name)
                    LabelValue(stringResource(R.string.field_type), deviceTypeLabel(plan.deviceType))
                    LabelValue(stringResource(R.string.field_android), image.displayName)
                    LabelValue(stringResource(R.string.field_cpu), stringResource(R.string.field_cpu_value, plan.cpuCores))
                    LabelValue(stringResource(R.string.field_ram), formatRam(plan.ramMb))
                    LabelValue(stringResource(R.string.field_storage), stringResource(R.string.gb, plan.storageGb.toString()))
                    LabelValue(stringResource(R.string.field_screen), stringResource(R.string.field_screen_value, plan.screenWidth, plan.screenHeight, plan.screenDpi))
                    LabelValue(stringResource(R.string.field_region), data.catalog.regions.firstOrNull { it.id == regionId }?.displayName ?: "—")
                    LabelValue(stringResource(R.string.root_access), stringResource(if (root) R.string.yes else R.string.no))
                    LabelValue(stringResource(R.string.field_plan), sub.planName)
                    LabelValue(stringResource(R.string.field_expires), formatDate(sub.expiresAt) ?: "—")
                    LabelValue(stringResource(R.string.field_always_on), stringResource(if (plan.alwaysOn) R.string.yes else R.string.no))
                }
                Text(stringResource(R.string.review_no_charge), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.review_retention, plan.dataRetentionDays), color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (image.preinstalledApps.isNotEmpty()) {
                    Text(stringResource(R.string.field_preinstalled) + ": " + image.preinstalledApps.joinToString("، "),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        InlineError(error)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (step > 1) OutlinedButton(onClick = { step-- }, enabled = !sending, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.back)) }
            val canNext = when (step) {
                1 -> sub != null
                2 -> image != null
                3 -> name.isNotBlank() && regionId != null
                else -> true
            }
            if (step < STEPS) {
                Button(onClick = { step++ }, enabled = canNext, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.next)) }
            } else {
                Button(
                    onClick = {
                        onCreate(CreateDeviceRequest(sub!!.id, image!!.id, regionId!!, name.trim(), root && rootPossible))
                    },
                    enabled = !sending && sub != null && image != null && regionId != null,
                    modifier = Modifier.weight(1f),
                ) {
                    if (sending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(stringResource(R.string.create_phone))
                }
            }
        }
    }
    if (confirmRoot) RootWarningDialog(onDismiss = { confirmRoot = false }) { root = true; confirmRoot = false }
}

@Composable
private fun Choice(selected: Boolean, onSelect: () -> Unit, content: @Composable () -> Unit) {
    Card(
        Modifier.fillMaxWidth().selectable(selected = selected, onClick = onSelect, role = Role.RadioButton),
        border = BorderStroke(if (selected) 2.dp else 1.dp,
            if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            RadioButton(selected = selected, onClick = null)
            Spacer(Modifier.width(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) { content() }
        }
    }
}

@Composable
private fun ImageChoice(img: AndroidImage, selected: Boolean, onSelect: () -> Unit) {
    Choice(selected, onSelect) {
        Text(img.displayName, style = MaterialTheme.typography.titleMedium)
        Text(stringResource(R.string.api_level, img.apiLevel), color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (img.rootSupported) Text(stringResource(R.string.root_supported), color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (img.preinstalledApps.isNotEmpty()) {
            Text(img.preinstalledApps.joinToString("، "), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Progress(progress: CreateProgress, onDone: () -> Unit, onViewDevice: (String) -> Unit, modifier: Modifier) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        when (progress) {
            is CreateProgress.Waiting -> {
                CircularProgressIndicator()
                Spacer(Modifier.height(16.dp))
                Text(stringResource(R.string.creating_title), style = MaterialTheme.typography.titleLarge)
                Text(stringResource(R.string.creating_body, progress.device.androidVersion), textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                OutlinedButton(onClick = onDone) { Text(stringResource(R.string.go_home)) }
            }
            is CreateProgress.Ready -> {
                Icon(Icons.Outlined.CheckCircle, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(12.dp))
                Text(stringResource(R.string.created_title), style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(16.dp))
                Button(onClick = { onViewDevice(progress.device.id) }) { Text(stringResource(R.string.view_phone)) }
            }
            is CreateProgress.Failed -> {
                Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.height(12.dp))
                Text(stringResource(R.string.create_failed_title), style = MaterialTheme.typography.titleLarge)
                statusDetail(progress.device.statusDetail)?.let { Text(it, textAlign = TextAlign.Center) }
                Spacer(Modifier.height(16.dp))
                Button(onClick = { onViewDevice(progress.device.id) }) { Text(stringResource(R.string.view_phone)) }
            }
            is CreateProgress.TimedOut -> {
                Text(stringResource(R.string.create_timeout), textAlign = TextAlign.Center)
                Spacer(Modifier.height(16.dp))
                Button(onClick = onDone) { Text(stringResource(R.string.go_home)) }
            }
            else -> CircularProgressIndicator()
        }
    }
}
