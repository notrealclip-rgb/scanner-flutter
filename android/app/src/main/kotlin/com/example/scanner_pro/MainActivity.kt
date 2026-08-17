package com.example.scanner_pro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.nio.charset.Charset

class MainActivity : FlutterActivity() {
    companion object {
        private const val SCAN_ACTION = "com.service.scanner.data"
        private const val SCAN_DATA_KEY = "ScanCode"
        private const val SCAN_BYTES_KEY = "ScanCodeBytes"
        private const val CHANNEL = "com.example.scanner/stream"
    }

    private var scannerReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                unregisterScannerReceiver()

                scannerReceiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        if (intent?.action != SCAN_ACTION) return

                        val barcode = extractBarcode(intent)
                            ?.trim()
                            ?.takeIf { it.isNotEmpty() }

                        if (barcode != null) {
                            events?.success(barcode)
                        }
                    }
                }

                val filter = IntentFilter(SCAN_ACTION)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(
                        scannerReceiver,
                        filter,
                        Context.RECEIVER_EXPORTED
                    )
                } else {
                    @Suppress("DEPRECATION")
                    registerReceiver(scannerReceiver, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                unregisterScannerReceiver()
            }
        })
    }

    private fun extractBarcode(intent: Intent): String? {
        // The M40 scanner is configured to use these exact values:
        // Action: com.service.scanner.data
        // Data label: ScanCode
        val primary = intent.extras?.get(SCAN_DATA_KEY)
        when (primary) {
            is String -> return primary
            is CharSequence -> return primary.toString()
        }

        // Keep the byte label as a fallback. Some scanner firmware versions
        // populate ScanCodeBytes instead of ScanCode.
        val bytes = intent.extras?.get(SCAN_BYTES_KEY)
        if (bytes is ByteArray) {
            return bytes.toString(Charset.forName("UTF-8"))
        }

        return null
    }

    private fun unregisterScannerReceiver() {
        scannerReceiver?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // Receiver was already unregistered or the activity was torn down.
            }
        }
        scannerReceiver = null
    }

    override fun onDestroy() {
        unregisterScannerReceiver()
        super.onDestroy()
    }
}
