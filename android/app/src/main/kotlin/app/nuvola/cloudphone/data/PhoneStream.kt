package app.nuvola.cloudphone.data

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.view.Surface
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

@Serializable
private data class StreamMeta(val type: String, val codec: String, val width: Int, val height: Int)

/**
 * Live connection to one cloud phone on its node: H.264 video in, scrcpy control messages out.
 * Video is decoded with MediaCodec straight onto the screen's Surface.
 */
class PhoneStream(private val url: String, private val listener: Listener) {
    interface Listener {
        fun onVideoSize(width: Int, height: Int)
        fun onFirstFrame()
        fun onEnded(failed: Boolean)
    }

    private class Packet(val data: ByteArray, val ptsUs: Long, val config: Boolean, val key: Boolean)

    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()
    private var socket: WebSocket? = null
    private val packets = LinkedBlockingQueue<Packet>(240)
    @Volatile private var resync = false
    @Volatile private var closed = false
    @Volatile private var configPacket: ByteArray? = null
    @Volatile private var surface: Surface? = null
    @Volatile private var decoder: Thread? = null

    /** Size of the phone screen in the video, which is also the coordinate space for touches. */
    @Volatile var videoWidth = 0; private set
    @Volatile var videoHeight = 0; private set

    fun start() {
        socket = client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val meta = runCatching { json.decodeFromString<StreamMeta>(text) }.getOrNull() ?: return
                setSize(meta.width, meta.height)
                startDecoderIfReady()
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (bytes.size < 12) return
                val head = ByteBuffer.wrap(bytes.substring(0, 12).toByteArray())
                val flags = head.long
                val packet = Packet(
                    data = bytes.substring(12).toByteArray(),
                    ptsUs = flags and 0x3FFF_FFFF_FFFF_FFFFL,
                    config = flags < 0,
                    key = (flags ushr 62) and 1L == 1L,
                )
                if (packet.config) configPacket = packet.data
                if (!packets.offer(packet)) { // the decoder fell behind: drop and restart from the next key frame
                    packets.clear()
                    resync = true
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = end(failed = code != 1000)
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = end(failed = true)
        })
    }

    fun attachSurface(s: Surface) {
        surface = s
        startDecoderIfReady()
    }

    fun detachSurface() {
        surface = null
        stopDecoder()
    }

    /** Sends one pointer of a touch: action is MotionEvent.ACTION_DOWN, ACTION_UP or ACTION_MOVE. */
    fun touch(action: Int, pointerId: Long, x: Int, y: Int) {
        val w = videoWidth
        val h = videoHeight
        if (w == 0) return
        val b = ByteBuffer.allocate(32).order(ByteOrder.BIG_ENDIAN)
        b.put(2).put(action.toByte()).putLong(pointerId)
        b.putInt(x.coerceIn(0, w - 1)).putInt(y.coerceIn(0, h - 1)).putShort(w.toShort()).putShort(h.toShort())
        b.putShort(if (action == 1) 0 else 0xFFFF.toShort()).putInt(0).putInt(0)
        socket?.send(b.array().toByteString())
    }

    /** Presses and releases an Android key (KEYCODE_BACK, KEYCODE_HOME, ...). */
    fun key(keycode: Int) {
        for (action in 0..1) {
            val b = ByteBuffer.allocate(14).order(ByteOrder.BIG_ENDIAN)
            b.put(0).put(action.toByte()).putInt(keycode).putInt(0).putInt(0)
            socket?.send(b.array().toByteString())
        }
    }

    fun close() {
        closed = true
        socket?.close(1000, null)
        stopDecoder()
        client.dispatcher.executorService.shutdown()
    }

    private fun end(failed: Boolean) {
        if (closed) return
        closed = true
        stopDecoder()
        listener.onEnded(failed)
    }

    private fun setSize(w: Int, h: Int) {
        if (w <= 0 || h <= 0 || (w == videoWidth && h == videoHeight)) return
        videoWidth = w
        videoHeight = h
        listener.onVideoSize(w, h)
    }

    @Synchronized
    private fun startDecoderIfReady() {
        val s = surface ?: return
        if (closed || decoder != null || videoWidth == 0) return
        decoder = Thread({ decode(s) }, "phone-decoder").apply { start() }
    }

    @Synchronized
    private fun stopDecoder() {
        val t = decoder ?: return
        decoder = null
        t.interrupt()
        if (Thread.currentThread() != t) t.join(1000)
    }

    private fun decode(target: Surface) {
        val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        try {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, videoWidth, videoHeight)
            if (Build.VERSION.SDK_INT >= 30) format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            codec.configure(format, target, null, 0)
            codec.start()
            configPacket?.let { feed(codec, it, 0, MediaCodec.BUFFER_FLAG_CODEC_CONFIG) }
            var waitingForKey = true
            var rendered = false
            val info = MediaCodec.BufferInfo()
            while (!Thread.currentThread().isInterrupted) {
                if (resync) { resync = false; waitingForKey = true }
                val p = packets.poll(10, TimeUnit.MILLISECONDS)
                when {
                    p == null -> {}
                    p.config -> feed(codec, p.data, 0, MediaCodec.BUFFER_FLAG_CODEC_CONFIG)
                    waitingForKey && !p.key -> {}
                    else -> {
                        val ok = feed(codec, p.data, p.ptsUs, if (p.key) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                        waitingForKey = !ok
                    }
                }
                while (true) {
                    val idx = codec.dequeueOutputBuffer(info, 0)
                    if (idx >= 0) {
                        codec.releaseOutputBuffer(idx, true)
                        if (!rendered) { rendered = true; listener.onFirstFrame() }
                    } else if (idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val f = codec.outputFormat
                        val w = if (f.containsKey("crop-right")) f.getInteger("crop-right") - f.getInteger("crop-left") + 1 else f.getInteger(MediaFormat.KEY_WIDTH)
                        val h = if (f.containsKey("crop-bottom")) f.getInteger("crop-bottom") - f.getInteger("crop-top") + 1 else f.getInteger(MediaFormat.KEY_HEIGHT)
                        setSize(w, h)
                    } else break
                }
            }
        } catch (_: InterruptedException) {
        } catch (e: Exception) {
            if (!closed && surface != null) end(failed = true)
        } finally {
            runCatching { codec.stop() }
            codec.release()
        }
    }

    private fun feed(codec: MediaCodec, data: ByteArray, ptsUs: Long, flags: Int): Boolean {
        val idx = codec.dequeueInputBuffer(20_000)
        if (idx < 0) return false
        val buf = codec.getInputBuffer(idx) ?: return false
        if (data.size > buf.capacity()) {
            codec.queueInputBuffer(idx, 0, 0, ptsUs, 0)
            return false
        }
        buf.clear()
        buf.put(data)
        codec.queueInputBuffer(idx, 0, data.size, ptsUs, flags)
        return true
    }
}
