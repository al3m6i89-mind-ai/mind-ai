package app.nuvola.common

import org.springframework.http.HttpStatus

/** Stable error codes. The app maps each code to a translated message. */
enum class ErrorCode(val status: HttpStatus) {
    VALIDATION_FAILED(HttpStatus.BAD_REQUEST),
    IDEMPOTENCY_KEY_REQUIRED(HttpStatus.BAD_REQUEST),
    UNAUTHENTICATED(HttpStatus.UNAUTHORIZED),
    INVALID_CREDENTIALS(HttpStatus.UNAUTHORIZED),
    SESSION_EXPIRED(HttpStatus.UNAUTHORIZED),
    FORBIDDEN(HttpStatus.FORBIDDEN),
    ACCOUNT_SUSPENDED(HttpStatus.FORBIDDEN),
    EMAIL_NOT_VERIFIED(HttpStatus.FORBIDDEN),
    NOT_FOUND(HttpStatus.NOT_FOUND),
    EMAIL_ALREADY_REGISTERED(HttpStatus.CONFLICT),
    TERMS_NOT_ACCEPTED(HttpStatus.BAD_REQUEST),
    INVALID_TOKEN(HttpStatus.BAD_REQUEST),
    TOO_MANY_ATTEMPTS(HttpStatus.TOO_MANY_REQUESTS),
    SUBSCRIPTION_REQUIRED(HttpStatus.PAYMENT_REQUIRED),
    SUBSCRIPTION_EXPIRED(HttpStatus.PAYMENT_REQUIRED),
    PAYMENT_REQUIRED(HttpStatus.PAYMENT_REQUIRED),
    DEVICE_LIMIT_REACHED(HttpStatus.CONFLICT),
    CONCURRENT_SESSION_LIMIT_REACHED(HttpStatus.CONFLICT),
    DEVICE_BUSY(HttpStatus.CONFLICT),
    INVALID_DEVICE_STATE(HttpStatus.CONFLICT),
    ROOT_NOT_ALLOWED(HttpStatus.CONFLICT),
    IMAGE_NOT_AVAILABLE(HttpStatus.CONFLICT),
    REGION_NOT_AVAILABLE(HttpStatus.CONFLICT),
    NO_CAPACITY(HttpStatus.SERVICE_UNAVAILABLE),
    STREAMING_NOT_AVAILABLE(HttpStatus.SERVICE_UNAVAILABLE),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR),
}

class ApiException(val code: ErrorCode, override val message: String) : RuntimeException(message)

fun notFound(what: String): Nothing = throw ApiException(ErrorCode.NOT_FOUND, "$what not found")
