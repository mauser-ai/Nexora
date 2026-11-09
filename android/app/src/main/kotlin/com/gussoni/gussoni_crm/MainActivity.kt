package com.gussoni.gussoni_crm

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "nexora/tap_to_pay"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "checkAvailability" -> {
            result.success(
              mapOf(
                "supported" to false,
                "platform" to "android",
                "reason" to "Bridge Tap to Pay pronto, ma SDK Stripe Terminal Android non ancora collegata in questa build."
              )
            )
          }

          "startPayment" -> {
            result.error(
              "tap_to_pay_not_configured",
              "Stripe Terminal Android non e ancora configurato nel layer nativo di questa build.",
              null
            )
          }

          else -> result.notImplemented()
        }
      }
  }
}
