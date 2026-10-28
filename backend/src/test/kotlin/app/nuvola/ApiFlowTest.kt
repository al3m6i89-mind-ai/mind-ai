package app.nuvola

import app.nuvola.auth.UserRepository
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.MvcResult
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ApiFlowTest {
    @Autowired lateinit var mvc: MockMvc
    @Autowired lateinit var json: ObjectMapper
    @Autowired lateinit var users: UserRepository

    private fun body(r: MvcResult): JsonNode = json.readTree(r.response.contentAsString.ifEmpty { "{}" })

    private fun call(req: MockHttpServletRequestBuilder, token: String? = null, payload: Any? = null): MvcResult {
        token?.let { req.header("Authorization", "Bearer $it") }
        payload?.let { req.contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(it)) }
        return mvc.perform(req).andReturn()
    }

    private fun register(verified: Boolean = true): Pair<String, String> {
        val email = "u-${UUID.randomUUID()}@test.dev"
        val r = call(post("/api/v1/auth/register"), payload = mapOf(
            "email" to email, "password" to "secret123", "displayName" to "Test", "acceptTerms" to true))
        assertThat(r.response.status).isEqualTo(201)
        if (verified) users.findByEmail(email)!!.also { it.emailVerified = true; users.save(it) }
        return body(r)["accessToken"].asText() to body(r)["refreshToken"].asText()
    }

    private fun awaitStatus(token: String, id: String, status: String): JsonNode {
        repeat(100) {
            val d = body(call(get("/api/v1/devices/$id"), token))
            if (d["status"].asText() == status && d["pendingAction"] == null) return d
            Thread.sleep(100)
        }
        error("device $id never reached $status")
    }

    @Test
    fun `terms must be accepted and passwords validated on the server`() {
        val r = call(post("/api/v1/auth/register"), payload = mapOf(
            "email" to "x-${UUID.randomUUID()}@test.dev", "password" to "secret123", "displayName" to "X", "acceptTerms" to false))
        assertThat(body(r)["error"]["code"].asText()).isEqualTo("TERMS_NOT_ACCEPTED")
        val weak = call(post("/api/v1/auth/register"), payload = mapOf(
            "email" to "x-${UUID.randomUUID()}@test.dev", "password" to "short", "displayName" to "X", "acceptTerms" to true))
        assertThat(body(weak)["error"]["code"].asText()).isEqualTo("VALIDATION_FAILED")
    }

    @Test
    fun `logout revokes the access token and refresh token reuse ends every session`() {
        val (access, refresh) = register()
        assertThat(call(get("/api/v1/me"), access).response.status).isEqualTo(200)

        val rotated = body(call(post("/api/v1/auth/refresh"), payload = mapOf("refreshToken" to refresh)))
        val access2 = rotated["accessToken"].asText()
        // The old refresh token is replayed: treat as stolen and revoke everything.
        val replay = call(post("/api/v1/auth/refresh"), payload = mapOf("refreshToken" to refresh))
        assertThat(replay.response.status).isEqualTo(401)
        assertThat(call(get("/api/v1/me"), access2).response.status).isEqualTo(401)

        val (a3, _) = register()
        assertThat(call(post("/api/v1/auth/logout"), a3).response.status).isEqualTo(204)
        assertThat(call(get("/api/v1/me"), a3).response.status).isEqualTo(401)
    }

    @Test
    fun `repeated failed logins are rate limited`() {
        val email = "rl-${UUID.randomUUID()}@test.dev"
        val codes = (1..6).map {
            body(call(post("/api/v1/auth/login"), payload = mapOf("email" to email, "password" to "wrong123")))["error"]["code"].asText()
        }
        assertThat(codes.take(5)).allMatch { it == "INVALID_CREDENTIALS" }
        assertThat(codes.last()).isEqualTo("TOO_MANY_ATTEMPTS")
    }

    @Test
    fun `device lifecycle with idempotency, limits, ownership and root`() {
        val (token, _) = register()
        val catalog = body(call(get("/api/v1/catalog")))
        val image = catalog["androidImages"].first { it["androidVersion"].asText() == "12" }
        assertThat(image["simulated"].asBoolean()).isTrue()
        val region = catalog["regions"][0]["id"].asText()
        val starterPlan = body(call(get("/api/v1/plans"))).first { it["code"].asText() == "starter-day" }["id"].asText()

        // No subscription yet.
        val noSub = call(post("/api/v1/devices").header("Idempotency-Key", "k-${UUID.randomUUID()}"), token,
            mapOf("subscriptionId" to UUID.randomUUID(), "androidImageId" to image["id"].asText(), "regionId" to region, "displayName" to "A"))
        assertThat(noSub.response.status).isEqualTo(404)

        val sub = body(call(post("/api/v1/subscriptions"), token, mapOf("planId" to starterPlan)))
        val req = mapOf("subscriptionId" to sub["id"].asText(), "androidImageId" to image["id"].asText(),
            "regionId" to region, "displayName" to "My phone", "rootEnabled" to true)
        val key = "k-${UUID.randomUUID()}"

        val first = call(post("/api/v1/devices").header("Idempotency-Key", key), token, req)
        assertThat(first.response.status).isEqualTo(202)
        val again = call(post("/api/v1/devices").header("Idempotency-Key", key), token, req)
        assertThat(again.response.status).isEqualTo(200)
        val id = body(first)["id"].asText()
        assertThat(body(again)["id"].asText()).isEqualTo(id)
        assertThat(body(first)["status"].asText()).isEqualTo("CREATING")
        assertThat(body(first)["androidVersion"].asText()).isEqualTo("12")
        assertThat(body(first)["rootEnabled"].asBoolean()).isTrue()

        // Starter plan allows one device.
        val second = call(post("/api/v1/devices").header("Idempotency-Key", "k-${UUID.randomUUID()}"), token, req)
        assertThat(body(second)["error"]["code"].asText()).isEqualTo("DEVICE_LIMIT_REACHED")

        awaitStatus(token, id, "RUNNING")
        assertThat(body(call(post("/api/v1/devices/$id/stop"), token))["status"].asText()).isEqualTo("STOPPING")
        val busy = call(post("/api/v1/devices/$id/start"), token)
        assertThat(body(busy)["error"]["code"].asText()).isIn("DEVICE_BUSY", "INVALID_DEVICE_STATE")
        awaitStatus(token, id, "STOPPED")

        call(post("/api/v1/devices/$id/root"), token, mapOf("enabled" to false))
        assertThat(awaitStatus(token, id, "STOPPED")["rootEnabled"].asBoolean()).isFalse()

        call(post("/api/v1/devices/$id/start"), token)
        awaitStatus(token, id, "RUNNING")

        // Streaming is honestly reported as unavailable with the development provider.
        val session = call(post("/api/v1/devices/$id/sessions"), token)
        assertThat(session.response.status).isEqualTo(503)
        assertThat(body(session)["error"]["code"].asText()).isEqualTo("STREAMING_NOT_AVAILABLE")

        // Another user cannot see or control this device.
        val (other, _) = register()
        assertThat(call(get("/api/v1/devices/$id"), other).response.status).isEqualTo(404)
        assertThat(call(post("/api/v1/devices/$id/stop"), other).response.status).isEqualTo(404)

        val dash = body(call(get("/api/v1/dashboard"), token))
        assertThat(dash["runningDevices"].asInt()).isEqualTo(1)
        assertThat(dash["deviceAllowance"].asInt()).isEqualTo(1)

        call(delete("/api/v1/devices/$id"), token)
        repeat(100) {
            if (call(get("/api/v1/devices/$id"), token).response.status == 404) return
            Thread.sleep(100)
        }
        error("device was not deleted")
    }

    @Test
    fun `unverified email cannot create devices and support tickets get numbers`() {
        val (token, _) = register(verified = false)
        val plan = body(call(get("/api/v1/plans")))[0]["id"].asText()
        val sub = body(call(post("/api/v1/subscriptions"), token, mapOf("planId" to plan)))
        val r = call(post("/api/v1/devices").header("Idempotency-Key", "k-${UUID.randomUUID()}"), token,
            mapOf("subscriptionId" to sub["id"].asText(), "androidImageId" to "mock-android-13", "regionId" to "dev-local", "displayName" to "A"))
        assertThat(body(r)["error"]["code"].asText()).isEqualTo("EMAIL_NOT_VERIFIED")

        val t = body(call(post("/api/v1/support/tickets"), token,
            mapOf("category" to "DEVICE", "subject" to "Help", "description" to "It does not start")))
        assertThat(t["ticketNumber"].asText()).startsWith("NV-")
        assertThat(body(call(get("/api/v1/support/tickets"), token)).size()).isEqualTo(1)
    }
}
