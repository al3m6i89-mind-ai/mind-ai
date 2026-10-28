package app.nuvola.common

import jakarta.servlet.http.HttpServletRequest

/** Uses the proxy-forwarded address when server.forward-headers-strategy resolves it. */
fun HttpServletRequest.clientIp(): String = remoteAddr ?: "unknown"
