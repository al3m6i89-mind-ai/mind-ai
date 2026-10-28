package app.nuvola.common

import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.MissingRequestHeaderException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException
import org.springframework.web.servlet.resource.NoResourceFoundException
import java.util.UUID

data class ErrorBody(val error: ErrorDetail)
data class ErrorDetail(
    val code: String,
    val message: String,
    val referenceId: String? = null,
    val fields: Map<String, String>? = null,
)

@RestControllerAdvice
class ErrorHandler {
    private val log = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(ApiException::class)
    fun api(e: ApiException) = respond(e.code, e.message)

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun validation(e: MethodArgumentNotValidException): ResponseEntity<ErrorBody> {
        val fields = e.bindingResult.fieldErrors.associate { it.field to (it.defaultMessage ?: "invalid") }
        return respond(ErrorCode.VALIDATION_FAILED, "Some fields are invalid", fields = fields)
    }

    @ExceptionHandler(HttpMessageNotReadableException::class, MethodArgumentTypeMismatchException::class)
    fun unreadable(e: Exception) = respond(ErrorCode.VALIDATION_FAILED, "Request body or parameters are malformed")

    @ExceptionHandler(MissingRequestHeaderException::class)
    fun missingHeader(e: MissingRequestHeaderException) =
        if (e.headerName.equals("Idempotency-Key", ignoreCase = true)) {
            respond(ErrorCode.IDEMPOTENCY_KEY_REQUIRED, "Idempotency-Key header is required")
        } else {
            respond(ErrorCode.VALIDATION_FAILED, "Missing header ${e.headerName}")
        }

    @ExceptionHandler(NoResourceFoundException::class)
    fun noResource(e: NoResourceFoundException) = respond(ErrorCode.NOT_FOUND, "Not found")

    @ExceptionHandler(Exception::class)
    fun unexpected(e: Exception): ResponseEntity<ErrorBody> {
        val ref = UUID.randomUUID().toString().substring(0, 8).uppercase()
        log.error("Unhandled error ref={}", ref, e)
        return respond(ErrorCode.INTERNAL_ERROR, "Something went wrong on our side", ref)
    }

    private fun respond(
        code: ErrorCode,
        message: String,
        ref: String? = null,
        fields: Map<String, String>? = null,
    ) = ResponseEntity.status(code.status).body(ErrorBody(ErrorDetail(code.name, message, ref, fields)))
}
