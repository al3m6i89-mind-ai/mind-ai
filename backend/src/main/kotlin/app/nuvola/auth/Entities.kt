package app.nuvola.auth

import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Id
import jakarta.persistence.Table
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import java.time.Instant
import java.util.UUID

enum class Role { USER, SUPPORT_AGENT, BILLING_ADMIN, OPERATIONS_ADMIN, SUPER_ADMIN }
enum class AccountStatus { ACTIVE, SUSPENDED, PENDING_DELETION, DELETED }

@Entity
@Table(name = "users")
class User(
    @Id val id: UUID = UUID.randomUUID(),
    var email: String,
    var passwordHash: String?,
    var displayName: String,
    var locale: String,
    var emailVerified: Boolean = false,
    @Enumerated(EnumType.STRING) var role: Role = Role.USER,
    @Enumerated(EnumType.STRING) var accountStatus: AccountStatus = AccountStatus.ACTIVE,
    var termsVersion: String,
    var termsAcceptedAt: Instant,
    var deletionRequestedAt: Instant? = null,
    val createdAt: Instant = Instant.now(),
    var updatedAt: Instant = Instant.now(),
)

interface UserRepository : JpaRepository<User, UUID> {
    @Query("select u from User u where lower(u.email) = lower(:email)")
    fun findByEmail(email: String): User?
}

@Entity
@Table(name = "user_sessions")
class UserSession(
    @Id val id: UUID = UUID.randomUUID(),
    val userId: UUID,
    var refreshTokenHash: String,
    var previousTokenHash: String? = null,
    var clientLabel: String?,
    var ipAddress: String?,
    val createdAt: Instant = Instant.now(),
    var lastUsedAt: Instant = Instant.now(),
    var expiresAt: Instant,
    var revokedAt: Instant? = null,
    var revokeReason: String? = null,
) {
    fun isActive(now: Instant) = revokedAt == null && expiresAt.isAfter(now)
}

interface UserSessionRepository : JpaRepository<UserSession, UUID> {
    fun findByRefreshTokenHash(hash: String): UserSession?
    fun findByPreviousTokenHash(hash: String): UserSession?
    fun findByUserIdAndRevokedAtIsNullOrderByLastUsedAtDesc(userId: UUID): List<UserSession>

    @Modifying
    @Query("update UserSession s set s.revokedAt = :now, s.revokeReason = :reason where s.userId = :userId and s.revokedAt is null")
    fun revokeAll(userId: UUID, now: Instant, reason: String): Int
}

enum class EmailTokenPurpose { VERIFY_EMAIL, RESET_PASSWORD }

@Entity
@Table(name = "email_tokens")
class EmailToken(
    @Id val id: UUID = UUID.randomUUID(),
    val userId: UUID,
    @Enumerated(EnumType.STRING) val purpose: EmailTokenPurpose,
    val tokenHash: String,
    val expiresAt: Instant,
    var usedAt: Instant? = null,
    val createdAt: Instant = Instant.now(),
)

interface EmailTokenRepository : JpaRepository<EmailToken, UUID> {
    fun findByTokenHash(hash: String): EmailToken?
}
