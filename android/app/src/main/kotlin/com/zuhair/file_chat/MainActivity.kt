package com.zuhair.file_chat

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Ad-blocking apps, also listed under <queries> in the manifest so they are visible.
    private val blockers = listOf(
        "com.adguard.android", "com.adguard.android.contentblocker", "com.adguard.vpn",
        "org.blokada.sex", "org.blokada.fem.fdroid", "org.blokada.origin.alarm", "org.blokada.alarm.dnschanger",
        "io.nextdns.NextDNS", "org.jak_linux.dns66", "org.adaway", "dnsfilter.android",
        "com.celzero.bravedns", "eu.faircode.netguard", "com.adlock", "com.controld.setuputility",
        "app.adblockfast", "com.hsv.freeadblockerbrowser", "org.adblockplus.adblockplussbrowser",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updatesChannel(flutterEngine)
        // PDF pages as pictures, so handwriting and drawings on them can be read.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "file_chat/pdf").setMethodCallHandler { call, result ->
            if (call.method != "render") return@setMethodCallHandler result.notImplemented()
            val path = call.argument<String>("path") ?: return@setMethodCallHandler result.success(emptyList<ByteArray>())
            val pages = call.argument<List<Int>>("pages") ?: emptyList()
            val width = call.argument<Int>("width") ?: 1600
            Thread {
                val images = safe { renderPages(path, pages, width) } ?: emptyList()
                runOnUiThread { result.success(images) }
            }.start()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "file_chat/adblock").setMethodCallHandler { call, result ->
            if (call.method == "deviceId") {
                return@setMethodCallHandler result.success(safe { Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) })
            }
            if (call.method != "scan") return@setMethodCallHandler result.notImplemented()
            result.success(
                mapOf(
                    "privateDnsMode" to safe { Settings.Global.getString(contentResolver, "private_dns_mode") },
                    "privateDns" to safe { Settings.Global.getString(contentResolver, "private_dns_specifier") },
                    "vpn" to (safe { vpnActive() } ?: false),
                    "apps" to blockers.filter { installed(it) },
                )
            )
        }
    }

    private var openUpdate = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        openUpdate = intent?.getBooleanExtra("openUpdate", false) ?: false
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("openUpdate", false)) {
            openUpdate = true
            updates?.invokeMethod("openUpdate", null)
        }
    }

    private var updates: MethodChannel? = null

    private fun updatesChannel(engine: FlutterEngine) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "file_chat/updates")
        updates = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    safe { Updates.schedule(applicationContext, call.argument<String>("url")!!, call.argument<Boolean>("ar") ?: true) }
                    result.success(null)
                }
                "notify" -> {
                    safe {
                        Updates.notifyOnce(
                            applicationContext, call.argument<String>("version") ?: "",
                            (call.argument<Number>("build") ?: 0).toLong(), call.argument<Boolean>("ar") ?: true
                        )
                    }
                    result.success(null)
                }
                "askNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
                    ) requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 7002)
                    result.success(null)
                }
                "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    safe {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                        )
                    }
                    result.success(null)
                }
                "takeOpenUpdate" -> {
                    result.success(openUpdate)
                    openUpdate = false
                }
                else -> result.notImplemented()
            }
        }
    }

    /** JPEGs of the given 1-based [pages], [width] pixels wide (pages missing from the file are skipped). */
    private fun renderPages(path: String, pages: List<Int>, width: Int): List<ByteArray> {
        val fd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = PdfRenderer(fd)
        try {
            val out = mutableListOf<ByteArray>()
            for (n in pages) {
                if (n < 1 || n > renderer.pageCount) continue
                val page = renderer.openPage(n - 1)
                try {
                    // Fits within width x 2*width, keeping the page's shape.
                    val scale = minOf(width.toFloat() / page.width, width * 2f / page.height)
                    val w = (page.width * scale).toInt().coerceAtLeast(1)
                    val h = (page.height * scale).toInt().coerceAtLeast(1)
                    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val bytes = ByteArrayOutputStream()
                    bmp.compress(Bitmap.CompressFormat.JPEG, 85, bytes)
                    bmp.recycle()
                    out.add(bytes.toByteArray())
                } finally {
                    page.close()
                }
            }
            return out
        } finally {
            renderer.close()
            fd.close()
        }
    }

    private fun <T> safe(f: () -> T): T? = try { f() } catch (_: Throwable) { null }

    private fun vpnActive(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    }

    private fun installed(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }
}
