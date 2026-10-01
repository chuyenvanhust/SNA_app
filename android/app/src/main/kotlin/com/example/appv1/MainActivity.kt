package com.example.appv1

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.vonage.clientlibrary.VGCellularRequestClient
import com.vonage.clientlibrary.VGCellularRequestParameters
import org.json.JSONObject
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.appv1/vonage"
    private var methodChannel: MethodChannel? = null

    private val TAG = "MainActivity"

    /** Hard timeout for a single cellular request. */
    private val REQUEST_TIMEOUT_MS = 30_000L

    /** Scope for background cellular requests; cancelled in onDestroy. */
    private val requestScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** Cellular POST client pinned to IPv4; see [CellularIPv4Client]. */
    private val ipv4Client by lazy { CellularIPv4Client(applicationContext) }

    /** Channel for the TAS SDK demo (VTNet Number Verification step 1). */
    private val TAS_CHANNEL = "com.example.appv1/tas"
    private var tasChannel: MethodChannel? = null
    private val tasBridge by lazy { TasAuthBridge(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Prevent the Vonage cellular SDK from crashing the whole app when a
        // network call throws on its internal ConnectivityThread (e.g. ETIMEDOUT).
        installCellularCrashGuard()

        // Initialize Vonage SDK
        try {
            VGCellularRequestClient.initializeSdk(applicationContext)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // Initialize TAS SDK with this Activity (it starts the consent page from it)
        try {
            tasBridge.init()
        } catch (e: Exception) {
            Log.w(TAG, "TAS SDK init failed: ${e.message}")
        }
    }

    /**
     * Installs a default uncaught-exception handler that swallows the network
     * errors thrown by the Vonage cellular SDK on its background
     * ConnectivityThread. Without this, a failed cellular connection
     * (e.g. ETIMEDOUT) becomes a FATAL EXCEPTION and kills the process before
     * the request can time out gracefully. All other crashes are delegated to
     * the previously registered handler so real bugs still surface.
     */
    private fun installCellularCrashGuard() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            if (isSuppressibleCellularCrash(thread, throwable)) {
                Log.w(
                    TAG,
                    "Suppressed Vonage cellular crash on thread '${thread.name}': " +
                        "${throwable.message}. The pending request will time out gracefully."
                )
            } else {
                previous?.uncaughtException(thread, throwable)
            }
        }
    }

    private fun isSuppressibleCellularCrash(thread: Thread, throwable: Throwable): Boolean {
        val onConnectivityThread = thread.name.contains("ConnectivityThread", ignoreCase = true)
        val seen = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Throwable, Boolean>())
        var cause: Throwable? = throwable
        while (cause != null && seen.add(cause)) {
            val isNetworkError = cause is java.io.IOException
            val fromVonage = cause.stackTrace.any {
                it.className.startsWith("com.vonage.clientlibrary")
            }
            if (isNetworkError && (onConnectivityThread || fromVonage)) {
                return true
            }
            cause = cause.cause
        }
        return false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "makeCellularRequest" -> {
                    val url = call.argument<String>("url")
                    val headers = call.argument<Map<String, String>>("headers")
                    val body = call.argument<String>("body")
                    val debug = call.argument<Boolean>("debug") ?: false

                    if (url == null) {
                        result.error("INVALID_ARGUMENT", "URL is required", null)
                        return@setMethodCallHandler
                    }

                    makeCellularRequest(url, headers, body, debug, result)
                }
                "makeCellularPostRequest" -> {
                    val url = call.argument<String>("url")
                    val headers = call.argument<Map<String, String>>("headers")
                    val body = call.argument<String>("body")
                    val debug = call.argument<Boolean>("debug") ?: false
                    // Defaults to true: the operator's IPv6 front-end rejects SNA
                    // requests. Pass false from Dart to A/B against the SDK path.
                    val forceIpv4 = call.argument<Boolean>("forceIpv4") ?: true

                    if (url == null) {
                        result.error("INVALID_ARGUMENT", "URL is required", null)
                        return@setMethodCallHandler
                    }

                    makeCellularPostRequest(url, headers, body, debug, forceIpv4, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        tasChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TAS_CHANNEL
        )

        tasChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "authenticate" -> {
                    val authorizeUrl = call.argument<String>("authorizeUrl")
                    if (authorizeUrl.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "authorizeUrl is required", null)
                        return@setMethodCallHandler
                    }
                    tasBridge.authenticate(authorizeUrl, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun makeCellularRequest(
        url: String,
        headers: Map<String, String>?,
        body: String?,
        debug: Boolean,
        result: MethodChannel.Result
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val params = VGCellularRequestParameters(
                    url = url,
                    headers = headers ?: emptyMap(),
                    queryParameters = emptyMap(),
                    maxRedirectCount = 10
                )

                val response = VGCellularRequestClient.getInstance()
                    .startCellularGetRequest(params, debug)

                withContext(Dispatchers.Main) {
                    if (response.optString("error") != "") {
                        // Error response from Vonage SDK
                        val errorMap = mapOf(
                            "error" to response.optString("error"),
                            "error_description" to response.optString("error_description"),
                            "debug" to if (response.has("debug")) {
                                val debugObj = response.getJSONObject("debug")
                                mapOf(
                                    "device_info" to debugObj.optString("device_info"),
                                    "url_trace" to debugObj.optString("url_trace")
                                )
                            } else {
                                emptyMap<String, String>()
                            }
                        )
                        result.success(errorMap)
                    } else {
                        // Success response
                        val httpStatus = response.optInt("http_status")
                        val responseBody = response.optJSONObject("response_body")
                        val rawBody = response.optString("response_raw_body")

                        val responseMap = mutableMapOf<String, Any>(
                            "http_status" to httpStatus
                        )

                        if (responseBody != null) {
                            responseMap["response_body"] = jsonObjectToMap(responseBody)
                        } else if (rawBody.isNotEmpty()) {
                            responseMap["response_raw_body"] = rawBody
                        }

                        if (response.has("debug")) {
                            val debugObj = response.getJSONObject("debug")
                            responseMap["debug"] = mapOf(
                                "device_info" to debugObj.optString("device_info"),
                                "url_trace" to debugObj.optString("url_trace")
                            )
                        }

                        result.success(responseMap)
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error(
                        "CELLULAR_REQUEST_ERROR",
                        "Failed to make cellular request: ${e.message}",
                        e.toString()
                    )
                }
            }
        }
    }

    private fun jsonObjectToMap(jsonObject: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = jsonObject.keys()
        
        while (keys.hasNext()) {
            val key = keys.next()
            val value = jsonObject.get(key)
            
            map[key] = when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                else -> value
            }
        }
        
        return map
    }

    private fun jsonArrayToList(jsonArray: org.json.JSONArray): List<Any> {
        val list = mutableListOf<Any>()
        
        for (i in 0 until jsonArray.length()) {
            val value = jsonArray.get(i)
            
            list.add(when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                else -> value
            })
        }
        
        return list
    }

    private fun makeCellularPostRequest(
        url: String,
        headers: Map<String, String>?,
        body: String?,
        debug: Boolean,
        forceIpv4: Boolean,
        result: MethodChannel.Result
    ) {
        requestScope.launch {
            val response: JSONObject = try {
                runWithTimeout(REQUEST_TIMEOUT_MS) {
                    postOverCellular(url, headers, body, forceIpv4)
                }
            } catch (e: TimeoutException) {
                Log.w(TAG, "Cellular POST timed out after ${REQUEST_TIMEOUT_MS}ms: $url")
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "error" to "sdk_timeout",
                            "error_description" to
                                "Request timed out after ${REQUEST_TIMEOUT_MS / 1000} seconds"
                        )
                    )
                }
                return@launch
            } catch (e: Exception) {
                // Unwrap the reflection/executor wrapper to report the real cause.
                val cause = (e as? ExecutionException)?.cause ?: e
                Log.w(TAG, "Cellular POST failed: ${cause.message}")
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "error" to "sdk_connection_error",
                            "error_description" to
                                (cause.message ?: "Failed to make cellular POST request")
                        )
                    )
                }
                return@launch
            }

            withContext(Dispatchers.Main) {
                if (response.optString("error") != "") {
                    // Error response
                    val errorMap = mapOf(
                        "error" to response.optString("error"),
                        "error_description" to response.optString("error_description")
                    )
                    result.success(errorMap)
                } else {
                    // Success response
                    val httpStatus = response.optInt("http_status")
                    val responseBody = response.optJSONObject("response_body")
                    val rawBody = response.optString("response_raw_body")

                    val responseMap = mutableMapOf<String, Any>(
                        "http_status" to httpStatus
                    )

                    if (responseBody != null) {
                        responseMap["response_body"] = jsonObjectToMap(responseBody)
                    } else if (rawBody.isNotEmpty()) {
                        responseMap["response_raw_body"] = rawBody
                    }

                    result.success(responseMap)
                }
            }
        }
    }

    /**
     * Sends the POST over mobile data, pinned to IPv4 by default.
     *
     * The operator endpoint is dual-stack and its IPv6 front-end answers the SNA
     * request with `400 INVALID_ARGUMENT`, while the byte-identical request over
     * IPv4 is accepted. Android prefers IPv6 and the Vonage SDK lets the system
     * pick, so [CellularIPv4Client] takes over that job. If the carrier hands out
     * no IPv4 route at all, fall back to the SDK rather than failing outright.
     */
    private fun postOverCellular(
        url: String,
        headers: Map<String, String>?,
        body: String?,
        forceIpv4: Boolean
    ): JSONObject {
        val safeHeaders = headers ?: emptyMap()
        if (!forceIpv4) {
            return invokePostWithDataCellular(url, safeHeaders, body)
        }
        return try {
            ipv4Client.post(java.net.URL(url), safeHeaders, body)
        } catch (e: NoIPv4RouteException) {
            Log.w(TAG, "${e.message} - falling back to the Vonage SDK (IPv6 path may fail)")
            invokePostWithDataCellular(url, safeHeaders, body)
        }
    }

    /**
     * Invokes the Vonage SDK's internal postWithDataCellular via reflection.
     * This is a blocking call; run it through [runWithTimeout] so a stuck
     * cellular connection cannot hang the request forever.
     */
    private fun invokePostWithDataCellular(
        url: String,
        headers: Map<String, String>?,
        body: String?
    ): JSONObject {
        val networkManagerField = VGCellularRequestClient.getInstance()
            .javaClass.getDeclaredField("networkManager")
        networkManagerField.isAccessible = true
        val manager = networkManagerField.get(VGCellularRequestClient.getInstance())

        val postMethod = manager.javaClass.getDeclaredMethod(
            "postWithDataCellular",
            java.net.URL::class.java,
            Map::class.java,
            String::class.java
        )
        postMethod.isAccessible = true

        val urlObj = java.net.URL(url)
        return postMethod.invoke(
            manager,
            urlObj,
            headers ?: emptyMap<String, String>(),
            body
        ) as JSONObject
    }

    /**
     * Runs [block] on a dedicated worker thread and aborts with a
     * [TimeoutException] if it does not finish within [timeoutMs]. Guarantees
     * control returns to the caller even when the underlying (native) socket
     * call is stuck waiting on a cellular connection.
     */
    private fun <T> runWithTimeout(timeoutMs: Long, block: () -> T): T {
        val executor = Executors.newSingleThreadExecutor()
        val future = executor.submit(Callable { block() })
        return try {
            future.get(timeoutMs, TimeUnit.MILLISECONDS)
        } finally {
            future.cancel(true)
            executor.shutdownNow()
        }
    }

    override fun onDestroy() {
        requestScope.cancel()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        tasChannel?.setMethodCallHandler(null)
        tasChannel = null
        super.onDestroy()
    }
}
