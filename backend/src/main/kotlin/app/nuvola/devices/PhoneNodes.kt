package app.nuvola.devices

import app.nuvola.common.ApiException
import app.nuvola.common.ErrorCode
import app.nuvola.config.AppProperties
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.http.HttpStatus
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.net.URI
import java.security.MessageDigest
import java.time.Instant

@Entity
@Table(name = "phone_nodes")
class PhoneNode(
    @Id val id: String,
    var publicUrl: String,
    var lastSeenAt: Instant,
)

interface PhoneNodeRepository : JpaRepository<PhoneNode, String>

data class NodeHeartbeat(val url: String)

/** The phone server calls this every minute with its current public address. */
@RestController
@RequestMapping("/api/v1/nodes")
class PhoneNodeController(private val nodes: PhoneNodeRepository, private val props: AppProperties) {
    @PostMapping("/heartbeat")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    fun heartbeat(@RequestHeader("X-Node-Token", required = false) token: String?, @RequestBody body: NodeHeartbeat) {
        val expected = props.devices.redroid.nodeToken
        if (expected.isBlank() || token == null || !MessageDigest.isEqual(token.toByteArray(), expected.toByteArray())) {
            throw ApiException(ErrorCode.UNAUTHENTICATED, "Unknown phone server")
        }
        val url = runCatching { URI(body.url) }.getOrNull()
        if (url?.scheme != "https" || url.host.isNullOrBlank() || body.url.length > 300) {
            throw ApiException(ErrorCode.VALIDATION_FAILED, "The phone server must report an https address")
        }
        val node = nodes.findById(MAIN).orElse(null)
        if (node == null) nodes.save(PhoneNode(MAIN, body.url, Instant.now()))
        else { node.publicUrl = body.url; node.lastSeenAt = Instant.now() }
    }

    companion object { const val MAIN = "main" }
}
