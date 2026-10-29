package app.nuvola

import app.nuvola.devices.PhoneNodeRepository
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post

@SpringBootTest(properties = ["app.devices.redroid.node-token=0123456789abcdef0123456789abcdef"])
@AutoConfigureMockMvc
@ActiveProfiles("test")
class NodeHeartbeatTest {
    @Autowired lateinit var mvc: MockMvc
    @Autowired lateinit var nodes: PhoneNodeRepository

    private fun beat(token: String?, url: String) = mvc.perform(
        post("/api/v1/nodes/heartbeat").contentType(MediaType.APPLICATION_JSON).content("""{"url":"$url"}""")
            .apply { if (token != null) header("X-Node-Token", token) }
    ).andReturn().response.status

    @Test
    fun `only the phone server with the right token can report its address`() {
        assertThat(beat(null, "https://a.example")).isEqualTo(401)
        assertThat(beat("wrong", "https://a.example")).isEqualTo(401)
        assertThat(beat("0123456789abcdef0123456789abcdef", "http://plain.example")).isEqualTo(400)
        assertThat(beat("0123456789abcdef0123456789abcdef", "https://one.trycloudflare.com")).isEqualTo(204)
        assertThat(beat("0123456789abcdef0123456789abcdef", "https://two.trycloudflare.com")).isEqualTo(204)
        assertThat(nodes.findById("main").get().publicUrl).isEqualTo("https://two.trycloudflare.com")
    }
}
