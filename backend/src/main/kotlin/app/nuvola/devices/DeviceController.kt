package app.nuvola.devices

import app.nuvola.auth.AuthUser
import app.nuvola.common.ApiException
import app.nuvola.common.ErrorCode
import app.nuvola.common.Tokens
import app.nuvola.config.AppProperties
import app.nuvola.billing.SubscriptionRepository
import app.nuvola.catalog.PlanRepository
import app.nuvola.common.AuditService
import app.nuvola.common.notFound
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.Duration
import java.time.Instant
import java.util.UUID

data class CreateDeviceRequest(
    val subscriptionId: UUID,
    @field:NotBlank val androidImageId: String,
    @field:NotBlank val regionId: String,
    @field:NotBlank @field:Size(max = 60) val displayName: String,
    val rootEnabled: Boolean = false,
)

data class RenameRequest(@field:NotBlank @field:Size(max = 60) val displayName: String)
data class RootRequest(val enabled: Boolean)

data class SessionDto(val sessionId: UUID, val gatewayUrl: String, val token: String, val expiresAt: Instant)

@RestController
@RequestMapping("/api/v1")
class DeviceController(private val service: DeviceService, private val sessions: DeviceSessionService) {

    @GetMapping("/dashboard")
    fun dashboard(@AuthenticationPrincipal u: AuthUser) = service.dashboard(u.userId)

    @GetMapping("/devices")
    fun list(@AuthenticationPrincipal u: AuthUser) = service.list(u.userId)

    @PostMapping("/devices")
    fun create(
        @AuthenticationPrincipal u: AuthUser,
        @RequestHeader("Idempotency-Key") key: String,
        @Valid @RequestBody body: CreateDeviceRequest,
    ): ResponseEntity<DeviceDto> {
        if (!key.matches(Regex("^[A-Za-z0-9-]{8,80}$"))) {
            throw ApiException(ErrorCode.IDEMPOTENCY_KEY_REQUIRED, "Idempotency-Key must be 8-80 letters, digits or dashes")
        }
        val (dto, created) = service.create(u.userId,
            CreateDeviceCommand(body.subscriptionId, body.androidImageId, body.regionId, body.displayName, body.rootEnabled), key)
        return ResponseEntity.status(if (created) HttpStatus.ACCEPTED else HttpStatus.OK).body(dto)
    }

    @GetMapping("/devices/{id}")
    fun get(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = service.get(u.userId, id)

    @PatchMapping("/devices/{id}")
    fun rename(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID, @Valid @RequestBody body: RenameRequest) =
        service.rename(u.userId, id, body.displayName)

    @PostMapping("/devices/{id}/start")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun start(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = service.start(u.userId, id)

    @PostMapping("/devices/{id}/stop")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun stop(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = service.stop(u.userId, id)

    @PostMapping("/devices/{id}/restart")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun restart(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = service.restart(u.userId, id)

    @PostMapping("/devices/{id}/root")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun root(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID, @RequestBody body: RootRequest) =
        service.setRoot(u.userId, id, body.enabled)

    @DeleteMapping("/devices/{id}")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun delete(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = service.delete(u.userId, id)

    @PostMapping("/devices/{id}/sessions")
    @ResponseStatus(HttpStatus.CREATED)
    fun openSession(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = sessions.open(u.userId, id)

    @DeleteMapping("/sessions/{sessionId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun closeSession(@AuthenticationPrincipal u: AuthUser, @PathVariable sessionId: UUID) = sessions.close(u.userId, sessionId)
}

@Service
class DeviceSessionService(
    private val devices: DeviceService,
    private val subs: SubscriptionRepository,
    private val plans: PlanRepository,
    private val repo: DeviceSessionRepository,
    private val providers: ProviderRegistry,
    private val props: AppProperties,
    private val audit: AuditService,
) {
    /** Checks ownership, subscription, state and limits, then asks the provider for a short-lived stream ticket. */
    @Transactional
    fun open(userId: UUID, deviceId: UUID): SessionDto {
        val d = devices.owned(userId, deviceId)
        val sub = subs.findById(d.subscriptionId).orElseThrow()
        if (!sub.isActiveAt(Instant.now())) throw ApiException(ErrorCode.SUBSCRIPTION_EXPIRED, "Renew your subscription to open this phone")
        if (d.lifecycleStatus != LifecycleStatus.RUNNING) {
            throw ApiException(ErrorCode.INVALID_DEVICE_STATE, "Start the phone before opening it")
        }
        val plan = plans.findById(sub.planId).orElseThrow()
        if (repo.countOpen(userId, Instant.now().minus(Duration.ofMinutes(2))) >= plan.concurrentSessionLimit) {
            throw ApiException(ErrorCode.CONCURRENT_SESSION_LIMIT_REACHED, "Close another open phone first")
        }
        val provider = providers.get(d.providerId)
        if (!provider.supportsStreaming) {
            throw ApiException(ErrorCode.STREAMING_NOT_AVAILABLE, "Screen streaming is not connected on this server yet")
        }
        val conn = try {
            provider.issueConnection(d.providerDeviceRef!!, props.streaming.sessionTokenTtl)
        } catch (e: ProviderException) {
            throw ApiException(ErrorCode.STREAMING_NOT_AVAILABLE, "Could not start the stream. Try again")
        }
        val session = repo.save(DeviceSession(userId = userId, cloudDeviceId = d.id,
            tokenHash = Tokens.sha256(conn.token), tokenExpiresAt = conn.expiresAt))
        audit.user(userId, "device.session_opened", "cloud_device", d.id, mapOf("session" to session.id))
        return SessionDto(session.id, conn.gatewayUrl, conn.token, conn.expiresAt)
    }

    @Transactional
    fun close(userId: UUID, sessionId: UUID) {
        val s = repo.findById(sessionId).filter { it.userId == userId }.orElse(null) ?: notFound("Session")
        if (s.endedAt == null) {
            s.endedAt = Instant.now()
            s.connectionStatus = ConnectionStatus.ENDED
        }
    }
}
