package dev.linkbud.sdk

import org.json.JSONObject
import java.time.Instant
import java.util.UUID

internal interface PendingStore {
    fun read(): String?
    fun write(value: String)
}

internal class State(private val store: PendingStore) {
    private var storageFailed = false
    val json: JSONObject = store.read()?.let { JSONObject(it) } ?: JSONObject()
        get() {
            check(!storageFailed) { "LinkBud storage failed; recreate the client before retrying" }
            return field
        }

    fun save() {
        try { store.write(json.toString()) }
        catch (failure: Exception) {
            // Mutations may not have reached disk. Never expose or reuse this in-memory state.
            storageFailed = true
            throw failure
        }
    }
    fun installationId(): String {
        if (!json.has("installation_id")) {
            json.put("installation_id", UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", ""))
            save()
        }
        return json.getString("installation_id")
    }
    fun acknowledged(id: String): Boolean = (json.optJSONArray("acknowledged") ?: org.json.JSONArray()).let { array ->
        (0 until array.length()).any { array.getString(it) == id }
    }
    fun acknowledge(id: String): Boolean {
        if (json.optJSONObject("pending")?.optString("id") != id) return false
        val ids = json.optJSONArray("acknowledged") ?: org.json.JSONArray()
        val kept = org.json.JSONArray()
        for (i in maxOf(0, ids.length() - 63) until ids.length()) kept.put(ids.getString(i))
        kept.put(id)
        json.put("acknowledged", kept).remove("pending")
        json.remove("request")
        save()
        return true
    }
    fun pending(now: Instant): PendingDestination? {
        val pending = json.optJSONObject("pending") ?: return null
        val expiry = if (pending.isNull("expires_at")) null else Instant.parse(pending.getString("expires_at"))
        if (expiry != null && !expiry.isAfter(now)) {
            json.remove("pending")
            json.remove("request")
            save()
            return null
        }
        return PendingDestination(pending.getString("id"), pending.getString("destination"), expiry)
    }
}
