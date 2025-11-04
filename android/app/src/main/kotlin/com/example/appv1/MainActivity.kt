package com.example.appv1

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.vonage.clientlibrary.VGCellularRequestClient
import com.vonage.clientlibrary.VGCellularRequestParameters
import org.json.JSONObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.appv1/vonage"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Initialize Vonage SDK
        try {
            VGCellularRequestClient.initializeSdk(applicationContext)
        } catch (e: Exception) {
            e.printStackTrace()
        }
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
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Use reflection to access the internal postWithDataCellular method
                val networkManager = VGCellularRequestClient.getInstance()
                    .javaClass.getDeclaredField("networkManager")
                networkManager.isAccessible = true
                val manager = networkManager.get(VGCellularRequestClient.getInstance())

                // Call postWithDataCellular method
                val postMethod = manager.javaClass.getDeclaredMethod(
                    "postWithDataCellular",
                    java.net.URL::class.java,
                    Map::class.java,
                    String::class.java
                )
                postMethod.isAccessible = true

                val urlObj = java.net.URL(url)
                val response = postMethod.invoke(
                    manager,
                    urlObj,
                    headers ?: emptyMap<String, String>(),
                    body
                ) as JSONObject

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
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error(
                        "CELLULAR_POST_ERROR",
                        "Failed to make cellular POST request: ${e.message}",
                        e.toString()
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }
}
