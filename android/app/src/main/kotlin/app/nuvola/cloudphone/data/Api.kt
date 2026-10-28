package app.nuvola.cloudphone.data

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path

interface Api {
    @GET("health") suspend fun health(): Map<String, String>
    @GET("app-config") suspend fun appConfig(): AppConfig

    @POST("auth/register") suspend fun register(@Body body: RegisterRequest): TokenPair
    @POST("auth/login") suspend fun login(@Body body: LoginRequest): TokenPair
    @POST("auth/refresh") suspend fun refresh(@Body body: RefreshRequest): TokenPair
    @POST("auth/logout") suspend fun logout(): Response<Unit>
    @POST("auth/verify-email") suspend fun verifyEmail(@Body body: TokenRequest): Response<Unit>
    @POST("auth/forgot-password") suspend fun forgotPassword(@Body body: EmailRequest): Response<Unit>
    @POST("auth/reset-password") suspend fun resetPassword(@Body body: ResetPasswordRequest): Response<Unit>

    @GET("me") suspend fun me(): Me
    @PATCH("me") suspend fun updateMe(@Body body: UpdateMeRequest): Me
    @DELETE("me") suspend fun deleteAccount(): Response<Unit>
    @POST("me/resend-verification") suspend fun resendVerification(): Response<Unit>
    @POST("me/password") suspend fun changePassword(@Body body: ChangePasswordRequest): Response<Unit>
    @GET("me/sessions") suspend fun loginSessions(): List<LoginSession>
    @DELETE("me/sessions/{id}") suspend fun revokeLoginSession(@Path("id") id: String): Response<Unit>

    @GET("plans") suspend fun plans(): List<Plan>
    @GET("catalog") suspend fun catalog(): Catalog
    @GET("subscriptions") suspend fun subscriptions(): List<Subscription>
    @POST("subscriptions") suspend fun createSubscription(@Body body: CreateSubscriptionRequest): Subscription
    @POST("subscriptions/{id}/cancel-renewal") suspend fun cancelRenewal(@Path("id") id: String): Subscription
    @GET("invoices") suspend fun invoices(): List<Invoice>

    @GET("dashboard") suspend fun dashboard(): Dashboard
    @GET("devices") suspend fun devices(): List<Device>
    @GET("devices/{id}") suspend fun device(@Path("id") id: String): Device
    @POST("devices") suspend fun createDevice(@Header("Idempotency-Key") key: String, @Body body: CreateDeviceRequest): Device
    @PATCH("devices/{id}") suspend fun renameDevice(@Path("id") id: String, @Body body: RenameRequest): Device
    @POST("devices/{id}/start") suspend fun startDevice(@Path("id") id: String): Device
    @POST("devices/{id}/stop") suspend fun stopDevice(@Path("id") id: String): Device
    @POST("devices/{id}/restart") suspend fun restartDevice(@Path("id") id: String): Device
    @POST("devices/{id}/root") suspend fun setRoot(@Path("id") id: String, @Body body: RootRequest): Device
    @DELETE("devices/{id}") suspend fun deleteDevice(@Path("id") id: String): Device
    @POST("devices/{id}/sessions") suspend fun openSession(@Path("id") id: String): StreamSession
    @DELETE("sessions/{id}") suspend fun closeSession(@Path("id") id: String): Response<Unit>

    @GET("support/tickets") suspend fun tickets(): List<Ticket>
    @GET("support/tickets/{id}") suspend fun ticket(@Path("id") id: String): Ticket
    @POST("support/tickets") suspend fun createTicket(@Body body: CreateTicketRequest): Ticket
    @POST("support/tickets/{id}/messages") suspend fun reply(@Path("id") id: String, @Body body: ReplyRequest): Ticket
}
