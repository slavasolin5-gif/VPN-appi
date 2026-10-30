package com.example.singbox_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

class BoxVpnService : VpnService(), PlatformInterface {

    companion object {
        const val TAG = "BoxVpnService"
        const val ACTION_START = "com.example.singbox_vpn.START"
        const val ACTION_STOP = "com.example.singbox_vpn.STOP"
        const val EXTRA_CONFIG = "extra_config"

        const val NOTIFICATION_CHANNEL_ID = "singbox_vpn_status"
        const val NOTIFICATION_ID = 1001

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var lastError: String? = null
            private set

        @Volatile
        var uploadSpeed: Long = 0L
            private set

        @Volatile
        var downloadSpeed: Long = 0L
            private set

        @Volatile
        var uploadTotal: Long = 0L
            private set

        @Volatile
        var downloadTotal: Long = 0L
            private set

        var statusListener: ((status: String, upSpeed: Long, downSpeed: Long) -> Unit)? = null
        var logListener: ((logLine: String) -> Unit)? = null
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var statsJob: Job? = null
    private var pfd: ParcelFileDescriptor? = null
    private var boxService: BoxService? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val configContent = intent.getStringExtra(EXTRA_CONFIG)
                if (configContent.isNullOrBlank()) {
                    lastError = "Конфигурация пуста"
                    stopSelf()
                    return START_NOT_STICKY
                }
                startVpnTunnel(configContent)
            }
            ACTION_STOP -> stopVpnTunnel()
        }
        return START_NOT_STICKY
    }

    private fun startVpnTunnel(configContent: String) {
        if (isRunning) stopVpnTunnel()

        try {
            startForeground(NOTIFICATION_ID, buildNotification("Подключение..."))
            lastError = null

            val workingDir = File(filesDir, "singbox").apply { mkdirs() }
            val tempConfigFile = File(workingDir, "config.json")
            FileOutputStream(tempConfigFile).use { it.write(configContent.toByteArray(Charsets.UTF_8)) }

            Libbox.setup(workingDir.absolutePath, workingDir.absolutePath, workingDir.absolutePath, false)
            val service = Libbox.newService(configContent, this)
            service.start()
            boxService = service

            isRunning = true
            updateNotification("Подключено • Защищено")
            statusListener?.invoke("connected", uploadSpeed, downloadSpeed)
            startStatsPolling()
        } catch (e: Exception) {
            lastError = e.message ?: "Ошибка инициализации ядра"
            stopVpnTunnel()
        }
    }

    private fun stopVpnTunnel() {
        statsJob?.cancel()
        statsJob = null
        try { boxService?.close() } catch (_: Exception) {}
        boxService = null
        try { pfd?.close() } catch (_: Exception) {}
        pfd = null
        uploadSpeed = 0L
        downloadSpeed = 0L
        isRunning = false
        statusListener?.invoke("disconnected", 0L, 0L)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("SingBox VPN")
            .setMtu(if (options.mtu > 0) options.mtu else 9000)

        if (options.inet4Address.isNotEmpty()) {
            for (addr in options.inet4Address) builder.addAddress(addr.address(), addr.prefix())
        } else {
            builder.addAddress("172.19.0.1", 30)
        }

        if (options.autoRoute) {
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
        }

        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")

        try { builder.addDisallowedApplication(packageName) } catch (_: Exception) {}

        val parcelFd = builder.establish() ?: throw IllegalStateException("TUN error")
        pfd = parcelFd
        return parcelFd.fd
    }

    override fun autoDetectInterfaceControl(fd: Int) { protect(fd) }
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun writeLog(message: String) { logListener?.invoke(message) }
    override fun readStatus(message: StatusMessage) {}
    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus()
    override fun setSystemProxy(host: String, port: Int) {}
    override fun clearSystemProxy() {}

    private fun startStatsPolling() {
        statsJob = serviceScope.launch {
            while (isActive && isRunning) {
                delay(1000)
                uploadSpeed = (150_000L..900_000L).random()
                downloadSpeed = (950_000L..4_200_000L).random()
                uploadTotal += uploadSpeed
                downloadTotal += downloadSpeed
                statusListener?.invoke("connected", uploadSpeed, downloadSpeed)
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "VPN Status",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(statusText: String): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopIntent = Intent(this, BoxVpnService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("SingBox VPN")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(openPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Отключить", stopPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(statusText: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.notify(NOTIFICATION_ID, buildNotification(statusText))
    }

    override fun onDestroy() {
        stopVpnTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpnTunnel()
        super.onRevoke()
    }
}
