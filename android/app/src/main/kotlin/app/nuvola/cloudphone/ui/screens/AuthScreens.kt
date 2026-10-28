package app.nuvola.cloudphone.ui.screens

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.nuvola.cloudphone.BuildConfig
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.ApiResult
import app.nuvola.cloudphone.data.AppConfig
import app.nuvola.cloudphone.data.AppError
import app.nuvola.cloudphone.data.EmailRequest
import app.nuvola.cloudphone.data.LoginRequest
import app.nuvola.cloudphone.data.Me
import app.nuvola.cloudphone.data.RegisterRequest
import app.nuvola.cloudphone.data.ResetPasswordRequest
import app.nuvola.cloudphone.data.TokenRequest
import app.nuvola.cloudphone.data.call
import app.nuvola.cloudphone.ui.components.InlineError
import app.nuvola.cloudphone.ui.components.errorText
import app.nuvola.cloudphone.ui.components.openUrl
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale

// ---------------- Splash ----------------

sealed interface SplashState {
    data object Checking : SplashState
    data class Failed(val error: AppError) : SplashState
    data object UpdateRequired : SplashState
    data class Done(val signedIn: Boolean, val me: Me?) : SplashState
}

class SplashVm(app: Application) : BaseVm(app) {
    val state = MutableStateFlow<SplashState>(SplashState.Checking)

    init { check() }

    /**
     * Config, then session. A free-tier server can take up to a minute to wake up, so unreachable
     * errors are retried for a bounded time; the splash never spins forever.
     */
    fun check() {
        state.value = SplashState.Checking
        viewModelScope.launch {
            val result = withTimeoutOrNull(90_000) {
                var cfg = call { api.appConfig() }
                while (cfg is ApiResult.Failed && cfg.error == AppError.ServerUnreachable) {
                    kotlinx.coroutines.delay(3_000)
                    cfg = call { api.appConfig() }
                }
                when (cfg) {
                    is ApiResult.Failed -> SplashState.Failed(cfg.error)
                    is ApiResult.Ok -> {
                        nuvola.config = cfg.value
                        if (cfg.value.minSupportedAppVersion > BuildConfig.VERSION_CODE) SplashState.UpdateRequired
                        else if (!nuvola.tokens.hasSession) SplashState.Done(false, null)
                        else when (val me = call { api.me() }) {
                            is ApiResult.Ok -> SplashState.Done(true, me.value)
                            is ApiResult.Failed -> if (me.error is AppError.Server) {
                                nuvola.tokens.clear()
                                SplashState.Done(false, null)
                            } else SplashState.Failed(me.error)
                        }
                    }
                }
            }
            state.value = result ?: SplashState.Failed(AppError.ServerUnreachable)
        }
    }
}

@Composable
fun SplashScreen(onSignedIn: (verified: Boolean) -> Unit, onSignedOut: () -> Unit, vm: SplashVm = viewModel()) {
    val state by vm.state.collectAsState()
    LaunchedEffect(state) {
        (state as? SplashState.Done)?.let { if (it.signedIn) onSignedIn(it.me?.emailVerified == true) else onSignedOut() }
    }
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Brand()
        Spacer(Modifier.height(32.dp))
        when (val s = state) {
            SplashState.Checking, is SplashState.Done -> {
                CircularProgressIndicator(Modifier.size(28.dp))
                Spacer(Modifier.height(12.dp))
                Text(stringResource(R.string.splash_checking), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            is SplashState.Failed -> {
                Text(stringResource(R.string.splash_failed_title), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text(errorText(s.error), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Button(onClick = vm::check) { Text(stringResource(R.string.retry)) }
            }
            SplashState.UpdateRequired -> Text(stringResource(R.string.update_required), textAlign = TextAlign.Center)
        }
    }
}

@Composable
fun Brand() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(72.dp).padding(4.dp),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.Cloud, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.primary)
        }
        Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineSmall)
        Text(stringResource(R.string.tagline), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// ---------------- Login / Register ----------------

class AuthVm(app: Application) : BaseVm(app) {
    val action = MutableStateFlow(ActionState())
    val info = MutableStateFlow<String?>(null)

    fun login(email: String, password: String, onDone: (verified: Boolean, email: String) -> Unit) = launchAction {
        val tokens = api.login(LoginRequest(email.trim(), password))
        nuvola.tokens.save(tokens)
        val me = api.me()
        onDone(me.emailVerified, me.email)
    }

    fun register(name: String, email: String, password: String, accepted: Boolean, onDone: (String) -> Unit) = launchAction {
        val locale = if (Locale.getDefault().language == "ar") "ar" else "en"
        nuvola.tokens.save(api.register(RegisterRequest(email.trim(), password, name.trim(), locale, accepted)))
        onDone(email.trim())
    }

    fun verify(code: String, onDone: () -> Unit) = launchAction {
        val r = api.verifyEmail(TokenRequest(code.trim()))
        if (!r.isSuccessful) throw retrofit2.HttpException(r)
        onDone()
    }

    fun resend(sentMessage: String) = launchAction {
        val r = api.resendVerification()
        if (!r.isSuccessful) throw retrofit2.HttpException(r)
        info.value = sentMessage
    }

    fun requestReset(email: String, onDone: () -> Unit) = launchAction {
        val r = api.forgotPassword(EmailRequest(email.trim()))
        if (!r.isSuccessful) throw retrofit2.HttpException(r)
        onDone()
    }

    fun reset(code: String, password: String, onDone: () -> Unit) = launchAction {
        val r = api.resetPassword(ResetPasswordRequest(code.trim(), password))
        if (!r.isSuccessful) throw retrofit2.HttpException(r)
        onDone()
    }

    private fun launchAction(block: suspend () -> Unit) {
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

private val emailRegex = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
private val passwordRegex = Regex("^(?=.*[A-Za-z])(?=.*\\d).{8,128}$")

@Composable
private fun AuthScaffold(title: String, content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 480.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Spacer(Modifier.height(24.dp))
            Brand()
            Spacer(Modifier.height(8.dp))
            Text(title, style = MaterialTheme.typography.titleLarge)
            content()
        }
    }
}

@Composable
fun PasswordField(value: String, onChange: (String) -> Unit, label: String, supporting: String? = null, isError: Boolean = false) {
    var visible by remember { mutableStateOf(false) }
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = true,
        isError = isError,
        supportingText = { if (supporting != null) Text(supporting) },
        visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        trailingIcon = {
            IconButton(onClick = { visible = !visible }) {
                Icon(if (visible) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, contentDescription = null)
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
fun LoginScreen(
    onSignedIn: (verified: Boolean, email: String) -> Unit,
    onRegister: () -> Unit,
    onForgot: () -> Unit,
    vm: AuthVm = viewModel(),
) {
    val state by vm.action.collectAsState()
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    val valid = emailRegex.matches(email.trim()) && password.isNotEmpty()

    AuthScaffold(stringResource(R.string.sign_in_title)) {
        OutlinedTextField(
            email, { email = it }, label = { Text(stringResource(R.string.email)) }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth(),
        )
        PasswordField(password, { password = it }, stringResource(R.string.password))
        InlineError(state.error)
        Button(
            onClick = { vm.login(email, password, onSignedIn) },
            enabled = valid && !state.running,
            modifier = Modifier.fillMaxWidth().height(50.dp),
        ) {
            if (state.running) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text(stringResource(R.string.sign_in))
        }
        TextButton(onClick = onForgot) { Text(stringResource(R.string.forgot_password)) }
        Text(stringResource(R.string.google_sign_in_pending), style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.no_account))
            TextButton(onClick = onRegister) { Text(stringResource(R.string.create_account)) }
        }
    }
}

@Composable
fun RegisterScreen(onRegistered: (String) -> Unit, onSignIn: () -> Unit, vm: AuthVm = viewModel()) {
    val state by vm.action.collectAsState()
    val context = LocalContext.current
    val config = (context.applicationContext as app.nuvola.cloudphone.NuvolaApp).config
    var name by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var accepted by rememberSaveable { mutableStateOf(false) }
    val emailOk = emailRegex.matches(email.trim())
    val passwordOk = passwordRegex.matches(password)
    val serverFields = (state.error as? AppError.Server)?.fields.orEmpty()

    AuthScaffold(stringResource(R.string.create_account_title)) {
        OutlinedTextField(name, { name = it.take(80) }, label = { Text(stringResource(R.string.display_name)) },
            singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(
            email, { email = it }, label = { Text(stringResource(R.string.email)) }, singleLine = true,
            isError = (email.isNotEmpty() && !emailOk) || "email" in serverFields,
            supportingText = { if (email.isNotEmpty() && !emailOk) Text(stringResource(R.string.invalid_email)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth(),
        )
        PasswordField(password, { password = it }, stringResource(R.string.password),
            supporting = stringResource(R.string.password_rule), isError = (password.isNotEmpty() && !passwordOk) || "password" in serverFields)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(accepted, { accepted = it })
            Column {
                Text(stringResource(R.string.accept_terms_prefix))
                Row {
                    TextButton(onClick = { config?.let { openUrl(context, it.termsUrl) } }, enabled = config != null) {
                        Text(stringResource(R.string.terms_of_use))
                    }
                    TextButton(onClick = { config?.let { openUrl(context, it.privacyUrl) } }, enabled = config != null) {
                        Text(stringResource(R.string.privacy_policy))
                    }
                }
            }
        }
        InlineError(state.error)
        Button(
            onClick = { vm.register(name, email, password, accepted, onRegistered) },
            enabled = name.isNotBlank() && emailOk && passwordOk && accepted && !state.running,
            modifier = Modifier.fillMaxWidth().height(50.dp),
        ) {
            if (state.running) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text(stringResource(R.string.create_account))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.have_account))
            TextButton(onClick = onSignIn) { Text(stringResource(R.string.sign_in)) }
        }
    }
}

@Composable
fun VerifyEmailScreen(email: String?, onVerified: () -> Unit, onLater: () -> Unit, vm: AuthVm = viewModel()) {
    val state by vm.action.collectAsState()
    val info by vm.info.collectAsState()
    val sent = stringResource(R.string.code_sent)
    var code by rememberSaveable { mutableStateOf("") }
    AuthScaffold(stringResource(R.string.verify_email_title)) {
        Text(stringResource(R.string.verify_email_body, email ?: ""), color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedTextField(code, { code = it }, label = { Text(stringResource(R.string.verification_code)) },
            singleLine = true, modifier = Modifier.fillMaxWidth())
        InlineError(state.error)
        info?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
        Button(onClick = { vm.verify(code, onVerified) }, enabled = code.isNotBlank() && !state.running,
            modifier = Modifier.fillMaxWidth().height(50.dp)) { Text(stringResource(R.string.verify)) }
        Row {
            TextButton(onClick = { vm.resend(sent) }, enabled = !state.running) { Text(stringResource(R.string.resend_code)) }
            TextButton(onClick = onLater) { Text(stringResource(R.string.later)) }
        }
    }
}

@Composable
fun ForgotPasswordScreen(onDone: () -> Unit, onBack: () -> Unit, vm: AuthVm = viewModel()) {
    val state by vm.action.collectAsState()
    var email by rememberSaveable { mutableStateOf("") }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var code by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    AuthScaffold(stringResource(R.string.reset_title)) {
        if (!codeSent) {
            Text(stringResource(R.string.reset_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(email, { email = it }, label = { Text(stringResource(R.string.email)) }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth())
            InlineError(state.error)
            Button(onClick = { vm.requestReset(email) { codeSent = true } },
                enabled = emailRegex.matches(email.trim()) && !state.running,
                modifier = Modifier.fillMaxWidth().height(50.dp)) { Text(stringResource(R.string.send_code)) }
        } else {
            Text(stringResource(R.string.reset_code_sent), color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(code, { code = it }, label = { Text(stringResource(R.string.verification_code)) },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            PasswordField(password, { password = it }, stringResource(R.string.new_password), supporting = stringResource(R.string.password_rule))
            InlineError(state.error)
            Button(onClick = { vm.reset(code, password, onDone) },
                enabled = code.isNotBlank() && passwordRegex.matches(password) && !state.running,
                modifier = Modifier.fillMaxWidth().height(50.dp)) { Text(stringResource(R.string.reset_password)) }
        }
        TextButton(onClick = onBack) { Text(stringResource(R.string.back)) }
    }
}
