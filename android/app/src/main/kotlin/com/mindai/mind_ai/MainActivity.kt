package com.mindai.mind_ai

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Pulls evenly spaced frames out of a video so Dart can key out the
        // background and build a transparent animated gift.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mindai/frames").setMethodCallHandler { call, result ->
            if (call.method != "extract") return@setMethodCallHandler result.notImplemented()
            val path = call.argument<String>("path")!!
            val count = call.argument<Int>("count") ?: 24
            val maxSize = call.argument<Int>("maxSize") ?: 512
            thread {
                try {
                    val r = MediaMetadataRetriever()
                    r.setDataSource(path)
                    val durationMs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L
                    val frames = ArrayList<ByteArray>()
                    for (i in 0 until count) {
                        val us = durationMs * 1000L * i / count
                        val bmp = r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST) ?: continue
                        val scale = minOf(1f, maxSize.toFloat() / maxOf(bmp.width, bmp.height))
                        val small = if (scale < 1f) {
                            Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
                        } else bmp
                        val out = ByteArrayOutputStream()
                        small.compress(Bitmap.CompressFormat.PNG, 100, out)
                        frames.add(out.toByteArray())
                    }
                    r.release()
                    runOnUiThread { result.success(frames) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("frames", e.message, null) }
                }
            }
        }
    }
}
