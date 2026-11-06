package dev.linkbud.flutter

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import dev.linkbud.sdk.LinkBud
import dev.linkbud.sdk.LinkBudConfig
import dev.linkbud.sdk.LinkBudResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class LinkBudFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener {
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private var channel: MethodChannel? = null
    private var activity: ActivityPluginBinding? = null
    private var initialIntent: Intent? = null
    private var sdk: LinkBud? = null
    private var started = false

    companion object {
        // Native storage supports one consumer/engine. Reject a second engine rather than race acknowledgments.
        private var owner: LinkBudFlutterPlugin? = null
        // LinkBud retains applicationContext only; its worker/storage live for the app process.
        @SuppressLint("StaticFieldLeak")
        private var sharedSDK: LinkBud? = null
        private var sharedConfiguration: LinkBudConfig? = null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "dev.linkbud/flutter").also { it.setMethodCallHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        if (owner === this) owner = null
        detachActivity()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addOnNewIntentListener(this)
        if (!started && initialIntent == null && binding.activity.intent?.action == Intent.ACTION_VIEW) {
            initialIntent = binding.activity.intent
        }
    }
    private fun detachActivity() {
        activity?.removeOnNewIntentListener(this)
        activity = null
    }
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()

    override fun onNewIntent(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_VIEW || intent.dataString == null) return false
        activity?.activity?.intent = intent
        val client = sdk
        if (!started || client == null) {
            if (initialIntent == null) initialIntent = intent
        } else {
            client.handleIntent(intent) { channel?.invokeMethod("onResult", encode(it)) }
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "initialize") {
            try {
                val config = LinkBudConfig(required(call, "origin"), required(call, "applicationId"),
                    required(call, "environment"), required(call, "sdkId"), call.argument<String>("routePrefix"))
                if (owner != null && owner !== this) {
                    result.error("engine_in_use", "LinkBud supports one Flutter engine", null); return
                }
                if (sharedConfiguration != null && sharedConfiguration != config) {
                    result.error("configuration_locked", "Restart the app to change environment", null); return
                }
                if (sdk == null) {
                    sdk = sharedSDK ?: LinkBud(binding.applicationContext, config).also { sharedSDK = it }
                    sharedConfiguration = config
                    owner = this
                }
                result.success(null)
            } catch (_: Exception) { result.error("invalid_configuration", "Use valid public environment identifiers and a root HTTPS origin", null) }
            return
        }
        val client = sdk ?: run { result.error("not_initialized", "Initialize LinkBud first", null); return }
        val complete: (LinkBudResult) -> Unit = { result.success(encode(it)) }
        try {
            when (call.method) {
                "start" -> {
                    started = true
                    val intent = initialIntent
                    initialIntent = null
                    if (intent != null) client.handleIntent(intent, complete) else client.resume(complete)
                }
                "handleUrl" -> client.handleIntent(Intent(Intent.ACTION_VIEW, Uri.parse(required(call, "url"))), complete)
                "resume" -> client.resume(complete)
                "pending" -> client.pending(complete)
                "recover" -> result.success(mapOf("status" to "rejected", "reason" to "unsupported_recovery"))
                "acknowledge" -> client.acknowledge(required(call, "id")) { result.success(it) }
                "destinationFailed" -> client.destinationFailed(required(call, "id"), required(call, "reason")) { result.success(it) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) { result.error("invalid_arguments", "Expected string arguments", null) }
    }
    private fun required(call: MethodCall, key: String): String = requireNotNull(call.argument<String>(key))
    private fun encode(result: LinkBudResult): Map<String, Any?> = when (result) {
        is LinkBudResult.Pending -> mapOf("status" to "pending", "id" to result.value.id,
            "destination" to result.value.destination, "expiresAt" to result.value.expiresAt.toString())
        LinkBudResult.Empty -> mapOf("status" to "empty")
        LinkBudResult.AlreadyAcknowledged -> mapOf("status" to "alreadyAcknowledged")
        is LinkBudResult.Retryable -> mapOf("status" to "retryable", "retryAt" to result.retryAt.toString())
        is LinkBudResult.Rejected -> mapOf("status" to "rejected", "reason" to result.reason)
    }
}
