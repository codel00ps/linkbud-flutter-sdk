package dev.linkbud.sdk

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant
import java.util.Locale
import org.json.JSONObject

data class LinkBudConfig @JvmOverloads constructor(
    val origin: String, val applicationId: String, val environment: String, val sdkId: String,
    val additionalLinkHosts: Set<String> = emptySet(),
) {
    private val extraHosts = additionalLinkHosts.map(::canonicalLinkHost).toSet()
    init {
        val uri = URI(origin)
        require(uri.scheme == "https" && uri.host != null && uri.rawUserInfo == null && uri.port == -1 &&
            uri.rawQuery == null && uri.rawFragment == null && uri.rawPath in listOf("", "/")) { "Use a root HTTPS origin" }
        require(applicationId.matches(Regex("[a-z0-9]{26}")) && sdkId.matches(Regex("[a-z0-9]{26}")))
        require(environment == "default")
    }
    internal val base get() = origin.trimEnd('/')

    /** Checks URL ownership without resolving a destination or changing stored state. */
    fun canHandleUrl(url: String): Boolean = runCatching { reference(url) }.isSuccess

    internal fun reference(url: String): Pair<String, String> {
        require(url.length <= 2048)
        val uri = URI(url)
        require(uri.scheme == "https" && (uri.host == URI(origin).host || uri.host?.lowercase(Locale.ROOT) in extraHosts) && uri.port == -1 && uri.rawUserInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null)
        require(uri.rawPath.matches(Regex("/[A-Za-z0-9]{6}"))) { "Link is outside this application" }
        return "short" to uri.rawPath.removePrefix("/")
    }

    internal fun body() = JSONObject().put("sdk_id", sdkId).put("application_id", applicationId).put("environment", environment)
}

private fun canonicalLinkHost(host: String): String {
    require(host.length <= 253 && host.all { it.code < 128 }) { "Use an exact ASCII DNS hostname" }
    val canonical = host.lowercase(Locale.ROOT)
    val labels = canonical.split('.')
    require(labels.size >= 2 && labels.all { it.matches(Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")) } &&
        labels.last().any { it in 'a'..'z' }) { "Use an exact DNS hostname without scheme, wildcard, port or path" }
    return canonical
}

data class PendingDestination(val id: String, val destination: String, val expiresAt: Instant?)

sealed class LinkBudResult {
    data class Pending(val value: PendingDestination) : LinkBudResult()
    data object Empty : LinkBudResult()
    data object AlreadyAcknowledged : LinkBudResult()
    data class Retryable(val retryAt: Instant) : LinkBudResult()
    data class Rejected(val reason: String) : LinkBudResult()
}

internal fun digest(value: String): String = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(StandardCharsets.UTF_8))
    .joinToString("") { "%02x".format(it) }

internal fun referrerToken(referrer: String): String? {
    require(referrer.length <= 4096)
    val values = referrer.split('&').map { it.split('=', limit = 2) }
        .filter { URLDecoder.decode(it[0], "UTF-8") == "linkbud_token" }
    if (values.isEmpty()) return null
    require(values.size == 1 && values[0].size == 2)
    return URLDecoder.decode(values[0][1], "UTF-8").also { require(it.matches(Regex("[A-Za-z0-9]{64}"))) }
}

internal fun validatePayload(config: LinkBudConfig, json: JSONObject, now: Instant, shortCode: String? = null): Pair<String, Instant?> {
    require(json.getInt("version") == 1 && json.getString("sdk_id") == config.sdkId &&
        json.getString("application_id") == config.applicationId && json.getString("environment") == config.environment)
    require(json.getString("slug").matches(Regex("[A-Za-z0-9]{16}")))
    require(json.getString("link_host") == URI(config.origin).host)
    require(json.getString("short_code").matches(Regex("[A-Za-z0-9]{6}")))
    if (shortCode != null) require(json.getString("short_code") == shortCode)
    val path = json.getString("destination")
    require(path.length <= 2048)
    // Decode percent escapes once, matching the server's destination validator. '+' is a literal path character.
    val decoded = URLDecoder.decode(path.replace("+", "%2B"), "UTF-8")
    require(decoded.startsWith('/') && !decoded.startsWith("//") && decoded.none { it <= ' ' || it == '\u007f' || it == '\\' })
    require(json.has("expires_at"))
    Instant.parse(json.getString("resolved_at"))
    val expiry = if (json.isNull("expires_at")) null else Instant.parse(json.getString("expires_at"))
    require(expiry == null || expiry.isAfter(now))
    if (json.has("handoff_expires_at")) require(Instant.parse(json.getString("handoff_expires_at")).isAfter(now))
    return path to expiry
}
