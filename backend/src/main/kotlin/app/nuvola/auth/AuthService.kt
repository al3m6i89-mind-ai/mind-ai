package app.nuvola.auth

import app.nuvola.common.ApiException
import app.nuvola.common.AuditService
import app.nuvola.common.ErrorCode
import app.nuvola.common.RateLimiter
import app.nuvola.common.Tokens
import app.nuvola.config.AppProperties
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Duration
import java.time.Instant
import java.util.UUID

data class TokenPair(
    val accessToken: String,
    val accessTokenExpiresAt: Instant,
    val refreshToken: String,
    val refreshTokenExpiresAt: Instant,
    val sessionId: UUID,
)

@Service
class AuthService(
    private val props: AppProperties,
    private val users: UserRepository,
    private val sessions: UserSessionRepository,
    private val emailTokens: EmailTokenRepository,
    private val passwords: PasswordEncoder,
    private val jwt: JwtService,
    private val mailer: Mailer,
    private val audit: AuditService,
) {
    private val emailLimiter = RateLimiter(props.security.loginAttemptsPerEmail, props.security.loginWindow)
    private val ipLimiter = RateLimiter(props.security.loginAttemptsPerIp, props.security.loginWindow)
    private val mailLimiter = RateLimiter(3, Duration.ofMinutes(15))

    // Compared against when the email is unknown, so response time does not reveal which emails exist.
    private val dummyHash = passwords.encode(Tokens.newToken())

    @Transactional
    fun register(email: String, password: String, displayName: String, locale: String, acceptedTerms: Boolean,
                 clientLabel: String?, ip: String): TokenPair {
        if (!acceptedTerms) throw ApiException(ErrorCode.TERMS_NOT_ACCEPTED, "Accept the terms of use to continue")
        val normalized = email.trim().lowercase()
        if (users.findByEmail(normalized) != null) {
            throw ApiException(ErrorCode.EMAIL_ALREADY_REGISTERED, "This email already has an account")
        }
        val now = Instant.now()
        val user = users.save(User(
            email = normalized,
            passwordHash = passwords.encode(password),
            displayName = displayName.trim(),
            locale = if (locale == "en") "en" else "ar",
            termsVersion = props.termsVersion,
            termsAcceptedAt = now,
        ))
        audit.user(user.id, "account.registered", "user", user.id)
        sendVerification(user)
        return openSession(user, clientLabel, ip)
    }

    @Transactional
    fun login(email: String, password: String, clientLabel: String?, ip: String): TokenPair {
        val key = email.trim().lowercase()
        if (emailLimiter.isBlocked(key) || ipLimiter.isBlocked(ip)) {
            throw ApiException(ErrorCode.TOO_MANY_ATTEMPTS, "Too many sign-in attempts. Try again in a few minutes")
        }
        val user = users.findByEmail(key)
        val ok = passwords.matches(password, user?.passwordHash ?: dummyHash) && user?.passwordHash != null
        if (!ok || user == null || user.accountStatus == AccountStatus.DELETED) {
            emailLimiter.record(key)
            ipLimiter.record(ip)
            throw ApiException(ErrorCode.INVALID_CREDENTIALS, "Email or password is incorrect")
        }
        if (user.accountStatus == AccountStatus.SUSPENDED) {
            throw ApiException(ErrorCode.ACCOUNT_SUSPENDED, "This account is suspended. Contact support")
        }
        emailLimiter.reset(key)
        if (user.accountStatus == AccountStatus.PENDING_DELETION) {
            // Signing in during the grace period cancels the deletion request.
            user.accountStatus = AccountStatus.ACTIVE
            user.deletionRequestedAt = null
            audit.user(user.id, "account.deletion_canceled", "user", user.id)
        }
        audit.user(user.id, "auth.login", "user", user.id, mapOf("ip" to ip))
        return openSession(user, clientLabel, ip)
    }

    // The reuse revocation must commit even though the call itself is rejected.
    @Transactional(noRollbackFor = [ApiException::class])
    fun refresh(refreshToken: String): TokenPair {
        val hash = Tokens.sha256(refreshToken)
        val now = Instant.now()
        val session = sessions.findByRefreshTokenHash(hash)
        if (session == null) {
            // A rotated-out token came back: someone else may hold a copy. End every session.
            sessions.findByPreviousTokenHash(hash)?.let { stolen ->
                sessions.revokeAll(stolen.userId, now, "refresh_token_reuse")
                audit.system("auth.refresh_reuse_detected", "user", stolen.userId)
            }
            throw ApiException(ErrorCode.SESSION_EXPIRED, "Sign in again to continue")
        }
        if (!session.isActive(now)) throw ApiException(ErrorCode.SESSION_EXPIRED, "Sign in again to continue")
        val user = users.findById(session.userId).orElseThrow()
        if (user.accountStatus != AccountStatus.ACTIVE) {
            throw ApiException(ErrorCode.SESSION_EXPIRED, "Sign in again to continue")
        }
        val newRefresh = Tokens.newToken()
        session.previousTokenHash = session.refreshTokenHash
        session.refreshTokenHash = Tokens.sha256(newRefresh)
        session.lastUsedAt = now
        val (access, accessExp) = jwt.issueAccessToken(user, session.id)
        return TokenPair(access, accessExp, newRefresh, session.expiresAt, session.id)
    }

    @Transactional
    fun logout(sessionId: UUID) {
        sessions.findById(sessionId).ifPresent {
            if (it.revokedAt == null) {
                it.revokedAt = Instant.now()
                it.revokeReason = "logout"
            }
        }
    }

    @Transactional
    fun verifyEmail(token: String) {
        val t = consumeToken(token, EmailTokenPurpose.VERIFY_EMAIL)
        val user = users.findById(t.userId).orElseThrow()
        user.emailVerified = true
        user.updatedAt = Instant.now()
        audit.user(user.id, "account.email_verified", "user", user.id)
    }

    @Transactional
    fun resendVerification(userId: UUID) {
        val user = users.findById(userId).orElseThrow()
        if (user.emailVerified) return
        if (mailLimiter.isBlocked(user.id.toString())) {
            throw ApiException(ErrorCode.TOO_MANY_ATTEMPTS, "Wait a few minutes before asking for another email")
        }
        mailLimiter.record(user.id.toString())
        sendVerification(user)
    }

    /** Always succeeds from the caller's view, so it cannot be used to discover registered emails. */
    @Transactional
    fun requestPasswordReset(email: String) {
        val user = users.findByEmail(email.trim()) ?: return
        if (user.accountStatus == AccountStatus.DELETED || mailLimiter.isBlocked("reset:${user.id}")) return
        mailLimiter.record("reset:${user.id}")
        val token = createToken(user.id, EmailTokenPurpose.RESET_PASSWORD, Duration.ofMinutes(30))
        mailer.send(user.email, "Reset your password",
            "Use this code in the app to set a new password (valid for 30 minutes):\n\n$token\n\n" +
                "If you did not ask for this, you can ignore this email.")
    }

    @Transactional
    fun resetPassword(token: String, newPassword: String) {
        val t = consumeToken(token, EmailTokenPurpose.RESET_PASSWORD)
        val user = users.findById(t.userId).orElseThrow()
        user.passwordHash = passwords.encode(newPassword)
        user.emailVerified = true
        user.updatedAt = Instant.now()
        sessions.revokeAll(user.id, Instant.now(), "password_reset")
        audit.user(user.id, "account.password_reset", "user", user.id)
    }

    @Transactional
    fun changePassword(userId: UUID, currentSessionId: UUID, current: String, newPassword: String) {
        val user = users.findById(userId).orElseThrow()
        if (user.passwordHash == null || !passwords.matches(current, user.passwordHash)) {
            throw ApiException(ErrorCode.INVALID_CREDENTIALS, "Current password is incorrect")
        }
        user.passwordHash = passwords.encode(newPassword)
        user.updatedAt = Instant.now()
        // Keep this device signed in, end every other session.
        val now = Instant.now()
        sessions.findByUserIdAndRevokedAtIsNullOrderByLastUsedAtDesc(userId)
            .filter { it.id != currentSessionId }
            .forEach { it.revokedAt = now; it.revokeReason = "password_changed" }
        audit.user(user.id, "account.password_changed", "user", user.id)
    }

    private fun openSession(user: User, clientLabel: String?, ip: String): TokenPair {
        val refresh = Tokens.newToken()
        val session = sessions.save(UserSession(
            userId = user.id,
            refreshTokenHash = Tokens.sha256(refresh),
            clientLabel = clientLabel?.take(120),
            ipAddress = ip,
            expiresAt = Instant.now().plus(props.security.refreshTokenTtl),
        ))
        val (access, accessExp) = jwt.issueAccessToken(user, session.id)
        return TokenPair(access, accessExp, refresh, session.expiresAt, session.id)
    }

    private fun sendVerification(user: User) {
        val token = createToken(user.id, EmailTokenPurpose.VERIFY_EMAIL, Duration.ofHours(24))
        mailer.send(user.email, "Confirm your email",
            "Enter this code in the app to confirm your email (valid for 24 hours):\n\n$token")
    }

    private fun createToken(userId: UUID, purpose: EmailTokenPurpose, ttl: Duration): String {
        val token = Tokens.newToken()
        emailTokens.save(EmailToken(userId = userId, purpose = purpose, tokenHash = Tokens.sha256(token),
            expiresAt = Instant.now().plus(ttl)))
        return token
    }

    private fun consumeToken(token: String, purpose: EmailTokenPurpose): EmailToken {
        val t = emailTokens.findByTokenHash(Tokens.sha256(token.trim()))
        val now = Instant.now()
        if (t == null || t.purpose != purpose || t.usedAt != null || t.expiresAt.isBefore(now)) {
            throw ApiException(ErrorCode.INVALID_TOKEN, "This code is invalid or has expired")
        }
        t.usedAt = now
        return t
    }
}
