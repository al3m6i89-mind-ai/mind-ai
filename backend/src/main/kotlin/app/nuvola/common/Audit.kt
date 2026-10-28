package app.nuvola.common

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import org.hibernate.annotations.JdbcTypeCode
import org.hibernate.type.SqlTypes
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "audit_logs")
class AuditLog(
    @Id val id: UUID = UUID.randomUUID(),
    val actorId: UUID?,
    val actorType: String,
    val action: String,
    val targetType: String,
    val targetId: String?,
    @JdbcTypeCode(SqlTypes.JSON) @Column(columnDefinition = "jsonb")
    val metadata: Map<String, Any?> = emptyMap(),
    val ipAddress: String? = null,
    val createdAt: Instant = Instant.now(),
)

interface AuditLogRepository : JpaRepository<AuditLog, UUID> {
    fun findByTargetTypeAndTargetIdOrderByCreatedAtDesc(targetType: String, targetId: String): List<AuditLog>
}

@Service
class AuditService(private val repo: AuditLogRepository) {
    fun user(actor: UUID, action: String, targetType: String, targetId: Any?, metadata: Map<String, Any?> = emptyMap()) {
        repo.save(AuditLog(actorId = actor, actorType = "USER", action = action, targetType = targetType,
            targetId = targetId?.toString(), metadata = metadata))
    }

    fun system(action: String, targetType: String, targetId: Any?, metadata: Map<String, Any?> = emptyMap()) {
        repo.save(AuditLog(actorId = null, actorType = "SYSTEM", action = action, targetType = targetType,
            targetId = targetId?.toString(), metadata = metadata))
    }
}
