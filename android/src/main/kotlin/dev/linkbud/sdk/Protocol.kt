package dev.linkbud.sdk

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant
import org.json.JSONObject

data class LinkBudConfig(val origin: String, val applicationId: String, val environment: String, val sdkId: String, val routePrefix: String? = null) {
    init {
        val uri = URI(origin)
        require(uri.scheme == "https" && uri.host != null && uri.rawUserInfo == null && uri.port == -1 &&
            uri.rawQuery == null && uri.rawFragment == null && uri.rawPath in listOf("", "/")) { "Use a root HTTPS origin" }
        require(applicationId.matches(Regex("[a-z0-9]{26}")) && sdkId.matches(Regex("[a-z0-9]{26}")))
        require(environment == "default")
        require(routePrefix == null || routePrefix.matches(Regex("[A-Za-z0-9]{3}")))
    }
    internal val base get() = origin.trimEnd('/')
    internal val prefix get() = "/l/$applicationId/$environment/"

    /** Checks URL ownership without resolving a destination or changing stored state. */
    fun canHandleUrl(url: String): Boolean = runCatching { reference(url) }.isSuccess

    internal fun slug(url: String): String {
        val uri = URI(url)
        require(uri.scheme == "https" && uri.host == URI(origin).host && uri.port == -1 && uri.rawUserInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null)
        val matched = prefix
        require(uri.rawPath.startsWith(matched)) { "Link is outside this application" }
        val slug = uri.rawPath.removePrefix(matched)
        require(slug.matches(Regex("[A-Za-z0-9]{16}"))) { "Link is outside this application/environment" }
        return slug
    }

    internal fun reference(url: String): Pair<String, String> {
        require(url.length <= 2048)
        val uri = URI(url)
        if (routePrefix != null && uri.rawPath?.startsWith("/$routePrefix/") == true) {
            require(uri.scheme == "https" && uri.host == URI(origin).host && uri.port == -1 && uri.rawUserInfo == null &&
                uri.rawQuery == null && uri.rawFragment == null)
            val code = uri.rawPath.removePrefix("/$routePrefix/")
            require(code.matches(Regex("[A-Za-z0-9]{6}")))
            return "short" to code
        }
        return "slug" to slug(url)
    }

    internal fun body() = JSONObject().put("sdk_id", sdkId).put("application_id", applicationId).put("environment", environment)
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

internal fun validatePayload(config: LinkBudConfig, json: JSONObject, slug: String?, now: Instant, shortCode: String? = null): Pair<String, Instant?> {
    require(json.getInt("version") == 1 && json.getString("sdk_id") == config.sdkId &&
        json.getString("application_id") == config.applicationId && json.getString("environment") == config.environment)
    require(json.getString("slug").matches(Regex("[A-Za-z0-9]{16}")))
    if (slug != null) require(json.getString("slug") == slug)
    if (shortCode != null || (slug == null && config.routePrefix != null)) {
        require(config.routePrefix != null && json.getString("route_prefix") == config.routePrefix)
        require(json.getString("short_code").matches(Regex("[A-Za-z0-9]{6}")))
        if (shortCode != null) require(json.getString("short_code") == shortCode)
    }
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
