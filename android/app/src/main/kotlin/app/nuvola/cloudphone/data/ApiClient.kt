package app.nuvola.cloudphone.data

import android.os.Build
import app.nuvola.cloudphone.BuildConfig
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import okhttp3.Authenticator
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import java.io.IOException
import java.util.concurrent.TimeUnit

val json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}

class ApiClient(private val tokens: TokenStore) {
    private val _sessionExpired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    /** Emits when the refresh token is no longer accepted and the user must sign in again. */
    val sessionExpired: SharedFlow<Unit> = _sessionExpired

    // HTTP header values must be printable ASCII, and device names can contain anything.
    private val clientLabel = "${Build.MANUFACTURER} ${Build.MODEL} - Android ${Build.VERSION.RELEASE}"
        .map { if (it in ' '..'~') it else '?' }.joinToString("").take(120)

    private fun baseClient() = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .addInterceptor(Interceptor { chain ->
            chain.proceed(chain.request().newBuilder().header("X-Client-Label", clientLabel).build())
        })
        .apply {
            if (BuildConfig.DEBUG) {
                addInterceptor(HttpLoggingInterceptor().apply {
                    level = HttpLoggingInterceptor.Level.BASIC
                    redactHeader("Authorization")
                })
            }
        }

    private fun retrofit(client: OkHttpClient) = Retrofit.Builder()
        .baseUrl(BuildConfig.API_BASE_URL)
        .client(client)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()

    // Used only to refresh tokens; it has no authenticator so it cannot loop.
    private val refreshApi: Api = retrofit(baseClient().build()).create(Api::class.java)

    val api: Api = retrofit(
        baseClient()
            .addInterceptor(Interceptor { chain ->
                val token = tokens.accessToken
                val req = if (token != null) chain.request().withBearer(token) else chain.request()
                chain.proceed(req)
            })
            .authenticator(RefreshingAuthenticator())
            .build(),
    ).create(Api::class.java)

    private fun Request.withBearer(token: String) = newBuilder().header("Authorization", "Bearer $token").build()

    private inner class RefreshingAuthenticator : Authenticator {
        override fun authenticate(route: Route?, response: Response): Request? {
            if (response.request.url.encodedPath.contains("/auth/")) return null
            if (response.priorResponse != null) return null
            synchronized(this) {
                val sent = response.request.header("Authorization")?.removePrefix("Bearer ")
                val current = tokens.accessToken
                // Another request already refreshed while this one waited.
                if (current != null && current != sent) return response.request.withBearer(current)
                val refresh = tokens.refreshToken ?: return expire()
                return try {
                    val pair = runBlocking { refreshApi.refresh(RefreshRequest(refresh)) }
                    tokens.save(pair)
                    response.request.withBearer(pair.accessToken)
                } catch (e: HttpException) {
                    expire()
                } catch (e: IOException) {
                    null
                }
            }
        }

        private fun expire(): Request? {
            tokens.clear()
            _sessionExpired.tryEmit(Unit)
            return null
        }
    }
}

/** Result of one API call, already classified for the UI. */
sealed interface ApiResult<out T> {
    data class Ok<T>(val value: T) : ApiResult<T>
    data class Failed(val error: AppError) : ApiResult<Nothing>
}

sealed interface AppError {
    data object NoInternet : AppError
    data object ServerUnreachable : AppError
    data class Server(val code: String, val message: String, val referenceId: String?, val fields: Map<String, String>?) : AppError
}

suspend fun <T> call(block: suspend () -> T): ApiResult<T> = try {
    ApiResult.Ok(block())
} catch (e: HttpException) {
    val body = e.response()?.errorBody()?.string()
    val detail = runCatching { json.decodeFromString<ErrorEnvelope>(body!!).error }.getOrNull()
    ApiResult.Failed(
        if (detail != null) AppError.Server(detail.code, detail.message, detail.referenceId, detail.fields)
        else AppError.Server("HTTP_${e.code()}", e.message(), null, null),
    )
} catch (e: java.net.UnknownHostException) {
    ApiResult.Failed(AppError.NoInternet)
} catch (e: IOException) {
    ApiResult.Failed(AppError.ServerUnreachable)
} catch (e: kotlinx.serialization.SerializationException) {
    ApiResult.Failed(AppError.Server("BAD_RESPONSE", e.message ?: "", null, null))
}
