package com.mindai.mind_ai

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

/**
 * Reels helpers on channel "mindai/video":
 *  - thumbnail(path, out): a JPEG cover from a frame about 1 s in.
 *  - compress(path, out): re-encodes to H.264/AAC, at most 720p (short side)
 *    and about 2.5 Mbps, with the phone's hardware encoder (Media3 Transformer).
 *    Returns false when the video is already small enough to upload as is.
 *    Sends "progress" (0..100) back while it works.
 */
@UnstableApi
class VideoTools(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "mindai/video")
    private val main = Handler(Looper.getMainLooper())

    companion object {
        const val SHORT_SIDE = 720
        const val BITRATE = 2_500_000
    }

    init {
        channel.setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            val out = call.argument<String>("out")
            if (path == null || out == null) return@setMethodCallHandler result.error("args", "path and out are required", null)
            when (call.method) {
                "thumbnail" -> thumbnail(path, out, result)
                "compress" -> compress(path, out, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun thumbnail(path: String, out: String, result: MethodChannel.Result) {
        thread {
            try {
                val r = MediaMetadataRetriever()
                r.setDataSource(path)
                val durationMs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                // About 1 s in (or a third of a short clip) avoids black opening frames.
                val atUs = minOf(1_000_000L, durationMs * 1000L / 3)
                val frame = r.getFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: r.getFrameAtTime(0)
                r.release()
                if (frame == null) {
                    main.post { result.success(false) }
                    return@thread
                }
                val scale = minOf(1f, 720f / minOf(frame.width, frame.height))
                val small = if (scale < 1f) {
                    Bitmap.createScaledBitmap(frame, (frame.width * scale).toInt(), (frame.height * scale).toInt(), true)
                } else frame
                FileOutputStream(File(out)).use { small.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                main.post { result.success(true) }
            } catch (e: Exception) {
                main.post { result.error("thumbnail", e.message, null) }
            }
        }
    }

    private fun compress(path: String, out: String, result: MethodChannel.Result) {
        // Measure first: size as shown (rotation applied) and current bitrate.
        var width = 0
        var height = 0
        var bitrate = 0L
        try {
            val r = MediaMetadataRetriever()
            r.setDataSource(path)
            width = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            height = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val w = width
                width = height
                height = w
            }
            bitrate = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L
            r.release()
        } catch (e: Exception) {
            return result.error("compress", "Can't read this video: ${e.message}", null)
        }
        val shortSide = minOf(width, height)
        if (shortSide in 1..SHORT_SIDE && bitrate in 1..(BITRATE * 6L / 5)) {
            return result.success(false) // already light
        }

        val effects = if (shortSide > SHORT_SIDE) {
            // Scale so the short side becomes 720, keeping the shape.
            val target = if (height >= width) height * SHORT_SIDE / width else SHORT_SIDE
            Effects(listOf(), listOf(Presentation.createForHeight(target - target % 2)))
        } else Effects.EMPTY

        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(path))))
            .setEffects(effects)
            .build()
        val encoders = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(BITRATE).build())
            .build()

        val progress = ProgressHolder()
        lateinit var transformer: Transformer
        val tick = object : Runnable {
            override fun run() {
                if (transformer.getProgress(progress) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    channel.invokeMethod("progress", progress.progress)
                }
                main.postDelayed(this, 400)
            }
        }
        transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoders)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    main.removeCallbacks(tick)
                    channel.invokeMethod("progress", 100)
                    result.success(true)
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    main.removeCallbacks(tick)
                    File(out).delete()
                    result.error("compress", exportException.message, null)
                }
            })
            .build()
        File(out).delete()
        transformer.start(item, out)
        main.post(tick)
    }
}
