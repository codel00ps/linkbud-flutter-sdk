import java.util.Base64
import java.net.URI

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// AGP 9 creates the Kotlin extension itself; AGP 8 still needs KGP.
if (extensions.findByName("kotlin") == null) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

val defines = (project.findProperty("dart-defines") as? String).orEmpty().split(",")
    .filter { it.isNotEmpty() }.associate {
        val pair = String(Base64.getDecoder().decode(it)).split("=", limit = 2)
        pair[0] to pair.getOrElse(1) { "" }
    }
val origin = defines["LINKBUD_ORIGIN"] ?: "https://links.example.com"
val application = defines["LINKBUD_APPLICATION"] ?: "aaaaaaaaaaaaaaaaaaaaaaaaaa"
val environment = defines["LINKBUD_ENVIRONMENT"] ?: "default"
val routePrefix = defines["LINKBUD_ROUTE_PREFIX"] ?: "Ab1"
require(routePrefix.matches(Regex("[A-Za-z0-9]{3}"))) { "LINKBUD_ROUTE_PREFIX must contain three Base62 characters" }

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "dev.linkbud.linkbud_flutter_example"
    compileSdk = 36
    ndkVersion = "29.0.14206865"
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = providers.gradleProperty("linkbudPackage").getOrElse("dev.linkbud.linkbud_flutter_example")
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["linkbudHost"] = URI(origin).host
        manifestPlaceholders["linkbudPath"] = "/l/$application/$environment/"
        manifestPlaceholders["linkbudShortPath"] = "/$routePrefix/"
    }
}
extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
flutter { source = "../.." }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
