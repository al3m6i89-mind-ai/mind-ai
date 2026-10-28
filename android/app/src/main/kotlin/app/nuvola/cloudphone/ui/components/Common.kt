package app.nuvola.cloudphone.ui.components

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.AppError
import app.nuvola.cloudphone.ui.theme.LocalStatusColors
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** One place that turns server error codes into translated sentences. */
fun AppError.message(context: Context): String = when (this) {
    AppError.NoInternet -> context.getString(R.string.err_no_internet)
    AppError.ServerUnreachable -> context.getString(R.string.err_server_unreachable)
    is AppError.Server -> when (code) {
        "INVALID_CREDENTIALS" -> context.getString(R.string.err_INVALID_CREDENTIALS)
        "TOO_MANY_ATTEMPTS" -> context.getString(R.string.err_TOO_MANY_ATTEMPTS)
        "EMAIL_ALREADY_REGISTERED" -> context.getString(R.string.err_EMAIL_ALREADY_REGISTERED)
        "TERMS_NOT_ACCEPTED" -> context.getString(R.string.err_TERMS_NOT_ACCEPTED)
        "VALIDATION_FAILED" -> context.getString(R.string.err_VALIDATION_FAILED)
        "INVALID_TOKEN" -> context.getString(R.string.err_INVALID_TOKEN)
        "SESSION_EXPIRED" -> context.getString(R.string.err_SESSION_EXPIRED)
        "UNAUTHENTICATED" -> context.getString(R.string.err_UNAUTHENTICATED)
        "ACCOUNT_SUSPENDED" -> context.getString(R.string.err_ACCOUNT_SUSPENDED)
        "EMAIL_NOT_VERIFIED" -> context.getString(R.string.err_EMAIL_NOT_VERIFIED)
        "NOT_FOUND" -> context.getString(R.string.err_NOT_FOUND)
        "FORBIDDEN" -> context.getString(R.string.err_FORBIDDEN)
        "SUBSCRIPTION_REQUIRED" -> context.getString(R.string.err_SUBSCRIPTION_REQUIRED)
        "SUBSCRIPTION_EXPIRED" -> context.getString(R.string.err_SUBSCRIPTION_EXPIRED)
        "PAYMENT_REQUIRED" -> context.getString(R.string.err_PAYMENT_REQUIRED)
        "DEVICE_LIMIT_REACHED" -> context.getString(R.string.err_DEVICE_LIMIT_REACHED)
        "CONCURRENT_SESSION_LIMIT_REACHED" -> context.getString(R.string.err_CONCURRENT_SESSION_LIMIT_REACHED)
        "DEVICE_BUSY" -> context.getString(R.string.err_DEVICE_BUSY)
        "INVALID_DEVICE_STATE" -> context.getString(R.string.err_INVALID_DEVICE_STATE)
        "ROOT_NOT_ALLOWED" -> context.getString(R.string.err_ROOT_NOT_ALLOWED)
        "IMAGE_NOT_AVAILABLE" -> context.getString(R.string.err_IMAGE_NOT_AVAILABLE)
        "REGION_NOT_AVAILABLE" -> context.getString(R.string.err_REGION_NOT_AVAILABLE)
        "NO_CAPACITY" -> context.getString(R.string.err_NO_CAPACITY)
        "STREAMING_NOT_AVAILABLE" -> context.getString(R.string.err_STREAMING_NOT_AVAILABLE)
        "IDEMPOTENCY_KEY_REQUIRED" -> context.getString(R.string.err_IDEMPOTENCY_KEY_REQUIRED)
        "INTERNAL_ERROR" -> context.getString(R.string.err_internal, referenceId ?: "-")
        else -> context.getString(R.string.err_generic)
    }
}

val AppError.code: String? get() = (this as? AppError.Server)?.code

@Composable
fun errorText(error: AppError): String = error.message(LocalContext.current)

fun formatDate(iso: String?): String? = iso?.let {
    runCatching {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withZone(ZoneId.systemDefault()).format(Instant.parse(it))
    }.getOrNull()
}

fun formatDateTime(iso: String?): String? = iso?.let {
    runCatching {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withZone(ZoneId.systemDefault()).format(Instant.parse(it))
    }.getOrNull()
}

fun formatRam(mb: Int): String = if (mb % 1024 == 0) "${mb / 1024} GB" else "%.1f GB".format(mb / 1024.0)

fun openUrl(context: Context, url: String) {
    runCatching { CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url)) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackTopBar(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    TopAppBar(
        title = { Text(title) },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back)) }
        },
        actions = { actions() },
    )
}

@Composable
fun LoadingBox(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

/** Full-screen error with a retry button. Retry re-reads data only; it never repeats a payment or creation. */
@Composable
fun ErrorState(error: AppError, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Outlined.CloudOff, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.padding(8.dp))
        Text(errorText(error), style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.padding(8.dp))
        Button(onClick = onRetry) { Text(stringResource(R.string.retry)) }
    }
}

@Composable
fun InlineError(error: AppError?) {
    if (error == null) return
    Text(
        errorText(error),
        color = MaterialTheme.colorScheme.onErrorContainer,
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.fillMaxWidth()
            .background(MaterialTheme.colorScheme.errorContainer, RoundedCornerShape(10.dp))
            .padding(12.dp),
    )
}

@Composable
fun SimulatedBanner() {
    val s = LocalStatusColors.current
    Row(
        Modifier.fillMaxWidth().background(s.warnBg, RoundedCornerShape(12.dp)).padding(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Outlined.Science, null, tint = s.warn)
        Spacer(Modifier.width(10.dp))
        Text(stringResource(R.string.simulated_banner), color = s.warn, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun Pill(text: String, fg: Color, bg: Color) {
    Row(
        Modifier.background(bg, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(6.dp).background(fg, CircleShape))
        Spacer(Modifier.width(6.dp))
        Text(text, color = fg, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
fun SectionCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Card(
        modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { content() }
    }
}

@Composable
fun LabelValue(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.width(12.dp))
        Text(value, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.End)
    }
}
