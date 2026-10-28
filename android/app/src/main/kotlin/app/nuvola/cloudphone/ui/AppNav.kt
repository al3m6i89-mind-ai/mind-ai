package app.nuvola.cloudphone.ui

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import app.nuvola.cloudphone.NuvolaApp
import app.nuvola.cloudphone.ui.screens.CreateDeviceScreen
import app.nuvola.cloudphone.ui.screens.DashboardScreen
import app.nuvola.cloudphone.ui.screens.DeviceDetailScreen
import app.nuvola.cloudphone.ui.screens.ForgotPasswordScreen
import app.nuvola.cloudphone.ui.screens.InvoicesScreen
import app.nuvola.cloudphone.ui.screens.LiveScreen
import app.nuvola.cloudphone.ui.screens.LoginScreen
import app.nuvola.cloudphone.ui.screens.NewTicketScreen
import app.nuvola.cloudphone.ui.screens.PlansScreen
import app.nuvola.cloudphone.ui.screens.RegisterScreen
import app.nuvola.cloudphone.ui.screens.SettingsScreen
import app.nuvola.cloudphone.ui.screens.SplashScreen
import app.nuvola.cloudphone.ui.screens.SubscriptionsScreen
import app.nuvola.cloudphone.ui.screens.SupportScreen
import app.nuvola.cloudphone.ui.screens.TicketScreen
import app.nuvola.cloudphone.ui.screens.VerifyEmailScreen

private object R0 {
    const val SPLASH = "splash"
    const val LOGIN = "login"
    const val REGISTER = "register"
    const val FORGOT = "forgot"
    const val VERIFY = "verify?email={email}"
    const val HOME = "home"
    const val DEVICE = "device/{deviceId}"
    const val LIVE = "live/{deviceId}"
    const val CREATE = "create"
    const val PLANS = "plans"
    const val SUBSCRIPTIONS = "subscriptions"
    const val INVOICES = "invoices"
    const val SUPPORT = "support"
    const val NEW_TICKET = "support/new"
    const val TICKET = "support/ticket/{ticketId}"
    const val SETTINGS = "settings"
}

private fun NavHostController.resetTo(route: String) = navigate(route) {
    popUpTo(0) { inclusive = true }
    launchSingleTop = true
}

private fun verifyRoute(email: String?) = "verify?email=" + Uri.encode(email ?: "")

@Composable
fun AppNav() {
    val nav = rememberNavController()
    val app = LocalContext.current.applicationContext as NuvolaApp

    // A refresh token the server no longer accepts sends the user back to sign in from any screen.
    LaunchedEffect(Unit) {
        app.client.sessionExpired.collect { nav.resetTo(R0.LOGIN) }
    }

    NavHost(nav, startDestination = R0.SPLASH) {
        composable(R0.SPLASH) {
            SplashScreen(onSignedIn = { nav.resetTo(R0.HOME) }, onSignedOut = { nav.resetTo(R0.LOGIN) })
        }
        composable(R0.LOGIN) {
            LoginScreen(
                onSignedIn = { verified, email -> nav.resetTo(R0.HOME); if (!verified) nav.navigate(verifyRoute(email)) },
                onRegister = { nav.navigate(R0.REGISTER) },
                onForgot = { nav.navigate(R0.FORGOT) },
            )
        }
        composable(R0.REGISTER) {
            RegisterScreen(onRegistered = { email -> nav.resetTo(R0.HOME); nav.navigate(verifyRoute(email)) }, onSignIn = { nav.popBackStack() })
        }
        composable(R0.FORGOT) {
            ForgotPasswordScreen(onDone = { nav.resetTo(R0.LOGIN) }, onBack = { nav.popBackStack() })
        }
        composable(R0.VERIFY, arguments = listOf(navArgument("email") { type = NavType.StringType; defaultValue = "" })) { entry ->
            VerifyEmailScreen(
                email = entry.arguments?.getString("email")?.ifBlank { null },
                onVerified = { nav.popBackStack() },
                onLater = { nav.popBackStack() },
            )
        }
        composable(R0.HOME) {
            DashboardScreen(
                onOpenDevice = { nav.navigate("device/$it") },
                onLive = { nav.navigate("live/$it") },
                onCreate = { nav.navigate(R0.CREATE) },
                onPlans = { nav.navigate(R0.PLANS) },
                onSubscriptions = { nav.navigate(R0.SUBSCRIPTIONS) },
                onInvoices = { nav.navigate(R0.INVOICES) },
                onSupport = { nav.navigate(R0.SUPPORT) },
                onSettings = { nav.navigate(R0.SETTINGS) },
                onVerifyEmail = { nav.navigate(verifyRoute(it)) },
            )
        }
        composable(R0.DEVICE, arguments = listOf(navArgument("deviceId") { type = NavType.StringType })) {
            DeviceDetailScreen(
                onBack = { nav.popBackStack() },
                onLive = { nav.navigate("live/$it") },
                onExtend = { nav.navigate(R0.SUBSCRIPTIONS) },
            )
        }
        composable(R0.LIVE, arguments = listOf(navArgument("deviceId") { type = NavType.StringType })) {
            LiveScreen(onBack = { nav.popBackStack() })
        }
        composable(R0.CREATE) {
            CreateDeviceScreen(
                onBack = { nav.popBackStack() },
                onPlans = { nav.navigate(R0.PLANS) },
                onDone = { nav.popBackStack(R0.HOME, inclusive = false) },
                onViewDevice = { id -> nav.navigate("device/$id") { popUpTo(R0.HOME) } },
            )
        }
        composable(R0.PLANS) {
            PlansScreen(onBack = { nav.popBackStack() }, onActivated = { nav.popBackStack() })
        }
        composable(R0.SUBSCRIPTIONS) {
            SubscriptionsScreen(onBack = { nav.popBackStack() }, onPlans = { nav.navigate(R0.PLANS) })
        }
        composable(R0.INVOICES) { InvoicesScreen(onBack = { nav.popBackStack() }) }
        composable(R0.SUPPORT) {
            SupportScreen(
                onBack = { nav.popBackStack() },
                onNewTicket = { nav.navigate(R0.NEW_TICKET) },
                onTicket = { nav.navigate("support/ticket/$it") },
            )
        }
        composable(R0.NEW_TICKET) {
            NewTicketScreen(onBack = { nav.popBackStack() }, onCreated = { id ->
                nav.navigate("support/ticket/$id") { popUpTo(R0.SUPPORT) }
            })
        }
        composable(R0.TICKET, arguments = listOf(navArgument("ticketId") { type = NavType.StringType })) {
            TicketScreen(onBack = { nav.popBackStack() })
        }
        composable(R0.SETTINGS) {
            SettingsScreen(
                onBack = { nav.popBackStack() },
                onSignedOut = { nav.resetTo(R0.LOGIN) },
                onVerifyEmail = { nav.navigate(verifyRoute(it)) },
            )
        }
    }
}
