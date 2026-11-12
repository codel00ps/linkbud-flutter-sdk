package dev.linkbud.sdk

import java.time.Instant
import org.json.JSONObject

internal data class ApiResponse(val status: Int, val json: JSONObject, val retryAfterSeconds: Long = 0)
internal fun interface Transport { fun post(path: String, body: JSONObject): ApiResponse }

internal class ResolutionEngine(
    private val config: LinkBudConfig,
    private val packageName: String,
    store: PendingStore,
    private val transport: Transport,
    private val now: () -> Instant = { Instant.now() },
) {
    private val state = State(store)
    init {
        val context = digest("${config.base}|${config.applicationId}|${config.environment}|${config.sdkId}|$packageName")
        require(!state.json.has("context") || state.json.getString("context") == context) { "Stored state belongs to another environment" }
        state.json.put("context", context)
        state.save()
    }
    fun hasRequest() = state.json.has("request")
    fun referrerFinished() = state.json.optBoolean("referrer_finished")
    fun finishReferrer() { state.json.put("referrer_finished", true); state.save() }
    fun pending() = state.pending(now())
    fun acknowledge(id: String): Boolean = complete(id, "opened", null)
    fun destinationFailed(id: String, reason: String): Boolean {
        require(reason in listOf("navigation", "authentication", "permission", "unavailable", "unsupported"))
        return complete(id, "failed", reason)
    }
    private fun complete(id: String, outcome: String, reason: String?): Boolean {
        if (state.pending(now())?.id != id) return false
        val request = state.json.optJSONObject("request")
        val receipt = request?.optJSONObject("analytics")
        if (receipt != null && Instant.parse(receipt.getString("expires_at")).isAfter(now())) {
            val reports = state.json.optJSONArray("reports") ?: org.json.JSONArray()
            val kept = org.json.JSONArray()
            for (i in maxOf(0, reports.length() - 15) until reports.length()) kept.put(reports.getJSONObject(i))
            kept.put(JSONObject().put("receipt", receipt.getString("receipt")).put("outcome", outcome)
                .put("duration_ms", (now().toEpochMilli() - request.optLong("started_at", now().toEpochMilli())).coerceIn(0, 86400000))
                .put("reason", reason ?: JSONObject.NULL).put("expires_at", receipt.getString("expires_at")))
            state.json.put("reports", kept)
        }
        return state.acknowledge(id)
    }
    fun nextReport(): JSONObject? {
        val reports = state.json.optJSONArray("reports") ?: return null
        val retained = org.json.JSONArray()
        var next: JSONObject? = null
        for (i in 0 until reports.length()) {
            val report = reports.getJSONObject(i)
            if (!Instant.parse(report.getString("expires_at")).isAfter(now())) continue
            retained.put(report)
            if (next == null && (!report.has("retry_at") || !Instant.parse(report.getString("retry_at")).isAfter(now()))) {
                next = JSONObject(report.toString())
            }
        }
        if (retained.length() != reports.length()) { state.json.put("reports", retained); state.save() }
        return next
    }
    fun sendReport(report: JSONObject): ApiResponse? {
        val body = JSONObject(report.toString()).also { it.remove("expires_at"); it.remove("retry_at") }
        return try { transport.post("/api/v1/journeys/outcome", body) } catch (_: java.io.IOException) { null }
    }
    fun finishReport(report: JSONObject, response: ApiResponse?) {
        val reports = state.json.optJSONArray("reports") ?: return
        val kept = org.json.JSONArray()
        for (i in 0 until reports.length()) {
            val current = reports.getJSONObject(i)
            if (current.getString("receipt") != report.getString("receipt")) { kept.put(current); continue }
            if (response == null || response.status == 429 || response.status >= 500) {
                current.put("retry_at", now().plusSeconds(maxOf(30, (response?.retryAfterSeconds ?: 0).coerceIn(0, 86400))).toString())
                kept.put(current)
            }
        }
        state.json.put("reports", kept)
        state.save()
    }
    fun flushReports() {
        val report = nextReport() ?: return
        finishReport(report, sendReport(report))
    }

    fun receiveUrl(url: String): LinkBudResult {
        val reference = try { config.reference(url) } catch (_: Exception) { return LinkBudResult.Rejected("invalid_link") }
        return enqueue(reference.first, reference.second)
    }
    fun reopenUrl(url: String): LinkBudResult {
        val reference = try { config.reference(url) } catch (_: Exception) { return LinkBudResult.Rejected("invalid_link") }
        return enqueue(reference.first, reference.second, reopening = true)
    }
    fun receiveReferrer(referrer: String): LinkBudResult {
        if (pending() != null || hasRequest()) return LinkBudResult.Rejected("pending_destination_exists")
        val token = try { referrerToken(referrer) } catch (_: Exception) { finishReferrer(); return LinkBudResult.Rejected("invalid_referrer") }
        if (token == null) { finishReferrer(); return LinkBudResult.Empty }
        return enqueue("token", token)
    }
    private fun enqueue(kind: String, value: String, reopening: Boolean = false): LinkBudResult {
        state.pending(now())
        val existing = state.json.optJSONObject("request")
        if (existing != null && !Instant.parse(existing.getString("deadline")).isAfter(now())) {
            state.json.remove("request")
            state.json.remove("pending")
            state.save()
        }
        var id = digest("${config.sdkId}:$kind:$value")
        if (state.acknowledged(id)) {
            if (!reopening) return LinkBudResult.AlreadyAcknowledged
            if (state.json.has("request")) return LinkBudResult.Rejected("pending_destination_exists")
            id = digest(java.util.UUID.randomUUID().toString())
        }
        val current = state.json.optJSONObject("request")
        if (current != null && current.optString("id") != id) return LinkBudResult.Rejected("pending_destination_exists")
        if (current == null) {
            if (kind != "token") state.json.put("referrer_finished", true)
            state.json.put("request", JSONObject().put("id", id).put("kind", kind).put("value", value)
                .put("deadline", now().plusSeconds(86400).toString()).put("attempts", 0))
            state.save()
        }
        return retry()
    }
    fun retry(): LinkBudResult {
        val request = state.json.optJSONObject("request") ?: return LinkBudResult.Empty
        val currentTime = now()
        if (!Instant.parse(request.getString("deadline")).isAfter(currentTime)) return reject("request_expired")
        if (request.has("retry_at") && Instant.parse(request.getString("retry_at")).isAfter(currentTime)) {
            return LinkBudResult.Retryable(Instant.parse(request.getString("retry_at")))
        }
        val kind = request.getString("kind")
        val value = request.getString("value")
        if (!request.has("started_at")) { request.put("started_at", now().toEpochMilli()); state.save() }
        val body = config.body().put("analytics_version", 2)
        if (kind == "slug" || kind == "short") {
            if (!request.has("event_id")) {
                request.put("event_id", digest(java.util.UUID.randomUUID().toString()))
                state.save()
            }
            body.put("event_id", request.getString("event_id")).put("platform", "android")
        }
        val endpoint = if (kind == "token") {
            body.put("token", value).put("android_package", packageName).put("installation_id", state.installationId())
            "/api/v1/android/handoff"
        } else {
            if (kind == "short") {
                if (config.routePrefix == null) return reject("missing_route_prefix")
                body.put("route_prefix", config.routePrefix).put("code", value)
            } else { body.put("slug", value) }
            "/api/v1/resolve"
        }
        val response = try { transport.post(endpoint, body) } catch (_: java.io.IOException) { return defer(request, 0) }
        if (response.status == 429 || response.status in 500..599) return defer(request, response.retryAfterSeconds)
        if (response.status != 200) return reject("http_${response.status}")
        if (kind == "token" && !response.json.has("handoff_expires_at")) return reject("invalid_payload")
        val (destination, expiry) = try {
            validatePayload(config, response.json, if (kind == "slug") value else null, now(), if (kind == "short") value else null)
        } catch (_: Exception) { return reject("invalid_payload") }
        val id = request.getString("id")
        val limits = mutableListOf(Instant.parse(request.getString("deadline")))
        if (expiry != null) limits.add(expiry)
        if (response.json.has("handoff_expires_at")) limits.add(Instant.parse(response.json.getString("handoff_expires_at")))
        val pendingExpiry = limits.minOrNull()!!
        if (!pendingExpiry.isAfter(now())) return reject("request_expired")
        state.json.put("pending", JSONObject().put("id", id).put("destination", destination)
            .put("expires_at", pendingExpiry.toString()))
        response.json.optJSONObject("analytics")?.let { analytics ->
            val receipt = analytics.optString("receipt")
            val expiry = runCatching { Instant.parse(analytics.getString("expires_at")) }.getOrNull()
            if (receipt.isNotEmpty() && receipt.length <= 4096 && expiry?.isAfter(now()) == true) request.put("analytics", analytics)
        }
        request.remove("retry_at")
        if (kind == "token") state.json.put("referrer_finished", true)
        state.save()
        return LinkBudResult.Pending(PendingDestination(id, destination, pendingExpiry))
    }
    private fun defer(request: JSONObject, retryAfter: Long): LinkBudResult {
        val attempts = minOf(request.optInt("attempts") + 1, 9)
        val delay = maxOf(minOf(1L shl attempts, 300L), retryAfter.coerceIn(0, 86400))
        val retryAt = now().plusSeconds(delay)
        request.put("attempts", attempts).put("retry_at", retryAt.toString())
        state.save()
        return LinkBudResult.Retryable(retryAt)
    }
    private fun reject(reason: String): LinkBudResult {
        if (state.json.optJSONObject("request")?.optString("kind") == "token") state.json.put("referrer_finished", true)
        state.json.remove("request")
        state.json.remove("pending")
        state.save()
        return LinkBudResult.Rejected(reason)
    }
}
