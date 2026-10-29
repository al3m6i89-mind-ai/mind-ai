package app.nuvola.devices

import app.nuvola.catalog.PlanRepository
import app.nuvola.billing.SubscriptionRepository
import app.nuvola.common.AuditService
import app.nuvola.config.AppProperties
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import org.springframework.transaction.support.TransactionTemplate
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * Runs device jobs from the database queue. Jobs are claimed with SKIP LOCKED, so several API
 * instances can run workers side by side without picking the same job.
 */
@Component
class JobWorker(
    private val jdbc: JdbcTemplate,
    private val tx: TransactionTemplate,
    private val jobs: DeviceJobRepository,
    private val devices: CloudDeviceRepository,
    private val subs: SubscriptionRepository,
    private val plans: PlanRepository,
    private val providers: ProviderRegistry,
    private val audit: AuditService,
    private val props: AppProperties,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Scheduled(fixedDelayString = "\${app.devices.job-poll-interval}")
    fun poll() {
        recoverTimedOut()
        claim().forEach(::run)
    }

    private fun claim(): List<UUID> = jdbc.queryForList(
        """
        UPDATE device_jobs SET status = 'RUNNING', started_at = now(), attempts = attempts + 1
        WHERE id IN (
            SELECT id FROM device_jobs WHERE status = 'QUEUED' AND run_after <= now()
            ORDER BY run_after LIMIT 5 FOR UPDATE SKIP LOCKED)
        RETURNING id
        """.trimIndent(), UUID::class.java,
    )

    private fun recoverTimedOut() {
        val cutoff = java.sql.Timestamp.from(Instant.now().minus(props.devices.jobTimeout))
        jdbc.update(
            """
            UPDATE device_jobs SET status = CASE WHEN attempts < max_attempts THEN 'QUEUED' ELSE 'FAILED' END,
                last_error = 'timed out', finished_at = CASE WHEN attempts < max_attempts THEN NULL ELSE now() END
            WHERE status = 'RUNNING' AND started_at < ?
            """.trimIndent(), cutoff,
        )
    }

    private fun run(jobId: UUID) {
        val (job, device) = tx.execute {
            val j = jobs.findById(jobId).orElseThrow()
            j to devices.findById(j.deviceId).orElseThrow()
        }!!
        val provider = providers.get(device.providerId)
        try {
            // Provider calls can be slow; they run outside any database transaction.
            var newRef: String? = null
            when (job.type) {
                JobType.CREATE -> newRef = provider.create(specFor(device))
                JobType.START -> provider.start(device.providerDeviceRef!!)
                JobType.STOP -> provider.stop(device.providerDeviceRef!!)
                JobType.RESTART -> provider.restart(device.providerDeviceRef!!)
                JobType.SET_ROOT -> provider.setRoot(device.providerDeviceRef!!, job.payload["enabled"] == true)
                JobType.DESTROY -> device.providerDeviceRef?.let(provider::destroy)
            }
            tx.executeWithoutResult { succeed(jobId, newRef) }
        } catch (e: Exception) {
            val retryable = (e as? ProviderException)?.retryable ?: true
            log.warn("Device job {} ({}) failed: {}", jobId, job.type, e.message)
            tx.executeWithoutResult { fail(jobId, e, retryable) }
        }
    }

    private fun succeed(jobId: UUID, newRef: String?) {
        val job = jobs.findById(jobId).orElseThrow()
        val d = devices.findById(job.deviceId).orElseThrow()
        val now = Instant.now()
        when (job.type) {
            JobType.CREATE -> { d.providerDeviceRef = newRef; d.lifecycleStatus = LifecycleStatus.RUNNING }
            JobType.START, JobType.RESTART -> d.lifecycleStatus = LifecycleStatus.RUNNING
            JobType.STOP -> d.lifecycleStatus = LifecycleStatus.STOPPED
            JobType.SET_ROOT -> {
                d.rootEnabled = job.payload["enabled"] == true
                d.lifecycleStatus = LifecycleStatus.valueOf(job.payload["resume"] as String)
            }
            JobType.DESTROY -> { d.lifecycleStatus = LifecycleStatus.DELETED; d.deletedAt = now }
        }
        if (job.type != JobType.STOP) d.statusDetail = null
        d.lastSeenAt = now
        d.updatedAt = now
        job.status = JobStatus.SUCCEEDED
        job.finishedAt = now
        audit.system("device.${job.type.name.lowercase()}_succeeded", "cloud_device", d.id)
    }

    private fun fail(jobId: UUID, e: Exception, retryable: Boolean) {
        val job = jobs.findById(jobId).orElseThrow()
        val d = devices.findById(job.deviceId).orElseThrow()
        val now = Instant.now()
        job.lastError = (e.message ?: e.javaClass.simpleName).take(500)
        if (retryable && job.attempts < job.maxAttempts) {
            job.status = JobStatus.QUEUED
            job.runAfter = now.plus(Duration.ofSeconds(5L * job.attempts))
            return
        }
        job.status = JobStatus.FAILED
        job.finishedAt = now
        d.lifecycleStatus = LifecycleStatus.ERROR
        d.statusDetail = when {
            e is NoCapacityException -> "NO_CAPACITY"
            job.type == JobType.CREATE -> "CREATE_FAILED"
            else -> "${job.type}_FAILED"
        }
        d.updatedAt = now
        audit.system("device.${job.type.name.lowercase()}_failed", "cloud_device", d.id, mapOf("error" to job.lastError))
    }

    private fun specFor(d: CloudDevice): DeviceSpec {
        val plan = plans.findById(subs.findById(d.subscriptionId).orElseThrow().planId).orElseThrow()
        return DeviceSpec(d.deviceType, d.androidImageId, d.androidVersion, d.region, d.cpuConfig, d.ramConfig, d.storageConfig,
            d.screenWidth, d.screenHeight, d.screenDpi, plan.maxFps, d.rootEnabled)
    }
}
