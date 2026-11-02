package com.zuhair.file_chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** Checks for a newer release and tells the user with a phone notification, once per release. */
object Updates {
    private const val CHANNEL = "updates"
    private const val WORK = "update-check"

    fun schedule(ctx: Context, url: String, ar: Boolean) {
        val request = PeriodicWorkRequest.Builder(UpdateWorker::class.java, 6, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInputData(Data.Builder().putString("url", url).putBoolean("ar", ar).build())
            .build()
        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    fun currentBuild(ctx: Context): Long {
        val info = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
    }

    /** Posts the notification unless this release was already announced. */
    fun notifyOnce(ctx: Context, version: String, build: Long, ar: Boolean) {
        val prefs = ctx.getSharedPreferences("updates", Context.MODE_PRIVATE)
        if (build <= currentBuild(ctx) || prefs.getLong("notified", 0) >= build) return
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val title = if (ar) "تحديث جديد متاح" else "Update available"
        val body = if (ar) "الإصدار $version جاهز. اضغط للتحديث." else "Version $version is ready. Tap to update."
        val open = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("openUpdate", true)
        val tap = PendingIntent.getActivity(
            ctx, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, if (ar) "التحديثات" else "Updates", NotificationManager.IMPORTANCE_DEFAULT)
            )
            Notification.Builder(ctx, CHANNEL)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(ctx)
        }
        val n = builder
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        nm.notify(7001, n)
        prefs.edit().putLong("notified", build).apply()
    }
}

class UpdateWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        val url = inputData.getString("url") ?: return Result.success()
        val ar = inputData.getBoolean("ar", true)
        return try {
            val conn = URL("$url?t=${System.currentTimeMillis()}").openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            val json = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
            Updates.notifyOnce(applicationContext, json.optString("version"), json.optLong("build", 0), ar)
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }
}
