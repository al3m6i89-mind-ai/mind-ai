package app.nuvola.auth

import app.nuvola.common.clientIp
import jakarta.servlet.http.HttpServletRequest
import jakarta.validation.Valid
import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController

const val PASSWORD_RULE = "^(?=.*[A-Za-z])(?=.*\\d).{8,128}$"

data class RegisterRequest(
    @field:Email @field:NotBlank @field:Size(max = 320) val email: String,
    @field:Pattern(regexp = PASSWORD_RULE, message = "at least 8 characters with a letter and a digit")
    val password: String,
    @field:NotBlank @field:Size(max = 80) val displayName: String,
    val locale: String = "ar",
    val acceptTerms: Boolean = false,
)

data class LoginRequest(
    @field:NotBlank @field:Size(max = 320) val email: String,
    @field:NotBlank @field:Size(max = 128) val password: String,
)

data class RefreshRequest(@field:NotBlank val refreshToken: String)
data class TokenRequest(@field:NotBlank @field:Size(max = 200) val token: String)
data class EmailRequest(@field:Email @field:NotBlank val email: String)
data class ResetPasswordRequest(
    @field:NotBlank val token: String,
    @field:Pattern(regexp = PASSWORD_RULE, message = "at least 8 characters with a letter and a digit")
    val newPassword: String,
)

@RestController
@RequestMapping("/api/v1/auth")
class AuthController(private val auth: AuthService) {

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    fun register(@Valid @RequestBody body: RegisterRequest, req: HttpServletRequest,
                 @RequestHeader("X-Client-Label", required = false) label: String?) =
        auth.register(body.email, body.password, body.displayName, body.locale, body.acceptTerms, label, req.clientIp())

    @PostMapping("/login")
    fun login(@Valid @RequestBody body: LoginRequest, req: HttpServletRequest,
              @RequestHeader("X-Client-Label", required = false) label: String?) =
        auth.login(body.email, body.password, label, req.clientIp())

    @PostMapping("/refresh")
    fun refresh(@Valid @RequestBody body: RefreshRequest) = auth.refresh(body.refreshToken)

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun logout(@AuthenticationPrincipal user: AuthUser) = auth.logout(user.sessionId)

    @PostMapping("/verify-email")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun verify(@Valid @RequestBody body: TokenRequest) = auth.verifyEmail(body.token)

    @PostMapping("/forgot-password")
    @ResponseStatus(HttpStatus.ACCEPTED)
    fun forgot(@Valid @RequestBody body: EmailRequest) = auth.requestPasswordReset(body.email)

    @PostMapping("/reset-password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun reset(@Valid @RequestBody body: ResetPasswordRequest) = auth.resetPassword(body.token, body.newPassword)
}
