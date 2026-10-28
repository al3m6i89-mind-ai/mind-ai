package app.nuvola.devices

import app.nuvola.catalog.DeviceType
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Id
import jakarta.persistence.Table
import org.hibernate.annotations.JdbcTypeCode
import org.hibernate.type.SqlTypes
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import java.time.Instant
import java.util.UUID

enum class LifecycleStatus {
    CREATING, STARTING, RUNNING, STOPPING, STOPPED, RESTARTING, OFFLINE, ERROR, DELETING, DELETED
}

@Entity
@Table(name = "cloud_devices")
class CloudDevice(
    @Id val id: UUID = UUID.randomUUID(),
    val ownerUserId: UUID,
    val subscriptionId: UUID,
    val providerId: String,
    var providerDeviceRef: String? = null,
    @Enumerated(EnumType.STRING) val deviceType: DeviceType,
    var displayName: String,
    val androidImageId: String,
    val androidVersion: String,
    val region: String,
    val cpuConfig: Int,
    val ramConfig: Int,
    val storageConfig: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val screenDpi: Int,
    var rootEnabled: Boolean,
    @Enumerated(EnumType.STRING) var lifecycleStatus: LifecycleStatus,
    var statusDetail: String? = null,
    val idempotencyKey: String,
    var lastSeenAt: Instant? = null,
    val createdAt: Instant = Instant.now(),
    var updatedAt: Instant = Instant.now(),
    var deletedAt: Instant? = null,
)

interface CloudDeviceRepository : JpaRepository<CloudDevice, UUID> {
    fun findByOwnerUserIdAndDeletedAtIsNullOrderByCreatedAt(ownerUserId: UUID): List<CloudDevice>
    fun findByOwnerUserIdAndIdempotencyKey(ownerUserId: UUID, key: String): CloudDevice?
    fun findBySubscriptionIdAndDeletedAtIsNull(subscriptionId: UUID): List<CloudDevice>

    @Query("select count(d) from CloudDevice d where d.subscriptionId = :subscriptionId and d.deletedAt is null and d.lifecycleStatus <> 'DELETING'")
    fun countLive(subscriptionId: UUID): Int
}

enum class JobType { CREATE, START, STOP, RESTART, DESTROY, SET_ROOT }
enum class JobStatus { QUEUED, RUNNING, SUCCEEDED, FAILED }

@Entity
@Table(name = "device_jobs")
class DeviceJob(
    @Id val id: UUID = UUID.randomUUID(),
    val deviceId: UUID,
    @Enumerated(EnumType.STRING) val type: JobType,
    @Enumerated(EnumType.STRING) var status: JobStatus = JobStatus.QUEUED,
    @JdbcTypeCode(SqlTypes.JSON) @Column(columnDefinition = "jsonb")
    val payload: Map<String, Any?> = emptyMap(),
    var attempts: Int = 0,
    val maxAttempts: Int = 3,
    var runAfter: Instant = Instant.now(),
    var startedAt: Instant? = null,
    var finishedAt: Instant? = null,
    var lastError: String? = null,
    val requestedBy: UUID?,
    val createdAt: Instant = Instant.now(),
)

interface DeviceJobRepository : JpaRepository<DeviceJob, UUID> {
    @Query("select j from DeviceJob j where j.deviceId = :deviceId and j.status in ('QUEUED', 'RUNNING')")
    fun findActive(deviceId: UUID): DeviceJob?

    @Query("select j from DeviceJob j where j.deviceId in :deviceIds and j.status in ('QUEUED', 'RUNNING')")
    fun findActiveFor(deviceIds: Collection<UUID>): List<DeviceJob>

    fun findTop20ByDeviceIdOrderByCreatedAtDesc(deviceId: UUID): List<DeviceJob>
}

enum class ConnectionStatus { PENDING, CONNECTED, ENDED, EXPIRED }

@Entity
@Table(name = "device_sessions")
class DeviceSession(
    @Id val id: UUID = UUID.randomUUID(),
    val userId: UUID,
    val cloudDeviceId: UUID,
    @Enumerated(EnumType.STRING) var connectionStatus: ConnectionStatus = ConnectionStatus.PENDING,
    val tokenHash: String,
    val tokenExpiresAt: Instant,
    var tokenUsedAt: Instant? = null,
    val startedAt: Instant = Instant.now(),
    var endedAt: Instant? = null,
    var lastActivityAt: Instant = Instant.now(),
)

interface DeviceSessionRepository : JpaRepository<DeviceSession, UUID> {
    @Query("select count(s) from DeviceSession s where s.userId = :userId and s.endedAt is null and s.lastActivityAt > :since")
    fun countOpen(userId: UUID, since: Instant): Int
}
