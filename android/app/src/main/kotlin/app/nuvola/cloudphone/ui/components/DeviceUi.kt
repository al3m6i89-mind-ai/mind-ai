package app.nuvola.cloudphone.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.nuvola.cloudphone.R
import app.nuvola.cloudphone.data.Device
import app.nuvola.cloudphone.ui.theme.LocalStatusColors

@Composable
fun statusLabel(status: String): String = stringResource(
    when (status) {
        "CREATING" -> R.string.status_CREATING
        "STARTING" -> R.string.status_STARTING
        "RUNNING" -> R.string.status_RUNNING
        "STOPPING" -> R.string.status_STOPPING
        "STOPPED" -> R.string.status_STOPPED
        "RESTARTING" -> R.string.status_RESTARTING
        "OFFLINE" -> R.string.status_OFFLINE
        "DELETING" -> R.string.status_DELETING
        "DELETED" -> R.string.status_DELETED
        else -> R.string.status_ERROR
    },
)

@Composable
fun StatusPill(status: String) {
    val s = LocalStatusColors.current
    val (fg, bg) = when (status) {
        "RUNNING" -> s.ok to s.okBg
        "STOPPED" -> s.idle to s.idleBg
        "ERROR", "OFFLINE" -> s.bad to s.badBg
        else -> s.warn to s.warnBg
    }
    Pill(statusLabel(status), fg, bg)
}

@Composable
fun statusDetail(detail: String?): String? = when (detail) {
    null -> null
    "SUBSCRIPTION_EXPIRED" -> stringResource(R.string.detail_SUBSCRIPTION_EXPIRED)
    "CREATE_FAILED" -> stringResource(R.string.detail_CREATE_FAILED)
    "NO_CAPACITY" -> stringResource(R.string.detail_NO_CAPACITY)
    else -> stringResource(R.string.detail_generic)
}

@Composable
fun jobLabel(type: String): String = stringResource(
    when (type) {
        "CREATE" -> R.string.job_CREATE
        "START" -> R.string.job_START
        "STOP" -> R.string.job_STOP
        "RESTART" -> R.string.job_RESTART
        "DESTROY" -> R.string.job_DESTROY
        else -> R.string.job_SET_ROOT
    },
)

@Composable
fun deviceTypeLabel(type: String): String =
    stringResource(if (type == "PHYSICAL") R.string.device_type_PHYSICAL else R.string.device_type_VIRTUAL)

val Device.canOpen get() = status == "RUNNING" && pendingAction == null && subscriptionActive
val Device.canStart get() = pendingAction == null && subscriptionActive && status in setOf("STOPPED", "OFFLINE", "ERROR") && status != "CREATING"
val Device.canStop get() = pendingAction == null && status in setOf("RUNNING", "OFFLINE", "ERROR")
val Device.canRestart get() = pendingAction == null && subscriptionActive && status in setOf("RUNNING", "OFFLINE", "ERROR")
val Device.canDelete get() = pendingAction == null && status !in setOf("DELETING", "DELETED", "CREATING")
val Device.isBusy get() = pendingAction != null
