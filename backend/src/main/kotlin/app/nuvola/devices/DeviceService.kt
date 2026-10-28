package app.nuvola.devices

import app.nuvola.auth.UserRepository
import app.nuvola.billing.DeviceCounter
import app.nuvola.billing.SubscriptionRepository
import app.nuvola.catalog.AndroidImageRepository
import app.nuvola.catalog.DeviceType
import app.nuvola.catalog.PlanRepository
import app.nuvola.catalog.RegionRepository
import app.nuvola.common.ApiException
import app.nuvola.common.AuditService
import app.nuvola.common.ErrorCode
import app.nuvola.common.notFound
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Instant
import java.util.UUID

data class CreateDeviceCommand(
    val subscriptionId: UUID,
    val androidImageId: String,
    val regionId: String,
    val displayName: String,
    val rootEnabled: Boolean,
)

data class DeviceDto(
    val id: UUID,
    val displayName: String,
    val deviceType: DeviceType,
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
    val status: LifecycleStatus,
    val statusDetail: String?,
    val pendingAction: JobType?,
    /** True when the device comes from the development provider and is not a real Android system. */
    val simulated: Boolean,
    val subscriptionId: UUID,
    val planName: String,
    val subscriptionExpiresAt: Instant?,
    val subscriptionActive: Boolean,
    val alwaysOn: Boolean,
    val preinstalledApps: List<String>,
    val lastSeenAt: Instant?,
    val createdAt: Instant,
    val updatedAt: Instant,
)

data class DashboardDto(
    val displayName: String,
    val email: String,
    val emailVerified: Boolean,
    val runningDevices: Int,
    val stoppedDevices: Int,
    val totalDevices: Int,
    val deviceAllowance: Int,
    val nearestExpiry: Instant?,
    val devicesSimulated: Boolean,
    val devices: List<DeviceDto>,
)

@Service
class DeviceService(
    private val devices: CloudDeviceRepository,
    private val jobs: DeviceJobRepository,
    private val subs: SubscriptionRepository,
    private val plans: PlanRepository,
    private val images: AndroidImageRepository,
    private val regions: RegionRepository,
    private val users: UserRepository,
    private val providers: ProviderRegistry,
    private val audit: AuditService,
) : DeviceCounter {

    override fun countLive(subscriptionId: UUID) = devices.countLive(subscriptionId)

    fun list(userId: UUID): List<DeviceDto> {
        val list = devices.findByOwnerUserIdAndDeletedAtIsNullOrderByCreatedAt(userId)
        val pending = jobs.findActiveFor(list.map { it.id }).associateBy { it.deviceId }
        return list.map { toDto(it, pending[it.id]) }
    }

    fun get(userId: UUID, id: UUID): DeviceDto = toDto(owned(userId, id), jobs.findActive(id))

    fun dashboard(userId: UUID): DashboardDto {
        val user = users.findById(userId).orElseThrow()
        val list = list(userId)
        val now = Instant.now()
        val activeSubs = subs.findByUserIdOrderByCreatedAtDesc(userId).filter { it.isActiveAt(now) }
        val allowance = activeSubs.sumOf { s -> plans.findById(s.planId).map { it.deviceLimit }.orElse(0) }
        return DashboardDto(
            displayName = user.displayName,
            email = user.email,
            emailVerified = user.emailVerified,
            runningDevices = list.count { it.status == LifecycleStatus.RUNNING },
            stoppedDevices = list.count { it.status == LifecycleStatus.STOPPED },
            totalDevices = list.size,
            deviceAllowance = allowance,
            nearestExpiry = activeSubs.mapNotNull { it.expiresAt }.minOrNull(),
            devicesSimulated = providers.active().simulated,
            devices = list,
        )
    }

    /** Creates at most one device per idempotency key, so a double tap or a retry never makes two. */
    @Transactional
    fun create(userId: UUID, cmd: CreateDeviceCommand, idempotencyKey: String): Pair<DeviceDto, Boolean> {
        devices.findByOwnerUserIdAndIdempotencyKey(userId, idempotencyKey)?.let {
            return toDto(it, jobs.findActive(it.id)) to false
        }
        val user = users.findById(userId).orElseThrow()
        if (!user.emailVerified) throw ApiException(ErrorCode.EMAIL_NOT_VERIFIED, "Confirm your email before creating a phone")

        // Row lock serialises concurrent creates on the same subscription so the limit holds.
        val sub = subs.lockById(cmd.subscriptionId)?.takeIf { it.userId == userId } ?: notFound("Subscription")
        if (!sub.isActiveAt(Instant.now())) throw ApiException(ErrorCode.SUBSCRIPTION_EXPIRED, "This subscription is not active")
        val plan = plans.findById(sub.planId).orElseThrow()
        if (devices.countLive(sub.id) >= plan.deviceLimit) {
            throw ApiException(ErrorCode.DEVICE_LIMIT_REACHED, "This plan allows ${plan.deviceLimit} phone(s)")
        }
        val provider = providers.active()
        val image = images.findById(cmd.androidImageId)
            .filter { it.active && it.providerId == provider.id && it.deviceType == plan.deviceType }
            .orElse(null) ?: throw ApiException(ErrorCode.IMAGE_NOT_AVAILABLE, "This Android version is not available")
        val region = regions.findById(cmd.regionId).filter { it.active }.orElse(null)
            ?: throw ApiException(ErrorCode.REGION_NOT_AVAILABLE, "This location is not available")
        if (cmd.rootEnabled && !(plan.rootAllowed && image.rootSupported)) {
            throw ApiException(ErrorCode.ROOT_NOT_ALLOWED, "Root is not available for this plan or Android version")
        }

        val device = devices.save(CloudDevice(
            ownerUserId = userId,
            subscriptionId = sub.id,
            providerId = provider.id,
            deviceType = plan.deviceType,
            displayName = cmd.displayName.trim(),
            androidImageId = image.id,
            androidVersion = image.androidVersion,
            region = region.id,
            cpuConfig = plan.cpuCores,
            ramConfig = plan.ramMb,
            storageConfig = plan.storageGb,
            screenWidth = plan.screenWidth,
            screenHeight = plan.screenHeight,
            screenDpi = plan.screenDpi,
            rootEnabled = cmd.rootEnabled,
            lifecycleStatus = LifecycleStatus.CREATING,
            idempotencyKey = idempotencyKey,
        ))
        val job = jobs.save(DeviceJob(deviceId = device.id, type = JobType.CREATE, requestedBy = userId))
        audit.user(userId, "device.create_requested", "cloud_device", device.id,
            mapOf("image" to image.id, "region" to region.id, "root" to cmd.rootEnabled))
        return toDto(device, job) to true
    }

    @Transactional
    fun start(userId: UUID, id: UUID): DeviceDto {
        val d = owned(userId, id)
        requireSubscription(d)
        return enqueue(userId, d, JobType.START, LifecycleStatus.STARTING,
            allowedFrom = setOf(LifecycleStatus.STOPPED, LifecycleStatus.OFFLINE, LifecycleStatus.ERROR))
    }

    @Transactional
    fun stop(userId: UUID, id: UUID): DeviceDto = enqueue(userId, owned(userId, id), JobType.STOP, LifecycleStatus.STOPPING,
        allowedFrom = setOf(LifecycleStatus.RUNNING, LifecycleStatus.OFFLINE, LifecycleStatus.ERROR))

    @Transactional
    fun restart(userId: UUID, id: UUID): DeviceDto {
        val d = owned(userId, id)
        requireSubscription(d)
        return enqueue(userId, d, JobType.RESTART, LifecycleStatus.RESTARTING,
            allowedFrom = setOf(LifecycleStatus.RUNNING, LifecycleStatus.OFFLINE, LifecycleStatus.ERROR))
    }

    @Transactional
    fun setRoot(userId: UUID, id: UUID, enabled: Boolean): DeviceDto {
        val d = owned(userId, id)
        if (d.rootEnabled == enabled) return toDto(d, jobs.findActive(id))
        if (enabled) {
            val plan = plans.findById(subs.findById(d.subscriptionId).orElseThrow().planId).orElseThrow()
            val image = images.findById(d.androidImageId).orElseThrow()
            if (!(plan.rootAllowed && image.rootSupported)) {
                throw ApiException(ErrorCode.ROOT_NOT_ALLOWED, "Root is not available for this plan or Android version")
            }
        }
        val next = if (d.lifecycleStatus == LifecycleStatus.RUNNING) LifecycleStatus.RESTARTING else d.lifecycleStatus
        return enqueue(userId, d, JobType.SET_ROOT, next,
            allowedFrom = setOf(LifecycleStatus.RUNNING, LifecycleStatus.STOPPED),
            payload = mapOf("enabled" to enabled, "resume" to d.lifecycleStatus.name))
    }

    @Transactional
    fun rename(userId: UUID, id: UUID, name: String): DeviceDto {
        val d = owned(userId, id)
        d.displayName = name.trim()
        d.updatedAt = Instant.now()
        audit.user(userId, "device.renamed", "cloud_device", id)
        return toDto(d, jobs.findActive(id))
    }

    @Transactional
    fun delete(userId: UUID, id: UUID): DeviceDto = enqueue(userId, owned(userId, id), JobType.DESTROY, LifecycleStatus.DELETING,
        allowedFrom = LifecycleStatus.entries.toSet() - setOf(LifecycleStatus.DELETING, LifecycleStatus.DELETED, LifecycleStatus.CREATING))

    /** System-initiated stop, e.g. when a subscription expires. */
    @Transactional
    fun systemStop(device: CloudDevice, reason: String) {
        if (device.lifecycleStatus != LifecycleStatus.RUNNING || jobs.findActive(device.id) != null) return
        device.lifecycleStatus = LifecycleStatus.STOPPING
        device.statusDetail = reason
        device.updatedAt = Instant.now()
        jobs.save(DeviceJob(deviceId = device.id, type = JobType.STOP, requestedBy = null))
        audit.system("device.stop_requested", "cloud_device", device.id, mapOf("reason" to reason))
    }

    @Transactional
    fun systemDestroy(device: CloudDevice, reason: String) {
        if (device.lifecycleStatus in setOf(LifecycleStatus.DELETING, LifecycleStatus.DELETED)) return
        jobs.findActive(device.id)?.let { return }
        device.lifecycleStatus = LifecycleStatus.DELETING
        device.statusDetail = reason
        device.updatedAt = Instant.now()
        jobs.save(DeviceJob(deviceId = device.id, type = JobType.DESTROY, requestedBy = null))
        audit.system("device.destroy_requested", "cloud_device", device.id, mapOf("reason" to reason))
    }

    fun owned(userId: UUID, id: UUID): CloudDevice =
        devices.findById(id).filter { it.ownerUserId == userId && it.deletedAt == null }.orElse(null) ?: notFound("Device")

    private fun requireSubscription(d: CloudDevice) {
        val sub = subs.findById(d.subscriptionId).orElseThrow()
        if (!sub.isActiveAt(Instant.now())) throw ApiException(ErrorCode.SUBSCRIPTION_EXPIRED, "Renew your subscription to use this phone")
    }

    private fun enqueue(
        userId: UUID,
        d: CloudDevice,
        type: JobType,
        next: LifecycleStatus,
        allowedFrom: Set<LifecycleStatus>,
        payload: Map<String, Any?> = emptyMap(),
    ): DeviceDto {
        if (jobs.findActive(d.id) != null) throw ApiException(ErrorCode.DEVICE_BUSY, "Wait for the current action to finish")
        if (d.lifecycleStatus !in allowedFrom) {
            throw ApiException(ErrorCode.INVALID_DEVICE_STATE, "This action is not possible while the phone is ${d.lifecycleStatus}")
        }
        if (type != JobType.DESTROY && d.providerDeviceRef == null) {
            throw ApiException(ErrorCode.INVALID_DEVICE_STATE, "This phone was never created successfully. Delete it and create a new one")
        }
        val job = try {
            jobs.saveAndFlush(DeviceJob(deviceId = d.id, type = type, payload = payload, requestedBy = userId))
        } catch (e: DataIntegrityViolationException) {
            throw ApiException(ErrorCode.DEVICE_BUSY, "Wait for the current action to finish")
        }
        d.lifecycleStatus = next
        d.statusDetail = null
        d.updatedAt = Instant.now()
        audit.user(userId, "device.${type.name.lowercase()}_requested", "cloud_device", d.id)
        return toDto(d, job)
    }

    fun toDto(d: CloudDevice, activeJob: DeviceJob?): DeviceDto {
        val sub = subs.findById(d.subscriptionId).orElseThrow()
        val plan = plans.findById(sub.planId).orElseThrow()
        val image = images.findById(d.androidImageId).orElse(null)
        val region = regions.findById(d.region).orElse(null)
        return DeviceDto(
            id = d.id,
            displayName = d.displayName,
            deviceType = d.deviceType,
            androidVersion = d.androidVersion,
            androidImageId = d.androidImageId,
            region = d.region,
            regionName = region?.displayName ?: d.region,
            cpuCores = d.cpuConfig,
            ramMb = d.ramConfig,
            storageGb = d.storageConfig,
            screenWidth = d.screenWidth,
            screenHeight = d.screenHeight,
            screenDpi = d.screenDpi,
            rootEnabled = d.rootEnabled,
            status = d.lifecycleStatus,
            statusDetail = d.statusDetail,
            pendingAction = activeJob?.type,
            simulated = providers.get(d.providerId).simulated,
            subscriptionId = sub.id,
            planName = plan.name,
            subscriptionExpiresAt = sub.expiresAt,
            subscriptionActive = sub.isActiveAt(Instant.now()),
            alwaysOn = plan.alwaysOn,
            preinstalledApps = image?.preinstalledApps ?: emptyList(),
            lastSeenAt = d.lastSeenAt,
            createdAt = d.createdAt,
            updatedAt = d.updatedAt,
        )
    }
}
