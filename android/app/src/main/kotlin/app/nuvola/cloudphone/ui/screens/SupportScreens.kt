package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.CreateTicketRequest
import app.nuvola.cloudphone.data.ReplyRequest
import app.nuvola.cloudphone.data.Ticket
import app.nuvola.cloudphone.data.call
import app.nuvola.cloudphone.ui.components.BackTopBar
import app.nuvola.cloudphone.ui.components.ErrorState
import app.nuvola.cloudphone.ui.components.InlineError
import app.nuvola.cloudphone.ui.components.LoadingBox
import app.nuvola.cloudphone.ui.components.SectionCard
import app.nuvola.cloudphone.ui.components.formatDateTime
import app.nuvola.cloudphone.ui.components.openUrl
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

private val categories = listOf("DEVICE", "CONNECTION", "BILLING", "ACCOUNT", "OTHER")

@Composable
private fun categoryLabel(c: String) = stringResource(
    when (c) {
        "DEVICE" -> R.string.cat_DEVICE
        "CONNECTION" -> R.string.cat_CONNECTION
        "BILLING" -> R.string.cat_BILLING
        "ACCOUNT" -> R.string.cat_ACCOUNT
        else -> R.string.cat_OTHER
    },
)

@Composable
private fun ticketStatus(s: String) = stringResource(
    when (s) {
        "OPEN" -> R.string.tstatus_OPEN
        "WAITING_FOR_USER" -> R.string.tstatus_WAITING_FOR_USER
        "IN_PROGRESS" -> R.string.tstatus_IN_PROGRESS
        "RESOLVED" -> R.string.tstatus_RESOLVED
        else -> R.string.tstatus_CLOSED
    },
)

class SupportVm(app: Application) : BaseVm(app) {
    val tickets = MutableStateFlow<Load<List<Ticket>>>(Load.Loading)
    val action = MutableStateFlow(ActionState())
    val config get() = nuvola.config

    fun reload(silent: Boolean = true) = load(tickets, silent) { api.tickets() }

    fun create(category: String, subject: String, description: String, onCreated: (Ticket) -> Unit) {
        if (action.value.running) return
        action.value = ActionState(running = true)
        viewModelScope.launch {
            action.value = when (val r = call { api.createTicket(CreateTicketRequest(category, subject.trim(), description.trim())) }) {
                is ApiResult.Ok -> { onCreated(r.value); ActionState() }
                is ApiResult.Failed -> ActionState(error = r.error)
            }
        }
    }
}

@Composable
fun SupportScreen(onBack: () -> Unit, onNewTicket: () -> Unit, onTicket: (String) -> Unit, vm: SupportVm = viewModel()) {
    val state by vm.tickets.collectAsState()
    val context = androidx.compose.ui.platform.LocalContext.current
    LifecycleResumeEffect(Unit) {
        vm.reload()
        onPauseOrDispose { }
    }
    Scaffold(topBar = { BackTopBar(stringResource(R.string.support_title), onBack) }) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { Text(stringResource(R.string.faq), style = MaterialTheme.typography.titleMedium) }
            items(
                listOf(
                    R.string.faq_q1 to R.string.faq_a1,
                    R.string.faq_q2 to R.string.faq_a2,
                    R.string.faq_q3 to R.string.faq_a3,
                    R.string.faq_q4 to R.string.faq_a4,
                ),
            ) { (q, a) -> Faq(stringResource(q), stringResource(a)) }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(stringResource(R.string.my_tickets), style = MaterialTheme.typography.titleMedium)
                    Button(onClick = onNewTicket) { Text(stringResource(R.string.new_ticket)) }
                }
            }
            when (val s = state) {
                Load.Loading -> item { LoadingBox(Modifier.padding(24.dp)) }
                is Load.Failed -> item { ErrorState(s.error, { vm.reload(false) }) }
                is Load.Ready -> {
                    if (s.value.isEmpty()) item { Text(stringResource(R.string.no_tickets), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    items(s.value, key = { it.id }) { t ->
                        SectionCard(Modifier.clickable { onTicket(t.id) }) {
                            Text("${t.ticketNumber} · ${t.subject}", style = MaterialTheme.typography.titleMedium)
                            Text("${categoryLabel(t.category)} · ${ticketStatus(t.status)} · ${formatDateTime(t.updatedAt) ?: ""}",
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            vm.config?.let { cfg ->
                item {
                    Row {
                        androidx.compose.material3.TextButton(onClick = { openUrl(context, cfg.termsUrl) }) { Text(stringResource(R.string.terms_of_use)) }
                        androidx.compose.material3.TextButton(onClick = { openUrl(context, cfg.privacyUrl) }) { Text(stringResource(R.string.privacy_policy)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Faq(q: String, a: String) {
    var open by rememberSaveable(q) { mutableStateOf(false) }
    SectionCard(Modifier.clickable { open = !open }.animateContentSize()) {
        Text(q, style = MaterialTheme.typography.titleMedium)
        if (open) Text(a, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun NewTicketScreen(onBack: () -> Unit, onCreated: (String) -> Unit, vm: SupportVm = viewModel()) {
    val action by vm.action.collectAsState()
    var category by rememberSaveable { mutableStateOf("DEVICE") }
    var subject by rememberSaveable { mutableStateOf("") }
    var description by rememberSaveable { mutableStateOf("") }
    Scaffold(topBar = { BackTopBar(stringResource(R.string.new_ticket), onBack) }) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.ticket_category), style = MaterialTheme.typography.titleMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                categories.forEach { c -> FilterChip(selected = c == category, onClick = { category = c }, label = { Text(categoryLabel(c)) }) }
            }
            OutlinedTextField(subject, { subject = it.take(150) }, label = { Text(stringResource(R.string.ticket_subject)) },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(description, { description = it.take(5000) }, label = { Text(stringResource(R.string.ticket_description)) },
                minLines = 5, modifier = Modifier.fillMaxWidth())
            Text(stringResource(R.string.ticket_no_secrets), color = MaterialTheme.colorScheme.onSurfaceVariant)
            InlineError(action.error)
            Button(
                onClick = { vm.create(category, subject, description) { onCreated(it.id) } },
                enabled = subject.isNotBlank() && description.isNotBlank() && !action.running,
                modifier = Modifier.fillMaxWidth(),
            ) { Text(stringResource(R.string.send)) }
        }
    }
}

class TicketVm(app: Application, handle: SavedStateHandle) : BaseVm(app) {
    private val id: String = checkNotNull(handle["ticketId"])
    val ticket = MutableStateFlow<Load<Ticket>>(Load.Loading)
    val action = MutableStateFlow(ActionState())

    init { reload() }

    fun reload() = load(ticket) { api.ticket(id) }

    fun reply(body: String, onSent: () -> Unit) {
        if (action.value.running) return
        action.value = ActionState(running = true)
        viewModelScope.launch {
            action.value = when (val r = call { api.reply(id, ReplyRequest(body.trim())) }) {
                is ApiResult.Ok -> { ticket.value = Load.Ready(r.value); onSent(); ActionState() }
                is ApiResult.Failed -> ActionState(error = r.error)
            }
        }
    }
}

@Composable
fun TicketScreen(onBack: () -> Unit, vm: TicketVm = viewModel()) {
    val state by vm.ticket.collectAsState()
    val action by vm.action.collectAsState()
    var reply by rememberSaveable { mutableStateOf("") }
    Scaffold(topBar = { BackTopBar((state as? Load.Ready)?.value?.ticketNumber ?: "", onBack) }) { padding ->
        when (val s = state) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(s.error, vm::reload, Modifier.padding(padding))
            is Load.Ready -> {
                val t = s.value
                Column(Modifier.padding(padding).fillMaxSize().imePadding()) {
                    LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        item {
                            Text(t.subject, style = MaterialTheme.typography.titleLarge)
                            Text("${categoryLabel(t.category)} · ${ticketStatus(t.status)}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        item { Bubble(stringResource(R.string.from_you), t.description, t.createdAt, mine = true) }
                        items(t.messages.orEmpty(), key = { it.id }) { m ->
                            Bubble(stringResource(if (m.fromSupport) R.string.from_support else R.string.from_you), m.body, m.createdAt, mine = !m.fromSupport)
                        }
                    }
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        InlineError(action.error)
                        OutlinedTextField(reply, { reply = it.take(5000) }, label = { Text(stringResource(R.string.reply_hint)) },
                            modifier = Modifier.fillMaxWidth(), maxLines = 4)
                        Button(onClick = { vm.reply(reply) { reply = "" } }, enabled = reply.isNotBlank() && !action.running,
                            modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.send)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Bubble(author: String, body: String, at: String, mine: Boolean) {
    val bg = if (mine) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
    val fg = if (mine) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
    Column(Modifier.fillMaxWidth().background(bg, RoundedCornerShape(14.dp)).padding(12.dp)) {
        Text("$author · ${formatDateTime(at) ?: ""}", style = MaterialTheme.typography.labelMedium, color = fg)
        Text(body, color = fg)
    }
}
