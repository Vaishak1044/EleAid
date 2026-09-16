package org.eleaid.eleaid_companion

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "eleaid/native"
    private val smsRequestCode = 4081
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermission" -> requestSmsPermission(result)
                "sendSms" -> sendSms(call.argument<String>("phone"), call.argument<String>("message"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.SEND_SMS), smsRequestCode)
    }

    private fun sendSms(phone: String?, message: String?, result: MethodChannel.Result) {
        if (phone.isNullOrBlank() || message.isNullOrBlank()) {
            result.error("INVALID_SMS", "Phone number and message are required", null)
            return
        }
        if (checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            result.error("SMS_PERMISSION", "SEND_SMS permission is not granted", null)
            return
        }
        try {
            SmsManager.getDefault().sendTextMessage(phone, null, message.take(300), null, null)
            result.success(true)
        } catch (error: Exception) {
            result.error("SMS_FAILED", error.message, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == smsRequestCode) {
            pendingPermissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermissionResult = null
        }
    }
}
