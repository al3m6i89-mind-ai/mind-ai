package app.nuvola.support

import app.nuvola.auth.AuthUser
import app.nuvola.common.AuditService
import app.nuvola.common.notFound
import app.nuvola.devices.DeviceService
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Id
import jakarta.persistence.Table
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.JdbcTemplate
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
import java.time.Instant
import java.util.UUID

enum class TicketCategory { DEVICE, CONNECTION, BILLING, ACCOUNT, OTHER }
enum class TicketStatus { OPEN, WAITING_FOR_USER, IN_PROGRESS, RESOLVED, CLOSED }

@Entity
@Table(name = "support_tickets")
class SupportTicket(
    @Id val id: UUID = UUID.randomUUID(),
    val ticketNumber: String,
    val userId: UUID,
    @Enumerated(EnumType.STRING) val category: TicketCategory,
    val subject: String,
    val description: String,
    val cloudDeviceId: UUID?,
    @Enumerated(EnumType.STRING) var status: TicketStatus = TicketStatus.OPEN,
    val createdAt: Instant = Instant.now(),
    var updatedAt: Instant = Instant.now(),
)

@Entity
@Table(name = "support_messages")
class SupportMessage(
    @Id val id: UUID = UUID.randomUUID(),
    val ticketId: UUID,
    val authorType: String,
    val authorId: UUID,
    val body: String,
    val createdAt: Instant = Instant.now(),
)

interface SupportTicketRepository : JpaRepository<SupportTicket, UUID> {
    fun findByUserIdOrderByCreatedAtDesc(userId: UUID): List<SupportTicket>
}

interface SupportMessageRepository : JpaRepository<SupportMessage, UUID> {
    fun findByTicketIdOrderByCreatedAt(ticketId: UUID): List<SupportMessage>
}

data class CreateTicketRequest(
    val category: TicketCategory,
    @field:NotBlank @field:Size(max = 150) val subject: String,
    @field:NotBlank @field:Size(max = 5000) val description: String,
    val cloudDeviceId: UUID? = null,
)

data class ReplyRequest(@field:NotBlank @field:Size(max = 5000) val body: String)

data class MessageDto(val id: UUID, val fromSupport: Boolean, val body: String, val createdAt: Instant)
data class TicketDto(
    val id: UUID,
    val ticketNumber: String,
    val category: TicketCategory,
    val subject: String,
    val description: String,
    val cloudDeviceId: UUID?,
    val status: TicketStatus,
    val createdAt: Instant,
    val updatedAt: Instant,
    val messages: List<MessageDto>? = null,
)

@Service
class SupportService(
    private val tickets: SupportTicketRepository,
    private val messages: SupportMessageRepository,
    private val devices: DeviceService,
    private val jdbc: JdbcTemplate,
    private val audit: AuditService,
) {
    fun list(userId: UUID) = tickets.findByUserIdOrderByCreatedAtDesc(userId).map { toDto(it, null) }

    fun get(userId: UUID, id: UUID): TicketDto {
        val t = owned(userId, id)
        return toDto(t, messages.findByTicketIdOrderByCreatedAt(t.id))
    }

    @Transactional
    fun create(userId: UUID, req: CreateTicketRequest): TicketDto {
        req.cloudDeviceId?.let { devices.owned(userId, it) }
        val number = "NV-" + jdbc.queryForObject("SELECT nextval('ticket_number_seq')", Long::class.java)
        val t = tickets.save(SupportTicket(ticketNumber = number, userId = userId, category = req.category,
            subject = req.subject.trim(), description = req.description.trim(), cloudDeviceId = req.cloudDeviceId))
        audit.user(userId, "support.ticket_created", "support_ticket", t.id)
        return toDto(t, emptyList())
    }

    @Transactional
    fun reply(userId: UUID, id: UUID, body: String): TicketDto {
        val t = owned(userId, id)
        messages.save(SupportMessage(ticketId = t.id, authorType = "USER", authorId = userId, body = body.trim()))
        if (t.status == TicketStatus.WAITING_FOR_USER || t.status == TicketStatus.RESOLVED) t.status = TicketStatus.OPEN
        t.updatedAt = Instant.now()
        return get(userId, id)
    }

    private fun owned(userId: UUID, id: UUID) =
        tickets.findById(id).filter { it.userId == userId }.orElse(null) ?: notFound("Ticket")

    private fun toDto(t: SupportTicket, msgs: List<SupportMessage>?) = TicketDto(
        t.id, t.ticketNumber, t.category, t.subject, t.description, t.cloudDeviceId, t.status, t.createdAt, t.updatedAt,
        msgs?.map { MessageDto(it.id, it.authorType == "AGENT", it.body, it.createdAt) },
    )
}

@RestController
@RequestMapping("/api/v1/support/tickets")
class SupportController(private val service: SupportService) {
    @GetMapping
    fun list(@AuthenticationPrincipal u: AuthUser) = service.list(u.userId)

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun create(@AuthenticationPrincipal u: AuthUser, @Valid @RequestBody body: CreateTicketRequest) = service.create(u.userId, body)

    @GetMapping("/{id}")
    fun get(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID) = service.get(u.userId, id)

    @PostMapping("/{id}/messages")
    fun reply(@AuthenticationPrincipal u: AuthUser, @PathVariable id: UUID, @Valid @RequestBody body: ReplyRequest) =
        service.reply(u.userId, id, body.body)
}
