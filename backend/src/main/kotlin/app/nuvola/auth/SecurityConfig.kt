package app.nuvola.auth

import app.nuvola.common.ErrorBody
import app.nuvola.common.ErrorCode
import app.nuvola.common.ErrorDetail
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.core.convert.converter.Converter
import org.springframework.http.HttpMethod
import org.springframework.security.authentication.AbstractAuthenticationToken
import org.springframework.security.authentication.BadCredentialsException
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.invoke
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.oauth2.jwt.Jwt
import org.springframework.security.web.AuthenticationEntryPoint
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.access.AccessDeniedHandler
import java.time.Instant
import java.util.UUID

/** The authenticated caller. Every controller reads identity from here, never from request bodies. */
data class AuthUser(val userId: UUID, val sessionId: UUID, val role: Role)

class UserAuthenticationToken(private val user: AuthUser, private val jwt: Jwt) :
    AbstractAuthenticationToken(listOf(SimpleGrantedAuthority("ROLE_${user.role.name}"))) {
    init { isAuthenticated = true }
    override fun getCredentials() = jwt.tokenValue
    override fun getPrincipal() = user
    override fun getName() = user.userId.toString()
}

@Configuration
class SecurityConfig(
    private val jwtService: JwtService,
    private val sessions: UserSessionRepository,
    private val users: UserRepository,
    private val mapper: ObjectMapper,
) {
    @Bean
    fun passwordEncoder(): PasswordEncoder = BCryptPasswordEncoder(12)

    @Bean
    fun filterChain(http: HttpSecurity): SecurityFilterChain {
        http {
            csrf { disable() }
            cors { }
            sessionManagement { sessionCreationPolicy = SessionCreationPolicy.STATELESS }
            authorizeHttpRequests {
                authorize(HttpMethod.GET, "/api/v1/health", permitAll)
                authorize(HttpMethod.GET, "/api/v1/app-config", permitAll)
                authorize(HttpMethod.GET, "/api/v1/plans", permitAll)
                authorize(HttpMethod.GET, "/api/v1/catalog", permitAll)
                authorize("/api/v1/auth/logout", authenticated)
                authorize("/api/v1/auth/**", permitAll)
                authorize(HttpMethod.POST, "/api/v1/nodes/heartbeat", permitAll) // checks X-Node-Token itself
                authorize("/api/v1/openapi/**", permitAll)
                authorize("/api/v1/docs/**", permitAll)
                authorize("/swagger-ui/**", permitAll)
                authorize("/actuator/health/**", permitAll)
                authorize("/api/v1/**", authenticated)
                authorize(anyRequest, denyAll)
            }
            oauth2ResourceServer {
                jwt {
                    jwtDecoder = jwtService.decoder
                    jwtAuthenticationConverter = sessionAwareConverter()
                }
                authenticationEntryPoint = entryPoint()
            }
            exceptionHandling {
                authenticationEntryPoint = entryPoint()
                accessDeniedHandler = deniedHandler()
            }
        }
        return http.build()
    }

    /** Rejects tokens whose login session was revoked (logout, password reset, suspected compromise). */
    private fun sessionAwareConverter() = Converter<Jwt, AbstractAuthenticationToken> { jwt ->
        val sid = runCatching { UUID.fromString(jwt.getClaimAsString("sid")) }.getOrNull()
            ?: throw BadCredentialsException("missing session")
        val session = sessions.findById(sid).orElse(null)
        if (session == null || !session.isActive(Instant.now())) throw BadCredentialsException("session revoked")
        val user = users.findById(session.userId).orElse(null)
        if (user == null || user.accountStatus == AccountStatus.DELETED || user.accountStatus == AccountStatus.SUSPENDED) {
            throw BadCredentialsException("account unavailable")
        }
        UserAuthenticationToken(AuthUser(user.id, sid, user.role), jwt)
    }

    private fun entryPoint() = AuthenticationEntryPoint { _, response, _ ->
        response.status = 401
        response.contentType = "application/json"
        mapper.writeValue(response.outputStream,
            ErrorBody(ErrorDetail(ErrorCode.UNAUTHENTICATED.name, "Sign in again to continue")))
    }

    private fun deniedHandler() = AccessDeniedHandler { _, response, _ ->
        response.status = 403
        response.contentType = "application/json"
        mapper.writeValue(response.outputStream,
            ErrorBody(ErrorDetail(ErrorCode.FORBIDDEN.name, "You do not have access to this")))
    }
}
