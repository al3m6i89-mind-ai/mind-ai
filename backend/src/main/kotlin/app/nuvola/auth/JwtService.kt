package app.nuvola.auth

import app.nuvola.config.AppProperties
import com.nimbusds.jose.jwk.source.ImmutableSecret
import org.springframework.security.oauth2.jose.jws.MacAlgorithm
import org.springframework.security.oauth2.jwt.JwsHeader
import org.springframework.security.oauth2.jwt.JwtClaimsSet
import org.springframework.security.oauth2.jwt.JwtDecoder
import org.springframework.security.oauth2.jwt.JwtEncoderParameters
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.UUID
import javax.crypto.spec.SecretKeySpec

@Service
class JwtService(private val props: AppProperties) {
    private val key = SecretKeySpec(props.security.jwtSecret.toByteArray(), "HmacSHA256")
    private val encoder = NimbusJwtEncoder(ImmutableSecret(key))
    val decoder: JwtDecoder = NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build()

    fun issueAccessToken(user: User, sessionId: UUID): Pair<String, Instant> {
        val now = Instant.now()
        val expires = now.plus(props.security.accessTokenTtl)
        val claims = JwtClaimsSet.builder()
            .issuer("nuvola")
            .subject(user.id.toString())
            .issuedAt(now)
            .expiresAt(expires)
            .claim("sid", sessionId.toString())
            .claim("role", user.role.name)
            .build()
        val header = JwsHeader.with(MacAlgorithm.HS256).build()
        return encoder.encode(JwtEncoderParameters.from(header, claims)).tokenValue to expires
    }
}
