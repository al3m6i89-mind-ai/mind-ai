package app.nuvola.catalog

import app.nuvola.config.AppProperties
import app.nuvola.devices.ProviderRegistry
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Id
import jakarta.persistence.Table
import org.hibernate.annotations.JdbcTypeCode
import org.hibernate.type.SqlTypes
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

enum class DeviceType { VIRTUAL, PHYSICAL }
enum class BillingPeriod { DAY, WEEK, MONTH, QUARTER, YEAR }

@Entity
@Table(name = "regions")
class Region(
    @Id val id: String,
    var displayName: String,
    var countryCode: String?,
    /** Null means every provider serves this region. */
    var providerId: String?,
    var active: Boolean,
    var sortOrder: Int,
) {
    fun servedBy(provider: String) = providerId == null || providerId == provider
}

@Entity
@Table(name = "android_images")
class AndroidImage(
    @Id val id: String,
    var providerId: String,
    var androidVersion: String,
    var apiLevel: Int,
    var displayName: String,
    @Enumerated(EnumType.STRING) var deviceType: DeviceType,
    var rootSupported: Boolean,
    @JdbcTypeCode(SqlTypes.JSON) @Column(columnDefinition = "jsonb")
    var preinstalledApps: List<String>,
    var active: Boolean,
    var sortOrder: Int,
)

@Entity
@Table(name = "plans")
class Plan(
    @Id val id: UUID,
    var code: String,
    var name: String,
    @Enumerated(EnumType.STRING) var billingPeriod: BillingPeriod,
    var price: BigDecimal,
    var currency: String,
    @Enumerated(EnumType.STRING) var deviceType: DeviceType,
    var deviceLimit: Int,
    var concurrentSessionLimit: Int,
    var cpuCores: Int,
    var ramMb: Int,
    var storageGb: Int,
    var screenWidth: Int,
    var screenHeight: Int,
    var screenDpi: Int,
    var maxFps: Int,
    var alwaysOn: Boolean,
    var rootAllowed: Boolean,
    var dataRetentionDays: Int,
    @JdbcTypeCode(SqlTypes.JSON) @Column(columnDefinition = "jsonb")
    var featureConfig: Map<String, Any?>,
    var active: Boolean,
    var sortOrder: Int,
    val createdAt: Instant,
)

interface RegionRepository : JpaRepository<Region, String> {
    fun findByActiveTrueOrderBySortOrder(): List<Region>
}

interface AndroidImageRepository : JpaRepository<AndroidImage, String> {
    fun findByActiveTrueOrderBySortOrder(): List<AndroidImage>
}

interface PlanRepository : JpaRepository<Plan, UUID> {
    fun findByActiveTrueOrderBySortOrder(): List<Plan>
}

data class AndroidImageDto(
    val id: String,
    val androidVersion: String,
    val apiLevel: Int,
    val displayName: String,
    val deviceType: DeviceType,
    val rootSupported: Boolean,
    val preinstalledApps: List<String>,
    val simulated: Boolean,
)

data class RegionDto(val id: String, val displayName: String, val countryCode: String?)

data class CatalogDto(val androidImages: List<AndroidImageDto>, val regions: List<RegionDto>)

@RestController
@RequestMapping("/api/v1")
class CatalogController(
    private val plans: PlanRepository,
    private val images: AndroidImageRepository,
    private val regions: RegionRepository,
    private val providers: ProviderRegistry,
    private val props: AppProperties,
) {
    @GetMapping("/plans")
    fun plans() = plans.findByActiveTrueOrderBySortOrder()

    /** Only images served by the provider this server actually runs are offered. */
    @GetMapping("/catalog")
    fun catalog(): CatalogDto {
        val provider = providers.active()
        return CatalogDto(
            androidImages = images.findByActiveTrueOrderBySortOrder()
                .filter { it.providerId == provider.id }
                .map {
                    AndroidImageDto(it.id, it.androidVersion, it.apiLevel, it.displayName, it.deviceType,
                        it.rootSupported, it.preinstalledApps, provider.simulated)
                },
            regions = regions.findByActiveTrueOrderBySortOrder().filter { it.servedBy(provider.id) }.map { RegionDto(it.id, it.displayName, it.countryCode) },
        )
    }

    @GetMapping("/health")
    fun health() = mapOf("status" to "ok", "time" to Instant.now().toString())

    @GetMapping("/app-config")
    fun appConfig() = mapOf(
        "environment" to props.environment,
        "minSupportedAppVersion" to props.minSupportedAppVersion,
        "termsVersion" to props.termsVersion,
        "termsUrl" to props.termsUrl,
        "privacyUrl" to props.privacyUrl,
        "supportEmail" to props.supportEmail,
        "deviceProvider" to providers.active().id,
        "devicesSimulated" to providers.active().simulated,
        "streamingAvailable" to providers.active().supportsStreaming,
    )
}
