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

                    if (url == null) {
                        result.error("INVALID_ARGUMENT", "URL is required", null)
                        return@setMethodCallHandler
                    }

                    makeCellularPostRequest(url, headers, body, debug, result)
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
        result: MethodChannel.Result
    ) {
        requestScope.launch {
            val response: JSONObject = try {
                runWithTimeout(REQUEST_TIMEOUT_MS) {
                    invokePostWithDataCellular(url, headers, body)
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
        super.onDestroy()
    }
}
