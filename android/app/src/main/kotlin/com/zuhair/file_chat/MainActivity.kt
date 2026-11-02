package com.zuhair.file_chat

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "file_chat/adblock").setMethodCallHandler { call, result ->
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
