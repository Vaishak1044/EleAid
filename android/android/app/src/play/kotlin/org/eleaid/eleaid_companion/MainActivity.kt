package org.eleaid.eleaid_companion

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "eleaid/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "composeSms" -> composeSms(call.argument<String>("phone"), call.argument<String>("message"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun composeSms(phone: String?, message: String?, result: MethodChannel.Result) {
        if (phone.isNullOrBlank() || message.isNullOrBlank()) {
            result.error("INVALID_SMS", "Phone number and message are required", null)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("smsto:${Uri.encode(phone)}")
                putExtra("sms_body", message.take(300))
            }
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("SMS_COMPOSER_UNAVAILABLE", error.message, null)
        }
    }
}
