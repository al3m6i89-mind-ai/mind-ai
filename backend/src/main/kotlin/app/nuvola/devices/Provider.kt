package app.nuvola.devices

import app.nuvola.catalog.DeviceType
import app.nuvola.config.AppProperties
import org.springframework.stereotype.Component
import java.time.Duration
import java.time.Instant

data class DeviceSpec(
    val deviceType: DeviceType,
    val androidImageId: String,
    val androidVersion: String,
    val region: String,
    val cpuCores: Int,
    val ramMb: Int,
    val storageGb: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val screenDpi: Int,
    val maxFps: Int,
    val rootEnabled: Boolean,
)

enum class ProviderState { RUNNING, STOPPED, MISSING, UNKNOWN }

data class StreamConnection(val gatewayUrl: String, val token: String, val expiresAt: Instant)

/** Thrown by a provider. Retryable errors are tried again with backoff. */
open class ProviderException(message: String, val retryable: Boolean) : RuntimeException(message)
class NoCapacityException(region: String) : ProviderException("No capacity in region $region", retryable = false)

/**
 * Boundary between the product and the infrastructure that runs Android.
 * Each implementation (Redroid hosts, Anbox Cloud, a B2B vendor, physical device racks) lives behind this.
 */
interface CloudDeviceProvider {
    val id: String
    /** True when devices are not real Android systems. Shown to users and blocked in production. */
    val simulated: Boolean
    val supportsStreaming: Boolean

    /** Allocates resources, boots the image and returns the provider's reference. Device is running afterwards. */
    fun create(spec: DeviceSpec): String
    fun start(ref: String)
    fun stop(ref: String)
    fun restart(ref: String)
    fun destroy(ref: String)
    /** Applies the root setting; the provider restarts Android if needed and returns it in its previous power state. */
    fun setRoot(ref: String, enabled: Boolean)
    fun state(ref: String): ProviderState
    fun issueConnection(ref: String, ttl: Duration): StreamConnection
}

@Component
class ProviderRegistry(providers: List<CloudDeviceProvider>, private val props: AppProperties) {
    private val byId = providers.associateBy { it.id }

    fun active(): CloudDeviceProvider = byId[props.devices.provider]
        ?: error("Unknown device provider '${props.devices.provider}'. Installed: ${byId.keys}")

    fun get(id: String): CloudDeviceProvider = byId[id] ?: error("Provider '$id' is not installed on this server")
}
