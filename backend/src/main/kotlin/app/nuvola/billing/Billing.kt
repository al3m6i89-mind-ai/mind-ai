package app.nuvola.billing

import app.nuvola.auth.AuthUser
import app.nuvola.catalog.BillingPeriod
import app.nuvola.catalog.PlanRepository
import app.nuvola.common.ApiException
import app.nuvola.common.AuditService
import app.nuvola.common.ErrorCode
import app.nuvola.common.notFound
import app.nuvola.config.AppProperties
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Id
import jakarta.persistence.LockModeType
import jakarta.persistence.Table
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Lock
import org.springframework.data.jpa.repository.Query
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID

enum class SubscriptionStatus { PENDING_PAYMENT, ACTIVE, EXPIRED, CANCELED }
enum class RenewalStatus { AUTO, OFF }

@Entity
@Table(name = "subscriptions")
class Subscription(
    @Id val id: UUID = UUID.randomUUID(),
    val userId: UUID,
    val planId: UUID,
    @Enumerated(EnumType.STRING) var status: SubscriptionStatus,
    var startsAt: Instant?,
    var expiresAt: Instant?,
    @Enumerated(EnumType.STRING) var renewalStatus: RenewalStatus = RenewalStatus.OFF,
    val provider: String,
    var providerReference: String? = null,
    val createdAt: Instant = Instant.now(),
    var updatedAt: Instant = Instant.now(),
) {
    fun isActiveAt(now: Instant) = status == SubscriptionStatus.ACTIVE && expiresAt?.isAfter(now) == true
}

interface SubscriptionRepository : JpaRepository<Subscription, UUID> {
    fun findByUserIdOrderByCreatedAtDesc(userId: UUID): List<Subscription>

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from Subscription s where s.id = :id")
    fun lockById(id: UUID): Subscription?

    @Query("select s from Subscription s where s.status = 'ACTIVE' and s.expiresAt <= :now")
    fun findDueForExpiry(now: Instant): List<Subscription>
}

@Entity
@Table(name = "invoices")
class Invoice(
    @Id val id: UUID,
    val userId: UUID,
    val paymentId: UUID,
    val invoiceNumber: String,
    val total: BigDecimal,
    val tax: BigDecimal,
    val currency: String,
    val createdAt: Instant,
)

interface InvoiceRepository : JpaRepository<Invoice, UUID> {
    fun findByUserIdOrderByCreatedAtDesc(userId: UUID): List<Invoice>
}

fun BillingPeriod.addTo(start: Instant): Instant {
    val t = start.atOffset(ZoneOffset.UTC)
    return when (this) {
        BillingPeriod.DAY -> t.plusDays(1)
        BillingPeriod.WEEK -> t.plusWeeks(1)
        BillingPeriod.MONTH -> t.plusMonths(1)
        BillingPeriod.QUARTER -> t.plusMonths(3)
        BillingPeriod.YEAR -> t.plusYears(1)
    }.toInstant()
}

data class SubscriptionDto(
    val id: UUID,
    val planId: UUID,
    val planName: String,
    val status: SubscriptionStatus,
    val startsAt: Instant?,
    val expiresAt: Instant?,
    val renewalStatus: RenewalStatus,
    val renewalPrice: BigDecimal,
    val currency: String,
    val deviceLimit: Int,
    val devicesUsed: Int,
    val dataRetentionDays: Int,
    val provider: String,
)

data class CreateSubscriptionRequest(val planId: UUID)

@Service
class SubscriptionService(
    private val subs: SubscriptionRepository,
    private val plans: PlanRepository,
    private val props: AppProperties,
    private val audit: AuditService,
    private val deviceCounter: DeviceCounter,
) {
    fun list(userId: UUID): List<SubscriptionDto> = subs.findByUserIdOrderByCreatedAtDesc(userId).map(::toDto)

    fun get(userId: UUID, id: UUID): Subscription =
        subs.findById(id).filter { it.userId == userId }.orElse(null) ?: notFound("Subscription")

    /**
     * Real purchases arrive in phase 5 through Google Play Billing or a payment provider, and only a
     * verified provider confirmation will activate them. Until then the only path is the dev shortcut.
     */
    @Transactional
    fun create(userId: UUID, planId: UUID): SubscriptionDto {
        val plan = plans.findById(planId).filter { it.active }.orElse(null) ?: notFound("Plan")
        if (!props.billing.allowUnpaidDevSubscriptions) {
            throw ApiException(ErrorCode.PAYMENT_REQUIRED, "Payments are not available yet")
        }
        val now = Instant.now()
        val sub = subs.save(Subscription(userId = userId, planId = plan.id, status = SubscriptionStatus.ACTIVE,
            startsAt = now, expiresAt = plan.billingPeriod.addTo(now), provider = "dev-unpaid"))
        audit.user(userId, "subscription.created", "subscription", sub.id, mapOf("plan" to plan.code, "provider" to "dev-unpaid"))
        return toDto(sub)
    }

    @Transactional
    fun setRenewal(userId: UUID, id: UUID, auto: Boolean): SubscriptionDto {
        val sub = get(userId, id)
        if (auto && sub.provider == "dev-unpaid") {
            throw ApiException(ErrorCode.PAYMENT_REQUIRED, "Automatic renewal needs a payment method")
        }
        sub.renewalStatus = if (auto) RenewalStatus.AUTO else RenewalStatus.OFF
        sub.updatedAt = Instant.now()
        audit.user(userId, if (auto) "subscription.renewal_on" else "subscription.renewal_off", "subscription", id)
        return toDto(sub)
    }

    fun toDto(s: Subscription): SubscriptionDto {
        val plan = plans.findById(s.planId).orElseThrow()
        return SubscriptionDto(s.id, plan.id, plan.name, s.status, s.startsAt, s.expiresAt, s.renewalStatus,
            plan.price, plan.currency, plan.deviceLimit, deviceCounter.countLive(s.id), plan.dataRetentionDays, s.provider)
    }
}

/** Implemented by the devices module so billing does not depend on device internals. */
interface DeviceCounter {
    fun countLive(subscriptionId: UUID): Int
}

@RestController
@RequestMapping("/api/v1")
class BillingController(private val service: SubscriptionService, private val invoices: InvoiceRepository) {
    @GetMapping("/subscriptions")
    fun list(@AuthenticationPrincipal user: AuthUser) = service.list(user.userId)

    @PostMapping("/subscriptions")
    @ResponseStatus(HttpStatus.CREATED)
    fun create(@AuthenticationPrincipal user: AuthUser, @RequestBody body: CreateSubscriptionRequest) =
        service.create(user.userId, body.planId)

    @PostMapping("/subscriptions/{id}/cancel-renewal")
    fun cancelRenewal(@AuthenticationPrincipal user: AuthUser, @PathVariable id: UUID) =
        service.setRenewal(user.userId, id, auto = false)

    @GetMapping("/invoices")
    fun invoices(@AuthenticationPrincipal user: AuthUser) = invoices.findByUserIdOrderByCreatedAtDesc(user.userId)
}
