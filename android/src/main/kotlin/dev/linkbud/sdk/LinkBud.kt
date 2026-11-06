package dev.linkbud.sdk

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/** Keep one instance in your Application. Results arrive on the main thread; network/disk work is serialized. */
class LinkBud(context: Context, config: LinkBudConfig) {
    private val app = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor()
    private val analyticsWorker = Executors.newSingleThreadExecutor()
    private var reporting = false
    private val main = Handler(Looper.getMainLooper())
    private val engine by lazy {
        val namespace = digest("${config.base}|${config.applicationId}|${config.environment}|${config.sdkId}|${app.packageName}")
        ResolutionEngine(config, app.packageName, FileStore(File(app.noBackupFilesDir, "linkbud-$namespace.json")), HttpTransport(config))
    }
    private var checkingReferrer = false

    fun handleIntent(intent: Intent?, callback: (LinkBudResult) -> Unit) {
        val url = if (intent?.action == Intent.ACTION_VIEW) intent.dataString else null
        if (url == null) { deliver(callback, LinkBudResult.Empty); return }
        execute(callback) { engine.receiveUrl(url) }
    }

    /** Call at launch, after login and when connectivity returns. Retryable supplies the earliest next attempt. */
    fun resume(callback: (LinkBudResult) -> Unit) {
        execute(callback) {
            if (engine.hasRequest()) engine.retry()
            else if (engine.referrerFinished()) LinkBudResult.Empty
            else {
                main.post { checkReferrer(callback) }
                return@execute null
            }
        }
        worker.execute { flushAnalytics() }
    }

    /** Cached navigation hint, without network validation; use resume before routing after a delay. */
    fun pending(callback: (LinkBudResult) -> Unit) = execute(callback) {
        engine.pending()?.let { LinkBudResult.Pending(it) } ?: LinkBudResult.Empty
    }

    /** Call only after successful authorized navigation. Persists deduplication before invoking completion. */
    fun acknowledge(id: String, completion: (Boolean) -> Unit) {
        worker.execute {
            val acknowledged = try { engine.acknowledge(id) } catch (_: Exception) { false }
            main.post { completion(acknowledged) }
            flushAnalytics()
        }
    }

    /** Report an abandoned destination with a fixed reason; never include app data. */
    fun destinationFailed(id: String, reason: String, completion: (Boolean) -> Unit) {
        worker.execute {
            val saved = try { engine.destinationFailed(id, reason) } catch (_: Exception) { false }
            main.post { completion(saved) }
            flushAnalytics()
        }
    }

    // Disk/state stays on worker; slow analytics delivery must not delay navigation.
    private fun flushAnalytics() {
        if (reporting) return
        val report = runCatching { engine.nextReport() }.getOrNull() ?: return
        reporting = true
        analyticsWorker.execute {
            val response = runCatching { engine.sendReport(report) }.getOrNull()
            worker.execute {
                runCatching { engine.finishReport(report, response) }
                reporting = false
                if (response != null && response.status != 429 && response.status < 500) flushAnalytics()
            }
        }
    }

    private fun execute(callback: (LinkBudResult) -> Unit, task: () -> LinkBudResult?) {
        worker.execute {
            val result = try { task() } catch (_: Exception) { LinkBudResult.Rejected("local_state_failure") }
            if (result != null) deliver(callback, result)
        }
    }
    private fun deliver(callback: (LinkBudResult) -> Unit, result: LinkBudResult) { main.post { callback(result) } }

    private fun checkReferrer(callback: (LinkBudResult) -> Unit) {
        if (checkingReferrer) { deliver(callback, LinkBudResult.Retryable(Instant.now().plusSeconds(30))); return }
        checkingReferrer = true
        val completed = AtomicBoolean(false)
        val client = InstallReferrerClient.newBuilder(app).build()
        val timeout = Runnable {
            if (completed.compareAndSet(false, true)) {
                checkingReferrer = false
                client.endConnection()
                deliver(callback, LinkBudResult.Retryable(Instant.now().plusSeconds(30)))
            }
        }
        fun finish(result: LinkBudResult, terminal: Boolean = false) {
            if (!completed.compareAndSet(false, true)) return
            main.removeCallbacks(timeout)
            main.post { checkingReferrer = false }
            client.endConnection()
            execute(callback) {
                if (terminal) engine.finishReferrer()
                result
            }
        }
        main.postDelayed(timeout, 10000)
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (completed.get()) return
                    when (responseCode) {
                        InstallReferrerClient.InstallReferrerResponse.OK -> {
                            // Binder read and token exchange both run off the UI thread.
                            worker.execute {
                                try {
                                    val referrer = client.installReferrer.installReferrer
                                    if (completed.compareAndSet(false, true)) {
                                        main.removeCallbacks(timeout)
                                        main.post { checkingReferrer = false }
                                        client.endConnection()
                                        val result = try { engine.receiveReferrer(referrer) } catch (_: Exception) { LinkBudResult.Rejected("local_state_failure") }
                                        deliver(callback, result)
                                    }
                                } catch (_: Exception) { finish(LinkBudResult.Retryable(Instant.now().plusSeconds(30))) }
                            }
                        }
                        InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED,
                        InstallReferrerClient.InstallReferrerResponse.PERMISSION_ERROR -> finish(LinkBudResult.Rejected("referrer_unavailable_reopen_link"), true)
                        else -> finish(LinkBudResult.Retryable(Instant.now().plusSeconds(30)))
                    }
                }
                override fun onInstallReferrerServiceDisconnected() {
                    finish(LinkBudResult.Retryable(Instant.now().plusSeconds(30)))
                }
            })
        } catch (_: SecurityException) { finish(LinkBudResult.Rejected("referrer_unavailable_reopen_link"), true) }
        catch (_: RuntimeException) { finish(LinkBudResult.Retryable(Instant.now().plusSeconds(30))) }
    }
}

internal class FileStore(file: File) : PendingStore {
    private val atomic = AtomicFile(file)
    override fun read(): String? = try {
        atomic.openRead().use { input ->
            val bytes = readBounded(input, 65536)
            check(bytes.size <= 65536) { "LinkBud state exceeds size limit" }
            String(bytes, Charsets.UTF_8)
        }
    } catch (_: java.io.FileNotFoundException) { null }
    override fun write(value: String) {
        val output = atomic.startWrite()
        try { output.write(value.toByteArray(Charsets.UTF_8)); atomic.finishWrite(output) }
        catch (failure: Exception) { atomic.failWrite(output); throw failure }
    }
}

internal class HttpTransport(private val config: LinkBudConfig) : Transport {
    override fun post(path: String, body: JSONObject): ApiResponse {
        val connection = URL(config.base + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Cache-Control", "no-store")
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            if (status != 200) return ApiResponse(status, JSONObject(), connection.getHeaderField("Retry-After")?.toLongOrNull() ?: 0)
            val bytes = connection.inputStream.use { readBounded(it, 16384) }
            if (bytes.size > 16384) return ApiResponse(422, JSONObject())
            return try { ApiResponse(status, JSONObject(String(bytes, Charsets.UTF_8))) }
            catch (_: Exception) { ApiResponse(422, JSONObject()) }
        } finally { connection.disconnect() }
    }
}

internal fun readBounded(input: java.io.InputStream, limit: Int): ByteArray {
    val result = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(4096)
    while (result.size() <= limit) {
        val count = input.read(buffer, 0, minOf(buffer.size, limit + 1 - result.size()))
        if (count == -1) break
        result.write(buffer, 0, count)
    }
    return result.toByteArray()
}
