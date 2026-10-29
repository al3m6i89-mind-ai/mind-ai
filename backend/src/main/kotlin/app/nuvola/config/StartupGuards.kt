package app.nuvola.config

import jakarta.annotation.PostConstruct
import org.springframework.stereotype.Component

/** Refuses to boot a production server with development shortcuts switched on. */
@Component
class StartupGuards(private val props: AppProperties) {
    @PostConstruct
    fun check() {
        if (props.devices.provider == "redroid") {
            check(props.devices.redroid.nodeUrl.isNotBlank() && props.devices.redroid.nodeToken.length >= 32) {
                "DEVICE_PROVIDER=redroid needs REDROID_NODE_URL and REDROID_NODE_TOKEN (printed by the node install script)"
            }
        }
        if (!props.isProduction) return
        val problems = buildList {
            if (props.devices.provider == "mock") add("DEVICE_PROVIDER=mock is not allowed in production")
            if (props.billing.allowUnpaidDevSubscriptions) add("unpaid dev subscriptions are not allowed in production")
            if (props.security.jwtSecret.startsWith("dev-only") || props.security.jwtSecret.length < 32) {
                add("JWT_SECRET must be set to a random value of at least 32 characters")
            }
            if (props.mail.transport == "log") add("MAIL_TRANSPORT=log is not allowed in production")
            if (props.account.autoVerifyEmail) add("auto-verified email is not allowed in production")
        }
        check(problems.isEmpty()) { "Unsafe production configuration: ${problems.joinToString("; ")}" }
    }
}
