package app.nuvola.config

import org.springframework.boot.context.properties.ConfigurationProperties
import java.time.Duration

@ConfigurationProperties(prefix = "app")
data class AppProperties(
    val environment: String,
    val publicBaseUrl: String,
    val termsVersion: String,
    val termsUrl: String,
    val privacyUrl: String,
    val supportEmail: String,
    val minSupportedAppVersion: Int,
    val security: Security,
    val mail: Mail,
    val devices: Devices,
    val streaming: Streaming,
    val billing: Billing,
    val account: Account,
) {
    val isProduction: Boolean get() = environment == "production"

    data class Security(
        val jwtSecret: String,
        val accessTokenTtl: Duration,
        val refreshTokenTtl: Duration,
        val loginAttemptsPerEmail: Int,
        val loginAttemptsPerIp: Int,
        val loginWindow: Duration,
    )

    data class Mail(val from: String, val transport: String)

    data class Devices(
        val provider: String,
        val jobPollInterval: Duration,
        val jobTimeout: Duration,
        val mockStepDelay: Duration,
        val redroid: Redroid = Redroid(),
    )

    /** One Redroid node (a server running the Nuvola node agent). */
    data class Redroid(
        val nodeUrl: String = "",
        val nodeToken: String = "",
        val requestTimeout: Duration = Duration.ofMinutes(8),
    )

    data class Streaming(val sessionTokenTtl: Duration)

    data class Billing(val allowUnpaidDevSubscriptions: Boolean)

    data class Account(val deletionGraceDays: Long, val autoVerifyEmail: Boolean = false)
}
