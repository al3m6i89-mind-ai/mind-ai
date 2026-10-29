package app.nuvola.devices

import app.nuvola.config.AppProperties
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.stereotype.Component
import java.io.IOException
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.time.Instant
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Real Android phones on a server running the Nuvola node agent (Redroid containers).
 * Lifecycle calls go to the agent's HTTP API; phone apps stream straight from the node
 * with a ticket signed here, so video never passes through this backend.
 */
@Component
class RedroidProvider(private val props: AppProperties, private val mapper: ObjectMapper) : CloudDeviceProvider {
    override val id = "redroid"
    override val simulated = false
    override val supportsStreaming = true

    private val node get() = props.devices.redroid
    private val http: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build()

    override fun create(spec: DeviceSpec): String {
        val body = mapOf(
            "version" to spec.androidVersion, "root" to spec.rootEnabled,
            "cpus" to spec.cpuCores, "ramMb" to spec.ramMb,
            "width" to spec.screenWidth, "height" to spec.screenHeight, "dpi" to spec.screenDpi, "fps" to spec.maxFps,
        )
        return call("POST", "/v1/devices", body)["ref"] as String
    }

    override fun start(ref: String) { call("POST", "/v1/devices/$ref/start") }
    override fun stop(ref: String) { call("POST", "/v1/devices/$ref/stop") }
    override fun restart(ref: String) { call("POST", "/v1/devices/$ref/restart") }
    override fun destroy(ref: String) { call("DELETE", "/v1/devices/$ref") }
    override fun setRoot(ref: String, enabled: Boolean) { call("POST", "/v1/devices/$ref/root", mapOf("enabled" to enabled)) }

    override fun state(ref: String): ProviderState =
        runCatching { ProviderState.valueOf(call("GET", "/v1/devices/$ref")["state"] as String) }.getOrDefault(ProviderState.UNKNOWN)

    override fun issueConnection(ref: String, ttl: Duration): StreamConnection {
        val expiresAt = Instant.now().plus(ttl)
        val gateway = node.nodeUrl.trimEnd('/').replaceFirst("https://", "wss://").replaceFirst("http://", "ws://")
        return StreamConnection("$gateway/v1/stream/$ref", ticket(ref, expiresAt), expiresAt)
    }

    /** Same format the agent verifies: "v1.<ref>.<unix expiry>.<base64url HMAC-SHA256>". */
    internal fun ticket(ref: String, expiresAt: Instant): String {
        val payload = "v1.$ref.${expiresAt.epochSecond}"
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(node.nodeToken.toByteArray(), "HmacSHA256")) }
        return payload + "." + Base64.getUrlEncoder().withoutPadding().encodeToString(mac.doFinal(payload.toByteArray()))
    }

    private fun call(method: String, path: String, body: Any? = null): Map<String, Any?> {
        val request = HttpRequest.newBuilder(URI.create(node.nodeUrl.trimEnd('/') + path))
            .timeout(node.requestTimeout)
            .header("Authorization", "Bearer ${node.nodeToken}")
            .header("Content-Type", "application/json")
            .method(method, body?.let { HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(it)) }
                ?: HttpRequest.BodyPublishers.noBody())
            .build()
        val response = try {
            http.send(request, HttpResponse.BodyHandlers.ofString())
        } catch (e: IOException) {
            throw ProviderException("Phone server unreachable: ${e.message}", retryable = true)
        }
        @Suppress("UNCHECKED_CAST")
        val json = runCatching { mapper.readValue(response.body(), Map::class.java) as Map<String, Any?> }.getOrDefault(emptyMap())
        val status = response.statusCode()
        if (status == 200) return json
        val message = "Phone server: ${json["error"] ?: status} ${json["message"] ?: ""}".trim()
        throw when {
            json["error"] == "no_capacity" -> ProviderException(message, retryable = false)
            status == 504 || status >= 500 -> ProviderException(message, retryable = true)
            else -> ProviderException(message, retryable = false)
        }
    }
}
