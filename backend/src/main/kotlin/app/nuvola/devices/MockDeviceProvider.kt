package app.nuvola.devices

import app.nuvola.config.AppProperties
import org.springframework.stereotype.Component
import java.time.Duration
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Development-only provider. It does not run Android: it only walks devices through
 * lifecycle states with a delay so the app and backend can be built and tested.
 * StartupGuards refuses to start production with this provider selected.
 */
@Component
class MockDeviceProvider(private val props: AppProperties) : CloudDeviceProvider {
    override val id = "mock"
    override val simulated = true
    override val supportsStreaming = false

    private val states = ConcurrentHashMap<String, ProviderState>()

    override fun create(spec: DeviceSpec): String {
        pause(3)
        val ref = "mock-${UUID.randomUUID()}"
        states[ref] = ProviderState.RUNNING
        return ref
    }

    override fun start(ref: String) = transition(ref, ProviderState.RUNNING)
    override fun stop(ref: String) = transition(ref, ProviderState.STOPPED)
    override fun restart(ref: String) = transition(ref, ProviderState.RUNNING, steps = 2)

    override fun destroy(ref: String) {
        pause(1)
        states.remove(ref)
    }

    override fun setRoot(ref: String, enabled: Boolean) {
        val before = state(ref)
        pause(2)
        states[ref] = before
    }

    override fun state(ref: String) = states[ref] ?: ProviderState.MISSING

    override fun issueConnection(ref: String, ttl: Duration): StreamConnection =
        throw ProviderException("The development provider has no screen to stream", retryable = false)

    private fun transition(ref: String, to: ProviderState, steps: Int = 1) {
        // After a server restart the in-memory map is empty; treat known refs as recoverable.
        pause(steps)
        states[ref] = to
    }

    private fun pause(steps: Int) = Thread.sleep(props.devices.mockStepDelay.toMillis() * steps)
}
