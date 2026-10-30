package com.example.singbox_vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "com.example.singbox_vpn/channel"
        const val EVENT_CHANNEL_STATS = "com.example.singbox_vpn/stats"
        const val EVENT_CHANNEL_LOGS = "com.example.singbox_vpn/logs"
        const val REQUEST_CODE_VPN_PERMISSION = 24601
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfigJson: String? = null
    private var statsEventSink: EventChannel.EventSink? = null
    private var logsEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_STATS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    statsEventSink = events
                }
                override fun onCancel(arguments: Any?) { statsEventSink = null }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_LOGS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    logsEventSink = events
                }
                override fun onCancel(arguments: Any?) { logsEventSink = null }
            })

        BoxVpnService.statusListener = { status, upSpeed, downSpeed ->
            runOnUiThread {
                statsEventSink?.success(
                    mapOf(
                        "status" to status,
                        "uploadSpeed" to upSpeed,
                        "downloadSpeed" to downSpeed,
                        "uploadTotal" to BoxVpnService.uploadTotal,
                        "downloadTotal" to BoxVpnService.downloadTotal
                    )
                )
            }
        }

        BoxVpnService.logListener = { logLine ->
            runOnUiThread { logsEventSink?.success(logLine) }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startVpn" -> {
                val configJson = call.argument<String>("config")
                if (configJson.isNullOrBlank()) {
                    result.error("INVALID_CONFIG", "Конфигурация пуста", null)
                    return
                }

                val prepareIntent = VpnService.prepare(this)
                if (prepareIntent != null) {
                    pendingResult = result
                    pendingConfigJson = configJson
                    startActivityForResult(prepareIntent, REQUEST_CODE_VPN_PERMISSION)
                } else {
                    startServiceWithConfig(configJson)
                    result.success(true)
                }
            }
            "stopVpn" -> {
                val intent = Intent(this, BoxVpnService::class.java).apply {
                    action = BoxVpnService.ACTION_STOP
                }
                startService(intent)
                result.success(true)
            }
            "getVpnStatus" -> {
                result.success(
                    mapOf(
                        "isRunning" to BoxVpnService.isRunning,
                        "lastError" to BoxVpnService.lastError,
                        "uploadSpeed" to BoxVpnService.uploadSpeed,
                        "downloadSpeed" to BoxVpnService.downloadSpeed
                    )
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun startServiceWithConfig(config: String) {
        val intent = Intent(this, BoxVpnService::class.java).apply {
            action = BoxVpnService.ACTION_START
            putExtra(BoxVpnService.EXTRA_CONFIG, config)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_VPN_PERMISSION) {
            if (resultCode == Activity.RESULT_OK) {
                pendingConfigJson?.let { startServiceWithConfig(it) }
                pendingResult?.success(true)
            } else {
                pendingResult?.error("PERMISSION_DENIED", "Отказ в правах VPN", null)
            }
            pendingResult = null
            pendingConfigJson = null
        }
    }
}
