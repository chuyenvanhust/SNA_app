package com.example.appv1

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/** Thrown when the cellular network offers no IPv4 route to the host. */
class NoIPv4RouteException(message: String) : IOException(message)

/**
 * POSTs over the mobile-data network with the connection pinned to IPv4.
 *
 * The operator endpoint is dual-stack, but its IPv6 front-end rejects the SNA
 * request with `400 INVALID_ARGUMENT` while the byte-identical request over IPv4
 * is accepted (verified with curl from a machine on the same carrier). Android
 * prefers IPv6 whenever the mobile interface has a global v6 address and the
 * Vonage SDK lets the system choose, so every request landed on the broken path.
 *
 * The raw request is written exactly the way the Vonage client writes it
 * (`CellularClient.makePost`) so the server sees the same bytes, with one
 * correction: `Content-Length` counts bytes rather than characters.
 */
class CellularIPv4Client(private val context: Context) {

    companion object {
        private const val TAG = "CellularIPv4Client"
        private const val NETWORK_TIMEOUT_MS = 10_000L
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 20_000
    }

    /**
     * Acquires the cellular network, then performs the POST on it.
     *
     * @throws NoIPv4RouteException when the host has no IPv4 address on this network
     * @throws IOException on any connection, TLS or protocol failure
     */
    fun post(url: URL, headers: Map<String, String>, body: String?): JSONObject {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val holder = AtomicReference<Network?>()
        val latch = CountDownLatch(1)

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                holder.set(network)
                latch.countDown()
            }

            override fun onUnavailable() {
                latch.countDown()
            }
        }

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                cm.requestNetwork(request, callback, NETWORK_TIMEOUT_MS.toInt())
            } else {
                cm.requestNetwork(request, callback)
            }

            if (!latch.await(NETWORK_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                throw IOException("Timed out waiting for the cellular network")
            }
            val network = holder.get()
                ?: throw IOException("Cellular network unavailable (mobile data off?)")

            return postOn(network, url, headers, body)
        } finally {
            runCatching { cm.unregisterNetworkCallback(callback) }
        }
    }

    private fun postOn(
        network: Network,
        url: URL,
        headers: Map<String, String>,
        body: String?
    ): JSONObject {
        val host = url.host
        val secure = url.protocol.equals("https", ignoreCase = true)
        val port = if (url.port > 0) url.port else if (secure) 443 else 80

        // Resolve through the cellular network's own DNS, then keep IPv4 only.
        val addresses = network.getAllByName(host)
        val ipv4 = addresses.firstOrNull { it is Inet4Address }
            ?: throw NoIPv4RouteException(
                "$host has no IPv4 address on the cellular network " +
                    "(got: ${addresses.joinToString { a -> a.hostAddress ?: "?" }})"
            )
        Log.d(TAG, "Pinned $host -> ${ipv4.hostAddress}:$port (IPv4, cellular)")

        var socket: Socket = network.socketFactory.createSocket()
        try {
            socket.connect(InetSocketAddress(ipv4, port), CONNECT_TIMEOUT_MS)
            socket.soTimeout = READ_TIMEOUT_MS
            if (secure) {
                socket = startTls(socket, host, port)
            }

            val requestBytes = buildRequest(url, headers, body)
            Log.d(TAG, "Sending:\n${String(requestBytes, Charsets.UTF_8)}")
            socket.getOutputStream().apply {
                write(requestBytes)
                flush()
            }

            val raw = readUntilClose(socket.getInputStream())
            Log.d(TAG, "Response:\n${String(raw, Charsets.UTF_8)}")
            return parseResponse(raw)
        } finally {
            runCatching { socket.close() }
        }
    }

    /**
     * Layers TLS over the already connected cellular socket. Passing [host] to
     * `createSocket` is what makes the SNI extension carry the hostname even
     * though the socket is connected to a raw IPv4 address.
     */
    private fun startTls(plain: Socket, host: String, port: Int): SSLSocket {
        val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory)
            .createSocket(plain, host, port, true) as SSLSocket

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            ssl.sslParameters = ssl.sslParameters.apply {
                serverNames = listOf(SNIHostName(host))
            }
        }
        ssl.soTimeout = READ_TIMEOUT_MS
        ssl.startHandshake()

        if (!HttpsURLConnection.getDefaultHostnameVerifier().verify(host, ssl.session)) {
            throw IOException("TLS hostname verification failed for $host")
        }
        return ssl
    }

    private fun buildRequest(
        url: URL,
        headers: Map<String, String>,
        body: String?
    ): ByteArray {
        val path = url.path.ifEmpty { "/" }
        val query = url.query?.let { "?$it" }.orEmpty()
        val bodyBytes = body?.toByteArray(Charsets.UTF_8) ?: ByteArray(0)

        val head = StringBuilder()
        head.append("POST ").append(path).append(query).append(" HTTP/1.1\r\n")
        head.append("Host: ").append(url.host).append("\r\n")
        // Headers below are computed here, so drop any caller-supplied copies.
        val reserved = setOf("host", "content-length", "connection")
        headers.forEach { (key, value) ->
            if (key.lowercase() !in reserved) {
                head.append(key).append(": ").append(value).append("\r\n")
            }
        }
        head.append("Content-Length: ").append(bodyBytes.size).append("\r\n")
        head.append("Connection: close\r\n\r\n")

        return head.toString().toByteArray(Charsets.UTF_8) + bodyBytes
    }

    private fun readUntilClose(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val read = input.read(buffer)
            if (read == -1) break
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    /** Converts the raw response into the JSON shape the Vonage SDK returns. */
    private fun parseResponse(raw: ByteArray): JSONObject {
        val text = String(raw, Charsets.UTF_8)
        val separator = text.indexOf("\r\n\r\n")
        val head = if (separator >= 0) text.substring(0, separator) else text
        var payload = if (separator >= 0) text.substring(separator + 4) else ""

        val headLines = head.split("\r\n")
        val statusLine = headLines.firstOrNull().orEmpty()
        val status = Regex("""HTTP/\d\.\d\s+(\d{3})""").find(statusLine)
            ?.groupValues?.get(1)?.toIntOrNull()
            ?: throw IOException("Malformed status line: '$statusLine'")

        val chunked = headLines.drop(1).any {
            it.startsWith("Transfer-Encoding", ignoreCase = true) &&
                it.contains("chunked", ignoreCase = true)
        }
        if (chunked) {
            payload = dechunk(payload)
        }

        val result = JSONObject().put("http_status", status)
        val trimmed = payload.trim()
        val json = runCatching { JSONObject(trimmed) }.getOrNull()
        when {
            json != null -> result.put("response_body", json)
            trimmed.isNotEmpty() -> result.put("response_raw_body", trimmed)
        }
        return result
    }

    private fun dechunk(payload: String): String {
        val out = StringBuilder()
        var rest = payload
        while (true) {
            val lineEnd = rest.indexOf("\r\n")
            if (lineEnd < 0) break
            val size = rest.substring(0, lineEnd).substringBefore(';').trim()
                .toIntOrNull(16) ?: break
            if (size == 0) break
            val start = lineEnd + 2
            val end = minOf(start + size, rest.length)
            out.append(rest, start, end)
            rest = if (end + 2 <= rest.length) rest.substring(end + 2) else ""
        }
        return out.toString()
    }
}
