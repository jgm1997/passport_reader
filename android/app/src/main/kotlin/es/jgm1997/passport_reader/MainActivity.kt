package es.jgm1997.passport_reader

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var integrityProvider: StandardIntegrityTokenProvider? = null

    override fun onCreate(savedInstanceBundle: Bundle?) {
        // Set BEFORE super.onCreate, so even the very first frame is protected
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceBundle)

        // Android 12+: hide other apps' overlay windows while ours is in front (anti-tapjacking)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            window.setHideOverlayWindows(true)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "passport_reader/integrity")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        val raw = call.argument<Any>("cloudProjectNumber")
                        val project = when (raw) {
                            is String -> raw.trim().toLongOrNull()
                            is Number -> raw.toLong()
                            else -> null
                        }
                        if (project == null) {
                            result.error(
                                "BAD_ARGS",
                                "cloudProjectNumber missing or not a number (got ${raw?.javaClass?.simpleName ?: "nothing"})",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        IntegrityManagerFactory.createStandard(applicationContext)
                            .prepareIntegrityToken(
                                PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build()
                            )
                            .addOnSuccessListener { integrityProvider = it; result.success(null) }
                            .addOnFailureListener { result.error("PREPARE_FAILED", it.message, null) }
                    }

                    "request" -> {
                        val provider = integrityProvider
                        val hash = call.argument<String>("requestHash")
                        if (provider == null || hash == null) {
                            result.error("NOT_READY", "Call prepare first", null)
                            return@setMethodCallHandler
                        }
                        provider.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                            .addOnSuccessListener { result.success(it.token()) }
                            .addOnFailureListener { result.error("REQUEST_FAILED", it.message, null) }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
