package app.nuvola.account

import app.nuvola.auth.AccountStatus
import app.nuvola.auth.AuthService
import app.nuvola.auth.AuthUser
import app.nuvola.auth.PASSWORD_RULE
import app.nuvola.auth.UserRepository
import app.nuvola.auth.UserSessionRepository
import app.nuvola.common.AuditService
import app.nuvola.common.notFound
import app.nuvola.config.AppProperties
import app.nuvola.devices.CloudDeviceRepository
import app.nuvola.devices.DeviceService
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.Duration
import java.time.Instant
import java.util.UUID

data class MeDto(
    val id: UUID,
    val email: String,
    val displayName: String,
    val locale: String,
    val emailVerified: Boolean,
    val role: String,
    val accountStatus: AccountStatus,
    val deletionScheduledFor: Instant?,
    val createdAt: Instant,
)

data class UpdateMeRequest(
    @field:Size(min = 1, max = 80) val displayName: String? = null,
    @field:Pattern(regexp = "^(ar|en)$") val locale: String? = null,
)

data class ChangePasswordRequest(
    @field:NotBlank val currentPassword: String,
    @field:Pattern(regexp = PASSWORD_RULE, message = "at least 8 characters with a letter and a digit")
    val newPassword: String,
)

data class LoginSessionDto(val id: UUID, val clientLabel: String?, val createdAt: Instant, val lastUsedAt: Instant, val current: Boolean)

@Service
class AccountService(
    private val users: UserRepository,
    private val sessions: UserSessionRepository,
    private val devices: CloudDeviceRepository,
    private val deviceService: DeviceService,
    private val audit: AuditService,
    private val props: AppProperties,
) {
    fun me(userId: UUID): MeDto {
        val u = users.findById(userId).orElseThrow()
        return MeDto(u.id, u.email, u.displayName, u.locale, u.emailVerified, u.role.name, u.accountStatus,
            u.deletionRequestedAt?.plus(Duration.ofDays(props.account.deletionGraceDays)), u.createdAt)
    }

    @Transactional
    fun update(userId: UUID, req: UpdateMeRequest): MeDto {
        val u = users.findById(userId).orElseThrow()
        req.displayName?.let { u.displayName = it.trim() }
        req.locale?.let { u.locale = it }
        u.updatedAt = Instant.now()
        return me(userId)
    }

    /**
     * Deletion request: signs out everywhere and stops devices now. After the grace period the
     * account is anonymised and devices destroyed. Payment and invoice records are kept as the law requires.
     */
    @Transactional
    fun requestDeletion(userId: UUID) {
        val u = users.findById(userId).orElseThrow()
        val now = Instant.now()
        u.accountStatus = AccountStatus.PENDING_DELETION
        u.deletionRequestedAt = now
        u.updatedAt = now
        sessions.revokeAll(userId, now, "account_deletion")
        devices.findByOwnerUserIdAndDeletedAtIsNullOrderByCreatedAt(userId).forEach { deviceService.systemStop(it, "ACCOUNT_DELETION") }
        audit.user(userId, "account.deletion_requested", "user", userId)
    }

    fun sessions(userId: UUID, current: UUID) =
        sessions.findByUserIdAndRevokedAtIsNullOrderByLastUsedAtDesc(userId)
            .filter { it.expiresAt.isAfter(Instant.now()) }
            .map { LoginSessionDto(it.id, it.clientLabel, it.createdAt, it.lastUsedAt, it.id == current) }

    @Transactional
    fun revokeSession(userId: UUID, id: UUID) {
        val s = sessions.findById(id).filter { it.userId == userId }.orElse(null) ?: notFound("Session")
        if (s.revokedAt == null) {
            s.revokedAt = Instant.now()
            s.revokeReason = "revoked_by_user"
        }
    }

    @Scheduled(fixedDelay = 3_600_000, initialDelay = 60_000)
    @Transactional
    fun finishDeletions() {
        val cutoff = Instant.now().minus(Duration.ofDays(props.account.deletionGraceDays))
        users.findAll().filter {
            it.accountStatus == AccountStatus.PENDING_DELETION && it.deletionRequestedAt?.isBefore(cutoff) == true
        }.forEach { u ->
            devices.findByOwnerUserIdAndDeletedAtIsNullOrderByCreatedAt(u.id).forEach { deviceService.systemDestroy(it, "ACCOUNT_DELETED") }
            u.email = "deleted-${u.id}@deleted.invalid"
            u.displayName = "Deleted user"
            u.passwordHash = null
            u.accountStatus = AccountStatus.DELETED
            u.updatedAt = Instant.now()
            audit.system("account.deleted", "user", u.id)
        }
    }
}

@RestController
@RequestMapping("/api/v1/me")
class MeController(private val account: AccountService, private val auth: AuthService) {
    @GetMapping
    fun me(@AuthenticationPrincipal u: AuthUser) = account.me(u.userId)

    @PatchMapping
    fun update(@AuthenticationPrincipal u: AuthUser, @Valid @RequestBody body: UpdateMeRequest) = account.update(u.userId, body)

    @DeleteMapping
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun delete(@AuthenticationPrincipal u: AuthUser) = account.requestDeletion(u.userId)

    @PostMapping("/resend-verification")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun resend(@AuthenticationPrincipal u: AuthUser) = auth.resendVerification(u.userId)

    @PostMapping("/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun password(@AuthenticationPrincipal u: AuthUser, @Valid @RequestBody body: ChangePasswordRequest) =
        auth.changePassword(u.userId, u.sessionId, body.currentPassword, body.newPassword)

    @GetMapping("/sessions")
    fun sessions(@AuthenticationPrincipal u: AuthUser) = account.sessions(u.userId, u.sessionId)

    @DeleteMapping("/sessions/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun revoke(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = account.revokeSession(u.userId, id)
}
