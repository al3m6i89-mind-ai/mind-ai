package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.os.LocaleListCompat
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.nuvola.cloudphone.BuildConfig
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.ChangePasswordRequest
import app.nuvola.cloudphone.data.LoginSession
import app.nuvola.cloudphone.data.Me
import app.nuvola.cloudphone.data.ThemeMode
import app.nuvola.cloudphone.data.UpdateMeRequest
import app.nuvola.cloudphone.data.call
import app.nuvola.cloudphone.ui.components.BackTopBar
import app.nuvola.cloudphone.ui.components.ErrorState
import app.nuvola.cloudphone.ui.components.InlineError
import app.nuvola.cloudphone.ui.components.LabelValue
import app.nuvola.cloudphone.ui.components.LoadingBox
import app.nuvola.cloudphone.ui.components.SectionCard
import app.nuvola.cloudphone.ui.components.formatDateTime
import app.nuvola.cloudphone.ui.components.openUrl
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

data class AccountData(val me: Me, val sessions: List<LoginSession>)

class SettingsVm(app: Application) : BaseVm(app) {
    val state = MutableStateFlow<Load<AccountData>>(Load.Loading)
    val action = MutableStateFlow(ActionState())
    val theme = MutableStateFlow(nuvola.settings.themeMode)
    val config get() = nuvola.config

    init { reload() }

    fun reload() = load(state) {
        kotlinx.coroutines.coroutineScope {
            val me = async { api.me() }
            val sessions = async { api.loginSessions() }
            AccountData(me.await(), sessions.await())
        }
    }

    fun setTheme(mode: ThemeMode) {
        nuvola.settings.themeMode = mode
        theme.value = mode
        nuvola.themeMode.value = mode
    }

    fun setLanguage(tag: String) {
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag))
        // Also store it on the account so emails arrive in the same language.
        nuvola.appScope.launch { call { api.updateMe(UpdateMeRequest(locale = tag)) } }
    }

    fun rename(name: String) = act { api.updateMe(UpdateMeRequest(displayName = name.trim())); reload() }

    fun changePassword(current: String, new: String, onDone: () -> Unit) = act {
        val r = api.changePassword(ChangePasswordRequest(current, new))
        if (!r.isSuccessful) throw retrofit2.HttpException(r)
        onDone()
        reload()
    }

    fun revoke(id: String) = act {
        val r = api.revokeLoginSession(id)
        if (!r.isSuccessful) throw retrofit2.HttpException(r)
        reload()
    }

    fun signOut(onDone: () -> Unit) {
        nuvola.appScope.launch {
            call { api.logout() }
            nuvola.tokens.clear()
            onDone()
        }
    }

    fun deleteAccount(onDone: () -> Unit) = act {
        val r = api.deleteAccount()
        if (!r.isSuccessful) throw retrofit2.HttpException(r)
        nuvola.tokens.clear()
        onDone()
    }

    private fun act(block: suspend () -> Unit) {
        if (action.value.running) return
        action.value = ActionState(running = true)
        viewModelScope.launch {
            action.value = when (val r = call(block)) {
                is ApiResult.Ok -> ActionState()
                is ApiResult.Failed -> ActionState(error = r.error)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen(onBack: () -> Unit, onSignedOut: () -> Unit, onVerifyEmail: (String) -> Unit, vm: SettingsVm = viewModel()) {
    val state by vm.state.collectAsState()
    val action by vm.action.collectAsState()
    val theme by vm.theme.collectAsState()
    val context = LocalContext.current
    var editingName by rememberSaveable { mutableStateOf(false) }
    var changingPassword by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    val currentLang = AppCompatDelegate.getApplicationLocales().toLanguageTags().ifEmpty {
        java.util.Locale.getDefault().language
    }

    Scaffold(topBar = { BackTopBar(stringResource(R.string.settings_title), onBack) }) { padding ->
        when (val s = state) {
            Load.Loading -> LoadingBox(Modifier.padding(padding))
            is Load.Failed -> ErrorState(s.error, vm::reload, Modifier.padding(padding))
            is Load.Ready -> {
                val me = s.value.me
                Column(
                    Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    InlineError(action.error)
                    SectionCard {
                        Text(stringResource(R.string.section_profile), style = MaterialTheme.typography.titleMedium)
                        LabelValue(stringResource(R.string.display_name), me.displayName)
                        LabelValue(stringResource(R.string.email), me.email)
                        if (!me.emailVerified) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(stringResource(R.string.unverified), color = MaterialTheme.colorScheme.error, modifier = Modifier.weight(1f))
                                TextButton(onClick = { onVerifyEmail(me.email) }) { Text(stringResource(R.string.verify)) }
                            }
                        }
                        TextButton(onClick = { editingName = true }) { Text(stringResource(R.string.rename)) }
                    }

                    SectionCard {
                        Text(stringResource(R.string.section_appearance), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(R.string.language))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(currentLang.startsWith("ar"), { vm.setLanguage("ar") }, { Text(stringResource(R.string.lang_ar)) })
                            FilterChip(currentLang.startsWith("en"), { vm.setLanguage("en") }, { Text(stringResource(R.string.lang_en)) })
                        }
                        Text(stringResource(R.string.theme))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(theme == ThemeMode.SYSTEM, { vm.setTheme(ThemeMode.SYSTEM) }, { Text(stringResource(R.string.theme_system)) })
                            FilterChip(theme == ThemeMode.LIGHT, { vm.setTheme(ThemeMode.LIGHT) }, { Text(stringResource(R.string.theme_light)) })
                            FilterChip(theme == ThemeMode.DARK, { vm.setTheme(ThemeMode.DARK) }, { Text(stringResource(R.string.theme_dark)) })
                        }
                    }

                    SectionCard {
                        Text(stringResource(R.string.section_security), style = MaterialTheme.typography.titleMedium)
                        TextButton(onClick = { changingPassword = true }) { Text(stringResource(R.string.change_password)) }
                        Text(stringResource(R.string.signed_in_devices), style = MaterialTheme.typography.titleMedium)
                        s.value.sessions.forEach { session ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(session.clientLabel ?: "—")
                                    Text(
                                        if (session.current) stringResource(R.string.this_device) else formatDateTime(session.lastUsedAt) ?: "",
                                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (!session.current) TextButton(onClick = { vm.revoke(session.id) }) { Text(stringResource(R.string.sign_out_device)) }
                            }
                        }
                    }

                    SectionCard {
                        Text(stringResource(R.string.section_legal), style = MaterialTheme.typography.titleMedium)
                        vm.config?.let { cfg ->
                            TextButton(onClick = { openUrl(context, cfg.termsUrl) }) { Text(stringResource(R.string.terms_of_use)) }
                            TextButton(onClick = { openUrl(context, cfg.privacyUrl) }) { Text(stringResource(R.string.privacy_policy)) }
                        }
                        Text(stringResource(R.string.app_version, BuildConfig.VERSION_NAME), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }

                    OutlinedButton(onClick = { vm.signOut(onSignedOut) }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.sign_out)) }
                    TextButton(
                        onClick = { confirmDelete = true },
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(stringResource(R.string.delete_account)) }
                }

                if (editingName) {
                    var name by rememberSaveable { mutableStateOf(me.displayName) }
                    AlertDialog(
                        onDismissRequest = { editingName = false },
                        title = { Text(stringResource(R.string.display_name)) },
                        text = { OutlinedTextField(name, { name = it.take(80) }, singleLine = true) },
                        confirmButton = { TextButton(onClick = { vm.rename(name); editingName = false }, enabled = name.isNotBlank()) { Text(stringResource(R.string.save)) } },
                        dismissButton = { TextButton(onClick = { editingName = false }) { Text(stringResource(R.string.cancel)) } },
                    )
                }
                if (changingPassword) {
                    var current by rememberSaveable { mutableStateOf("") }
                    var new by rememberSaveable { mutableStateOf("") }
                    AlertDialog(
                        onDismissRequest = { changingPassword = false },
                        title = { Text(stringResource(R.string.change_password)) },
                        text = {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                PasswordField(current, { current = it }, stringResource(R.string.current_password))
                                PasswordField(new, { new = it }, stringResource(R.string.new_password), supporting = stringResource(R.string.password_rule))
                            }
                        },
                        confirmButton = {
                            TextButton(
                                onClick = { vm.changePassword(current, new) { changingPassword = false } },
                                enabled = current.isNotEmpty() && Regex("^(?=.*[A-Za-z])(?=.*\\d).{8,128}$").matches(new),
                            ) { Text(stringResource(R.string.save)) }
                        },
                        dismissButton = { TextButton(onClick = { changingPassword = false }) { Text(stringResource(R.string.cancel)) } },
                    )
                }
                if (confirmDelete) {
                    AlertDialog(
                        onDismissRequest = { confirmDelete = false },
                        title = { Text(stringResource(R.string.delete_account)) },
                        text = { Text(stringResource(R.string.delete_account_body, 14)) },
                        confirmButton = {
                            TextButton(
                                onClick = { confirmDelete = false; vm.deleteAccount(onSignedOut) },
                                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                            ) { Text(stringResource(R.string.delete_account_confirm)) }
                        },
                        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } },
                    )
                }
            }
        }
    }
}
