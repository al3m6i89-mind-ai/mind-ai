package app.nuvola.devices

import app.nuvola.billing.SubscriptionRepository
import app.nuvola.billing.SubscriptionStatus
import app.nuvola.catalog.PlanRepository
import app.nuvola.common.AuditService
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional
import java.time.Duration
import java.time.Instant

/**
 * Applies the published service policy when a subscription ends:
 * devices stop at expiry, and are deleted only after the plan's data-retention period.
 */
@Component
class LifecycleScheduler(
    private val subs: SubscriptionRepository,
    private val plans: PlanRepository,
    private val devices: CloudDeviceRepository,
    private val deviceService: DeviceService,
    private val audit: AuditService,
) {
    @Scheduled(fixedDelay = 60_000, initialDelay = 10_000)
    @Transactional
    fun expireSubscriptions() {
        val now = Instant.now()
        subs.findDueForExpiry(now).forEach { sub ->
            sub.status = SubscriptionStatus.EXPIRED
            sub.updatedAt = now
            audit.system("subscription.expired", "subscription", sub.id)
            devices.findBySubscriptionIdAndDeletedAtIsNull(sub.id).forEach { deviceService.systemStop(it, "SUBSCRIPTION_EXPIRED") }
        }
    }

    @Scheduled(fixedDelay = 3_600_000, initialDelay = 30_000)
    @Transactional
    fun purgeAfterRetention() {
        val now = Instant.now()
        subs.findAll().filter { it.status == SubscriptionStatus.EXPIRED || it.status == SubscriptionStatus.CANCELED }.forEach { sub ->
            val plan = plans.findById(sub.planId).orElseThrow()
            val end = sub.expiresAt ?: return@forEach
            if (end.plus(Duration.ofDays(plan.dataRetentionDays.toLong())).isBefore(now)) {
                devices.findBySubscriptionIdAndDeletedAtIsNull(sub.id).forEach { deviceService.systemDestroy(it, "RETENTION_ENDED") }
            }
        }
    }
}
