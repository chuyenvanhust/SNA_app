package com.example.appv1

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.vcs.tas_sdk.TasSDK
import com.vcs.tas_sdk.model.AuthCallback
import com.vcs.tas_sdk.model.AuthHandler
import com.vcs.tas_sdk.model.TasConfig
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridges the TAS SDK to Flutter for step 1 (authorization code) of the VTNet
 * CAMARA Number Verification flow.
 *
 * The SDK requests the authorize URL over mobile data itself and reports the
 * code that comes back on the registered redirect URL (tas://demo, see
 * AndroidManifest). Steps 2 and 3 (token, device-phone-number) stay in Dart, so
 * [sendAuthorizeCode] only keeps the code and hands it back to Flutter.
 *
 * Notes from the SDK bytecode that shape this class:
 * - [getAuthorizeUrl] is synchronous and may be called more than once per
 *   authentication, so it must return a prepared URL, never hit the network.
 * - AuthCallback runs on an SDK worker thread, so replies are posted to main.
 * - The consent page is started with the SDK's context and no NEW_TASK flag,
 *   so the SDK has to be initialised with an Activity, not the Application.
 */
class TasAuthBridge(private val activity: Activity) : AuthHandler {
    private val TAG = "TasAuthBridge"
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var authorizeUrl: String = ""
    @Volatile private var authorizeCode: String? = null
    @Volatile private var codeMetaData: Map<String, Any> = emptyMap()

    /** Initialises the SDK; debug logs go to logcat (request URL, redirect trace). */
    fun init() {
        TasSDK.getInstance().initSDK(activity, TasConfig(true, false), this)
    }

    override fun getAuthorizeUrl(): String = authorizeUrl

    override suspend fun sendAuthorizeCode(code: String, metaData: Map<String, Any>): Boolean {
        Log.i(TAG, "Authorization code received, metadata keys=${metaData.keys}")
        authorizeCode = code
        codeMetaData = metaData
        return true
    }

    /**
     * Runs the TAS authentication for [url] and replies to [result] exactly once
     * with either {code, state, metadata} or {error, error_description}.
     */
    fun authenticate(url: String, result: MethodChannel.Result) {
        authorizeUrl = url
        authorizeCode = null
        codeMetaData = emptyMap()

        val replied = AtomicBoolean(false)
        fun reply(payload: Map<String, Any?>) {
            if (replied.compareAndSet(false, true)) {
                mainHandler.post { result.success(payload) }
            }
        }

        try {
            TasSDK.getInstance().authenticate(
                AuthCallback(
                    {
                        val metaData = codeMetaData
                        reply(
                            mapOf(
                                "code" to authorizeCode,
                                "state" to metaData["state"]?.toString(),
                                "metadata" to metaData.mapValues { it.value.toString() }
                            )
                        )
                    },
                    { e ->
                        Log.w(TAG, "TAS authentication failed: ${e.code} ${e.message}")
                        reply(
                            mapOf(
                                "error" to e.code.name,
                                "error_description" to e.message
                            )
                        )
                    }
                )
            )
        } catch (e: Exception) {
            // Thrown synchronously when initSDK was not called or the manifest
            // REDIRECT_URL meta-data is missing.
            Log.w(TAG, "TAS authenticate threw: ${e.message}")
            reply(
                mapOf(
                    "error" to "SdkException",
                    "error_description" to (e.message ?: e.toString())
                )
            )
        }
    }
}
