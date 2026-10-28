package app.nuvola.cloudphone.data

import kotlinx.serialization.Serializable

// Mirrors the backend DTOs. Instants are kept as ISO-8601 strings and formatted in the UI.

@Serializable
data class ErrorEnvelope(val error: ErrorDetail)

@Serializable
data class ErrorDetail(
    val code: String,
    val message: String,
    val referenceId: String? = null,
    val fields: Map<String, String>? = null,
)

@Serializable
data class TokenPair(
    val accessToken: String,
    val accessTokenExpiresAt: String,
    val refreshToken: String,
    val refreshTokenExpiresAt: String,
    val sessionId: String,
)

@Serializable data class RegisterRequest(
    val email: String, val password: String, val displayName: String, val locale: String, val acceptTerms: Boolean,
)
@Serializable data class LoginRequest(val email: String, val password: String)
@Serializable data class RefreshRequest(val refreshToken: String)
@Serializable data class TokenRequest(val token: String)
@Serializable data class EmailRequest(val email: String)
@Serializable data class ResetPasswordRequest(val token: String, val newPassword: String)
@Serializable data class ChangePasswordRequest(val currentPassword: String, val newPassword: String)
@Serializable data class UpdateMeRequest(val displayName: String? = null, val locale: String? = null)

@Serializable
data class AppConfig(
    val environment: String,
    val minSupportedAppVersion: Int,
    val termsVersion: String,
    val termsUrl: String,
    val privacyUrl: String,
    val supportEmail: String,
    val deviceProvider: String,
    val devicesSimulated: Boolean,
    val streamingAvailable: Boolean,
)

@Serializable
data class Me(
    val id: String,
    val email: String,
    val displayName: String,
    val locale: String,
    val emailVerified: Boolean,
    val role: String,
    val accountStatus: String,
    val deletionScheduledFor: String? = null,
    val createdAt: String,
)

@Serializable
data class LoginSession(val id: String, val clientLabel: String? = null, val createdAt: String, val lastUsedAt: String, val current: Boolean)

@Serializable
data class Plan(
    val id: String,
    val code: String,
    val name: String,
    val billingPeriod: String,
    val price: Double,
    val currency: String,
    val deviceType: String,
    val deviceLimit: Int,
    val concurrentSessionLimit: Int,
    val cpuCores: Int,
    val ramMb: Int,
    val storageGb: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val screenDpi: Int,
    val maxFps: Int,
    val alwaysOn: Boolean,
    val rootAllowed: Boolean,
    val dataRetentionDays: Int,
)

@Serializable
data class AndroidImage(
    val id: String,
    val androidVersion: String,
    val apiLevel: Int,
    val displayName: String,
    val deviceType: String,
    val rootSupported: Boolean,
    val preinstalledApps: List<String>,
    val simulated: Boolean,
)

@Serializable data class Region(val id: String, val displayName: String, val countryCode: String? = null)
@Serializable data class Catalog(val androidImages: List<AndroidImage>, val regions: List<Region>)

@Serializable
data class Subscription(
    val id: String,
    val planId: String,
    val planName: String,
    val status: String,
    val startsAt: String? = null,
    val expiresAt: String? = null,
    val renewalStatus: String,
    val renewalPrice: Double,
    val currency: String,
    val deviceLimit: Int,
    val devicesUsed: Int,
    val dataRetentionDays: Int,
    val provider: String,
)

@Serializable data class CreateSubscriptionRequest(val planId: String)

@Serializable
data class Invoice(
    val id: String,
    val invoiceNumber: String,
    val total: Double,
    val tax: Double,
    val currency: String,
    val createdAt: String,
)

@Serializable
data class Device(
    val id: String,
    val displayName: String,
    val deviceType: String,
    val androidVersion: String,
    val androidImageId: String,
    val region: String,
    val regionName: String,
    val cpuCores: Int,
    val ramMb: Int,
    val storageGb: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val screenDpi: Int,
    val rootEnabled: Boolean,
    val status: String,
    val statusDetail: String? = null,
    val pendingAction: String? = null,
    val simulated: Boolean,
    val subscriptionId: String,
    val planName: String,
    val subscriptionExpiresAt: String? = null,
    val subscriptionActive: Boolean,
    val alwaysOn: Boolean,
    val preinstalledApps: List<String> = emptyList(),
    val lastSeenAt: String? = null,
    val createdAt: String,
    val updatedAt: String,
)

@Serializable
data class Dashboard(
    val displayName: String,
    val email: String,
    val emailVerified: Boolean,
    val runningDevices: Int,
    val stoppedDevices: Int,
    val totalDevices: Int,
    val deviceAllowance: Int,
    val nearestExpiry: String? = null,
    val devicesSimulated: Boolean,
    val devices: List<Device>,
)

@Serializable
data class CreateDeviceRequest(
    val subscriptionId: String,
    val androidImageId: String,
    val regionId: String,
    val displayName: String,
    val rootEnabled: Boolean,
)

@Serializable data class RenameRequest(val displayName: String)
@Serializable data class RootRequest(val enabled: Boolean)
@Serializable data class StreamSession(val sessionId: String, val gatewayUrl: String, val token: String, val expiresAt: String)

@Serializable
data class Ticket(
    val id: String,
    val ticketNumber: String,
    val category: String,
    val subject: String,
    val description: String,
    val cloudDeviceId: String? = null,
    val status: String,
    val createdAt: String,
    val updatedAt: String,
    val messages: List<TicketMessage>? = null,
)

@Serializable data class TicketMessage(val id: String, val fromSupport: Boolean, val body: String, val createdAt: String)
@Serializable data class CreateTicketRequest(val category: String, val subject: String, val description: String, val cloudDeviceId: String? = null)
@Serializable data class ReplyRequest(val body: String)
