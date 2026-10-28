package app.nuvola.common

import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap

/**
 * Sliding-window limiter kept in memory. Good for a single API instance;
 * swap for a Redis-backed limiter before running more than one instance.
 */
class RateLimiter(private val limit: Int, private val window: Duration, private val clock: Clock = Clock.systemUTC()) {
    private val hits = ConcurrentHashMap<String, ArrayDeque<Instant>>()

    fun isBlocked(key: String): Boolean = synchronized(bucket(key)) {
        prune(bucket(key))
        bucket(key).size >= limit
    }

    fun record(key: String) = synchronized(bucket(key)) {
        prune(bucket(key))
        bucket(key).addLast(clock.instant())
    }

    fun reset(key: String) {
        hits.remove(key)
    }

    private fun bucket(key: String) = hits.computeIfAbsent(key) { ArrayDeque() }

    private fun prune(q: ArrayDeque<Instant>) {
        val cutoff = clock.instant().minus(window)
        while (q.isNotEmpty() && q.first().isBefore(cutoff)) q.removeFirst()
    }
}
