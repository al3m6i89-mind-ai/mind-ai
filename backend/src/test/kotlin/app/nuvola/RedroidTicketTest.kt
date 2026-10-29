package app.nuvola

import app.nuvola.devices.PhoneNodeRepository
import app.nuvola.devices.RedroidProvider
import app.nuvola.config.AppProperties
import com.fasterxml.jackson.databind.ObjectMapper
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import java.time.Instant

@SpringBootTest
@ActiveProfiles("test")
class RedroidTicketTest {
    @Autowired lateinit var props: AppProperties
    @Autowired lateinit var mapper: ObjectMapper
    @Autowired lateinit var nodes: PhoneNodeRepository

    /** The node agent (Go) must accept tickets signed here; the expected value comes from node-agent's signTicket. */
    @Test
    fun `ticket matches the node agent format`() {
        val node = props.devices.redroid.copy(nodeUrl = "https://node.example", nodeToken = "0123456789abcdef0123456789abcdef")
        val provider = RedroidProvider(props.copy(devices = props.devices.copy(redroid = node)), mapper, nodes)
        assertEquals(
            "v1.nv0123456789.1800000000.k2Zww5EHqDLAhQ5zSwIx2FPiONRzFx1nqRT498g7G2E",
            provider.ticket("nv0123456789", Instant.ofEpochSecond(1_800_000_000)),
        )
        assertEquals("wss://node.example/v1/stream/nv0123456789",
            provider.issueConnection("nv0123456789", java.time.Duration.ofSeconds(60)).gatewayUrl)
    }
}
