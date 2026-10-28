package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.AppError
import app.nuvola.cloudphone.data.CreateSubscriptionRequest
import app.nuvola.cloudphone.data.Invoice
import app.nuvola.cloudphone.data.Plan
import app.nuvola.cloudphone.data.Subscription
import app.nuvola.cloudphone.data.call
import app.nuvola.cloudphone.ui.components.BackTopBar
import app.nuvola.cloudphone.ui.components.ErrorState
import app.nuvola.cloudphone.ui.components.InlineError
import app.nuvola.cloudphone.ui.components.LabelValue
import app.nuvola.cloudphone.ui.components.LoadingBox
import app.nuvola.cloudphone.ui.components.Pill
import app.nuvola.cloudphone.ui.components.SectionCard
import app.nuvola.cloudphone.ui.components.deviceTypeLabel
import app.nuvola.cloudphone.ui.components.formatDate
import app.nuvola.cloudphone.ui.components.formatRam
import app.nuvola.cloudphone.ui.theme.LocalStatusColors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Currency

fun formatMoney(amount: Double, currencyCode: String): String = runCatching {
    val format = NumberFormat.getCurrencyInstance()
    format.currency = Currency.getInstance(currencyCode)
    format.format(amount)
}.getOrDefault("$amount $currencyCode")

@Composable
private fun periodLabel(period: String) = stringResource(
    when (period) {
        "DAY" -> R.string.per_DAY
        "WEEK" -> R.string.per_WEEK
        "QUARTER" -> R.string.per_QUARTER
        "YEAR" -> R.string.per_YEAR
        else -> R.string.per_MONTH
    },
)

class PlansVm(app: Application) : BaseVm(app) {
    val plans = MutableStateFlow<Load<List<Plan>>>(Load.Loading)
    val action = MutableStateFlow(ActionState())

    init { reload() }

    fun reload() = load(plans) { api.plans() }

    fun choose(plan: Plan, onDone: () -> Unit) {
        if (action.value.running) return
        action.value = ActionState(running = true)
        viewModelScope.launch {
            action.value = when (val r = call { api.createSubscription(CreateSubscriptionRequest(plan.id)) }) {
                is ApiResult.Ok -> { onDone(); ActionState(done = true) }
                is ApiResult.Failed -> ActionState(error = r.error)
            }
        }
    }
}

@Composable
fun PlansScreen(onBack: () -> Unit, onActivated: () -> Unit, vm: PlansVm = viewModel()) {
    val state by vm.plans.collectAsState()
    val action by vm.action.collectAsState()
    Scaffold(topBar = { BackTopBar(stringResource(R.string.plans_title), onBack) }) { padding ->
        when (val s = state) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(s.error, vm::reload, Modifier.padding(padding))
            is Load.Ready -> LazyColumn(
                Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                s.value.firstOrNull()?.let { item { Text(stringResource(R.string.prices_note, it.currency), color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                if (action.error != null) item { InlineError(action.error) }
                items(s.value, key = { it.id }) { plan ->
                    SectionCard {
                        Text(plan.name, style = MaterialTheme.typography.titleMedium)
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text(formatMoney(plan.price, plan.currency), style = MaterialTheme.typography.headlineSmall)
                            Text(" " + periodLabel(plan.billingPeriod), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(deviceTypeLabel(plan.deviceType))
                        Text(stringResource(R.string.plan_devices, plan.deviceLimit))
                        Text(stringResource(R.string.plan_concurrent, plan.concurrentSessionLimit))
                        Text(stringResource(R.string.plan_specs, plan.cpuCores, formatRam(plan.ramMb), plan.storageGb))
                        Text(stringResource(R.string.plan_screen, plan.screenWidth, plan.screenHeight, plan.maxFps))
                        Text(stringResource(if (plan.alwaysOn) R.string.plan_always_on else R.string.plan_not_always_on))
                        if (plan.rootAllowed) Text(stringResource(R.string.plan_root))
                        Text(stringResource(R.string.plan_retention, plan.dataRetentionDays), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Button(onClick = { vm.choose(plan, onActivated) }, enabled = !action.running, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.choose_plan))
                        }
                    }
                }
            }
        }
    }
}

class SubscriptionsVm(app: Application) : BaseVm(app) {
    val subs = MutableStateFlow<Load<List<Subscription>>>(Load.Loading)
    val error = MutableStateFlow<AppError?>(null)

    init { reload() }

    fun reload() = load(subs) { api.subscriptions() }

    fun cancelRenewal(id: String) {
        viewModelScope.launch {
            when (val r = call { api.cancelRenewal(id) }) {
                is ApiResult.Ok -> reload()
                is ApiResult.Failed -> error.value = r.error
            }
        }
    }
}

@Composable
fun SubscriptionsScreen(onBack: () -> Unit, onPlans: () -> Unit, vm: SubscriptionsVm = viewModel()) {
    val state by vm.subs.collectAsState()
    val error by vm.error.collectAsState()
    val colors = LocalStatusColors.current
    Scaffold(topBar = { BackTopBar(stringResource(R.string.subscriptions_title), onBack) }) { padding ->
        when (val s = state) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(s.error, vm::reload, Modifier.padding(padding))
            is Load.Ready -> LazyColumn(
                Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (error != null) item { InlineError(error) }
                if (s.value.isEmpty()) item {
                    SectionCard {
                        Text(stringResource(R.string.no_subscriptions))
                        Button(onClick = onPlans) { Text(stringResource(R.string.see_plans)) }
                    }
                }
                items(s.value, key = { it.id }) { sub ->
                    SectionCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(sub.planName, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                            val (fg, bg) = if (sub.status == "ACTIVE") colors.ok to colors.okBg else colors.idle to colors.idleBg
                            Pill(subStatus(sub.status), fg, bg)
                        }
                        Text(stringResource(R.string.started_on, formatDate(sub.startsAt) ?: "—"))
                        LabelValue(stringResource(R.string.field_expires), formatDate(sub.expiresAt) ?: "—")
                        Text(stringResource(R.string.slots_used, sub.devicesUsed, sub.deviceLimit), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            if (sub.renewalStatus == "AUTO") stringResource(R.string.renewal_auto, formatMoney(sub.renewalPrice, sub.currency))
                            else stringResource(R.string.renewal_off),
                        )
                        Text(stringResource(R.string.review_retention, sub.dataRetentionDays), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (sub.provider == "dev-unpaid") Text(stringResource(R.string.sub_dev_note), color = colors.warn)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (sub.renewalStatus == "AUTO") OutlinedButton(onClick = { vm.cancelRenewal(sub.id) }) {
                                Text(stringResource(R.string.cancel_renewal))
                            }
                            OutlinedButton(onClick = onPlans) { Text(stringResource(R.string.extend)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun subStatus(status: String) = stringResource(
    when (status) {
        "ACTIVE" -> R.string.sub_status_ACTIVE
        "EXPIRED" -> R.string.sub_status_EXPIRED
        "CANCELED" -> R.string.sub_status_CANCELED
        else -> R.string.sub_status_PENDING_PAYMENT
    },
)

class InvoicesVm(app: Application) : BaseVm(app) {
    val invoices = MutableStateFlow<Load<List<Invoice>>>(Load.Loading)
    init { reload() }
    fun reload() = load(invoices) { api.invoices() }
}

@Composable
fun InvoicesScreen(onBack: () -> Unit, vm: InvoicesVm = viewModel()) {
    val state by vm.invoices.collectAsState()
    Scaffold(topBar = { BackTopBar(stringResource(R.string.invoices_title), onBack) }) { padding ->
        when (val s = state) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(s.error, vm::reload, Modifier.padding(padding))
            is Load.Ready -> LazyColumn(
                Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (s.value.isEmpty()) item {
                    Text(stringResource(R.string.no_invoices), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(32.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                items(s.value, key = { it.id }) { inv ->
                    SectionCard {
                        LabelValue(inv.invoiceNumber, formatMoney(inv.total, inv.currency))
                        Text(formatDate(inv.createdAt) ?: "", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
